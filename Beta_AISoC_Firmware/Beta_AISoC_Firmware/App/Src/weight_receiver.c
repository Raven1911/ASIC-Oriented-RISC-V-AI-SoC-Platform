#include "weight_receiver.h"

#include "flash_utils.h"
#include "SPI_Driver.h"
#include "UART_Driver.h"
#include "timer.h"

#define FRAME_SOF 0xA5U
#define FRAME_EOF 0x55U
#define WEIGHT_MAX_PAYLOAD_SIZE 1024U
#define WEIGHT_MAX_RESPONSE_DATA_SIZE 32U
#define WEIGHT_UART_TIMEOUT_MS 5000U
#define WEIGHT_FRAME_TIMEOUT_MS 100U

/*
 * The full payload is still verified by CMD_VERIFY CRC32 at the end.
 * Per-page readback is useful for bring-up, but it doubles SPI traffic and
 * makes large weight transfers much more likely to miss UART retries.
 */
#ifndef WEIGHT_WRITE_READBACK_VERIFY
#define WEIGHT_WRITE_READBACK_VERIFY 0
#endif

#define WEIGHT_CMD_INFO 0x02U
#define WEIGHT_CMD_ERASE 0x03U
#define WEIGHT_CMD_WRITE 0x04U
#define WEIGHT_CMD_VERIFY 0x05U
#define WEIGHT_CMD_GET_CAP 0x07U

#define WEIGHT_STATUS_ACK 0x79U
#define WEIGHT_STATUS_NACK 0x1FU
#define WEIGHT_STATUS_ERROR 0xEEU

#define WEIGHT_ERR_CAT_COMM 0x01U
#define WEIGHT_ERR_CAT_LOGIC 0x02U
#define WEIGHT_ERR_CAT_FLASH 0x03U

#define WEIGHT_ERR_BAD_LENGTH 0x01U
#define WEIGHT_ERR_BAD_STATE 0x02U
#define WEIGHT_ERR_BAD_ADDRESS 0x03U
#define WEIGHT_ERR_ERASE_FAIL 0x04U
#define WEIGHT_ERR_WRITE_FAIL 0x05U
#define WEIGHT_ERR_CRC_FAIL 0x06U

typedef struct {
    uint8_t seq;
    uint8_t cmd;
    uint16_t len;
    uint8_t payload[WEIGHT_MAX_PAYLOAD_SIZE];
} WeightFrame_t;

typedef struct {
    bool declared;
    bool erased;
    uint32_t base_offset;
    uint32_t size;
    uint32_t crc32;
} WeightSession_t;

static WeightFrame_t current_frame;
static WeightSession_t session;
#if WEIGHT_WRITE_READBACK_VERIFY
static uint8_t readback_buffer[WEIGHT_MAX_PAYLOAD_SIZE];
#endif

static uint8_t last_valid_seq = 0xFFU;
static uint8_t last_response_status = WEIGHT_STATUS_ACK;
static uint16_t last_response_len = 0U;
static uint8_t last_response_data[WEIGHT_MAX_RESPONSE_DATA_SIZE];
static bool last_response_valid = false;

static uint16_t crc16_byte(uint16_t crc, uint8_t data)
{
    crc ^= ((uint16_t)data << 8);

    for (uint8_t bit = 0; bit < 8U; bit++) {
        if ((crc & 0x8000U) != 0U) {
            crc = (uint16_t)((crc << 1) ^ 0x1021U);
        } else {
            crc <<= 1;
        }
    }

    return crc;
}

static uint16_t crc16_block(uint16_t init_crc, const uint8_t *data, uint32_t length)
{
    uint16_t crc = init_crc;

    for (uint32_t i = 0; i < length; i++) {
        crc = crc16_byte(crc, data[i]);
    }

    return crc;
}

static bool uart_read_timeout(uint8_t *data, uint32_t timeout_ms)
{
    uint32_t start = millis();

    while (!Uart_read(data)) {
        if ((uint32_t)(millis() - start) >= timeout_ms) {
            return false;
        }
    }

    return true;
}

static uint32_t read_le32(const uint8_t *data)
{
    return ((uint32_t)data[0]) |
           ((uint32_t)data[1] << 8) |
           ((uint32_t)data[2] << 16) |
           ((uint32_t)data[3] << 24);
}

static uint16_t read_le16(const uint8_t *data)
{
    return ((uint16_t)data[0]) | ((uint16_t)data[1] << 8);
}

static void write_le16(uint8_t *data, uint16_t value)
{
    data[0] = (uint8_t)(value & 0xFFU);
    data[1] = (uint8_t)((value >> 8) & 0xFFU);
}

static void write_le32(uint8_t *data, uint32_t value)
{
    data[0] = (uint8_t)(value & 0xFFU);
    data[1] = (uint8_t)((value >> 8) & 0xFFU);
    data[2] = (uint8_t)((value >> 16) & 0xFFU);
    data[3] = (uint8_t)((value >> 24) & 0xFFU);
}

static bool is_valid_weight_base_offset(uint32_t base_offset)
{
    if (base_offset < WEIGHTS_FLASH_MIN_OFFSET) {
        return false;
    }

    if (base_offset >= SOC_FLASH_SIZE) {
        return false;
    }

    if ((base_offset % SOC_SECTOR_SIZE) != 0U) {
        return false;
    }

    return true;
}

static bool is_valid_weight_range(uint32_t base_offset, uint32_t size)
{
    if (!is_valid_weight_base_offset(base_offset) || (size == 0U)) {
        return false;
    }

    if (size > (SOC_FLASH_SIZE - base_offset)) {
        return false;
    }

    return true;
}

static void send_response(uint8_t seq, uint8_t status, const uint8_t *data, uint16_t len)
{
    uint8_t header[5];
    uint16_t crc;

    header[0] = FRAME_SOF;
    header[1] = seq;
    header[2] = status;
    header[3] = (uint8_t)(len & 0xFFU);
    header[4] = (uint8_t)((len >> 8) & 0xFFU);

    crc = crc16_block(0xFFFFU, &header[1], 4U);
    if ((data != 0) && (len > 0U)) {
        crc = crc16_block(crc, data, len);
    }

    for (uint8_t i = 0; i < sizeof(header); i++) {
        Uart_write(header[i]);
    }

    for (uint16_t i = 0; i < len; i++) {
        Uart_write(data[i]);
    }

    Uart_write((uint8_t)(crc & 0xFFU));
    Uart_write((uint8_t)((crc >> 8) & 0xFFU));
    Uart_write(FRAME_EOF);
}

static void cache_response(uint8_t status, const uint8_t *data, uint16_t len)
{
    last_response_status = status;
    last_response_len = 0U;
    last_response_valid = true;

    if ((data != 0) && (len > 0U)) {
        uint16_t cached_len = (len <= WEIGHT_MAX_RESPONSE_DATA_SIZE) ? len : WEIGHT_MAX_RESPONSE_DATA_SIZE;
        for (uint16_t i = 0; i < cached_len; i++) {
            last_response_data[i] = data[i];
        }
        last_response_len = cached_len;
    }
}

static void send_cached_response(uint8_t seq, uint8_t status, const uint8_t *data, uint16_t len)
{
    cache_response(status, data, len);
    send_response(seq, status, data, len);
}

static void replay_last_response(uint8_t seq)
{
    if (last_response_valid) {
        send_response(seq,
                      last_response_status,
                      (last_response_len > 0U) ? last_response_data : 0,
                      last_response_len);
    } else {
        send_response(seq, WEIGHT_STATUS_ACK, 0, 0U);
    }
}

static void send_error(uint8_t seq, uint8_t category, uint8_t code, uint32_t info)
{
    uint8_t error_payload[6];

    error_payload[0] = category;
    error_payload[1] = code;
    write_le32(&error_payload[2], info);

    send_cached_response(seq, WEIGHT_STATUS_ERROR, error_payload, sizeof(error_payload));
}

static bool receive_frame(WeightFrame_t *frame)
{
    uint8_t byte;
    uint8_t header[4];
    uint8_t crc_l;
    uint8_t crc_h;
    uint8_t eof;
    uint16_t calculated_crc;
    uint16_t received_crc;

    do {
        if (!uart_read_timeout(&byte, WEIGHT_UART_TIMEOUT_MS)) {
            return false;
        }
    } while (byte != FRAME_SOF);

    for (uint8_t i = 0; i < sizeof(header); i++) {
        if (!uart_read_timeout(&header[i], WEIGHT_FRAME_TIMEOUT_MS)) {
            return false;
        }
    }

    frame->seq = header[0];
    frame->cmd = header[1];
    frame->len = read_le16(&header[2]);

    if (frame->len > WEIGHT_MAX_PAYLOAD_SIZE) {
        send_response(frame->seq, WEIGHT_STATUS_NACK, 0, 0U);
        return false;
    }

    for (uint16_t i = 0; i < frame->len; i++) {
        if (!uart_read_timeout(&frame->payload[i], WEIGHT_FRAME_TIMEOUT_MS)) {
            send_response(frame->seq, WEIGHT_STATUS_NACK, 0, 0U);
            return false;
        }
    }

    if (!uart_read_timeout(&crc_l, WEIGHT_FRAME_TIMEOUT_MS) ||
        !uart_read_timeout(&crc_h, WEIGHT_FRAME_TIMEOUT_MS) ||
        !uart_read_timeout(&eof, WEIGHT_FRAME_TIMEOUT_MS)) {
        send_response(frame->seq, WEIGHT_STATUS_NACK, 0, 0U);
        return false;
    }

    calculated_crc = crc16_block(0xFFFFU, header, sizeof(header));
    calculated_crc = crc16_block(calculated_crc, frame->payload, frame->len);
    received_crc = ((uint16_t)crc_h << 8) | crc_l;

    if ((eof != FRAME_EOF) || (calculated_crc != received_crc)) {
        send_response(frame->seq, WEIGHT_STATUS_NACK, 0, 0U);
        return false;
    }

    return true;
}

static bool flash_write_bytes_checked(uint32_t addr, const uint8_t *data, uint32_t len)
{
    uint32_t remaining = len;
    uint32_t offset = 0U;

    while (remaining > 0U) {
        uint32_t bytes_to_page_end = SOC_PAGE_SIZE - (addr % SOC_PAGE_SIZE);
        uint32_t write_len = (remaining < bytes_to_page_end) ? remaining : bytes_to_page_end;

        if (!flash_page_program(addr, &data[offset], (uint16_t)write_len)) {
            return false;
        }

#if WEIGHT_WRITE_READBACK_VERIFY
        flash_read_data(addr, readback_buffer, write_len);
        for (uint32_t i = 0; i < write_len; i++) {
            if (readback_buffer[i] != data[offset + i]) {
                return false;
            }
        }
#endif

        addr += write_len;
        offset += write_len;
        remaining -= write_len;
    }

    return true;
}

static bool erase_weight_range(uint32_t base_offset, uint32_t size)
{
    uint32_t erase_addr = base_offset - (base_offset % SOC_SECTOR_SIZE);
    uint32_t end_addr = base_offset + size;

    while (erase_addr < end_addr) {
        if (!flash_erase_sector(erase_addr)) {
            return false;
        }
        erase_addr += SOC_SECTOR_SIZE;
    }

    return true;
}

static void handle_get_cap(const WeightFrame_t *frame)
{
    uint8_t cap[18];

    write_le32(&cap[0], SOC_FLASH_SIZE);
    write_le32(&cap[4], SOC_SECTOR_SIZE);
    write_le32(&cap[8], WEIGHTS_FLASH_MIN_OFFSET);
    write_le32(&cap[12], WEIGHTS_METADATA_OFFSET_ADDR);
    write_le16(&cap[16], WEIGHT_MAX_PAYLOAD_SIZE);

    send_cached_response(frame->seq, WEIGHT_STATUS_ACK, cap, sizeof(cap));
}

static void handle_info(const WeightFrame_t *frame)
{
    uint32_t size;
    uint32_t crc32;
    uint32_t base_offset;

    if (frame->len != 14U) {
        send_error(frame->seq, WEIGHT_ERR_CAT_LOGIC, WEIGHT_ERR_BAD_LENGTH, frame->len);
        return;
    }

    size = read_le32(&frame->payload[0]);
    crc32 = read_le32(&frame->payload[4]);
    base_offset = read_le32(&frame->payload[8]);

    if (!is_valid_weight_range(base_offset, size)) {
        send_error(frame->seq, WEIGHT_ERR_CAT_LOGIC, WEIGHT_ERR_BAD_ADDRESS, base_offset);
        return;
    }

    session.declared = true;
    session.erased = false;
    session.base_offset = base_offset;
    session.size = size;
    session.crc32 = crc32;

    send_cached_response(frame->seq, WEIGHT_STATUS_ACK, 0, 0U);
}

static void handle_erase(const WeightFrame_t *frame)
{
    uint32_t base_offset;
    uint32_t size;

    if (frame->len != 8U) {
        send_error(frame->seq, WEIGHT_ERR_CAT_LOGIC, WEIGHT_ERR_BAD_LENGTH, frame->len);
        return;
    }

    if (!session.declared) {
        send_error(frame->seq, WEIGHT_ERR_CAT_LOGIC, WEIGHT_ERR_BAD_STATE, 0U);
        return;
    }

    base_offset = read_le32(&frame->payload[0]);
    size = read_le32(&frame->payload[4]);

    if ((base_offset != session.base_offset) || (size != session.size)) {
        send_error(frame->seq, WEIGHT_ERR_CAT_LOGIC, WEIGHT_ERR_BAD_ADDRESS, base_offset);
        return;
    }

    if (!erase_weight_range(base_offset, size)) {
        send_error(frame->seq, WEIGHT_ERR_CAT_FLASH, WEIGHT_ERR_ERASE_FAIL, base_offset);
        return;
    }

    session.erased = true;
    send_cached_response(frame->seq, WEIGHT_STATUS_ACK, 0, 0U);
}

static void handle_write(const WeightFrame_t *frame)
{
    uint32_t offset;
    uint32_t data_len;
    uint32_t abs_addr;

    if (frame->len < 4U) {
        send_error(frame->seq, WEIGHT_ERR_CAT_LOGIC, WEIGHT_ERR_BAD_LENGTH, frame->len);
        return;
    }

    if (!session.declared || !session.erased) {
        send_error(frame->seq, WEIGHT_ERR_CAT_LOGIC, WEIGHT_ERR_BAD_STATE, 0U);
        return;
    }

    offset = read_le32(&frame->payload[0]);
    data_len = (uint32_t)frame->len - 4U;

    if ((offset > session.size) || (data_len > (session.size - offset))) {
        send_error(frame->seq, WEIGHT_ERR_CAT_LOGIC, WEIGHT_ERR_BAD_ADDRESS, offset + data_len);
        return;
    }

    abs_addr = session.base_offset + offset;
    if (!flash_write_bytes_checked(abs_addr, &frame->payload[4], data_len)) {
        send_error(frame->seq, WEIGHT_ERR_CAT_FLASH, WEIGHT_ERR_WRITE_FAIL, abs_addr);
        return;
    }

    send_cached_response(frame->seq, WEIGHT_STATUS_ACK, 0, 0U);
}

static void handle_verify(const WeightFrame_t *frame)
{
    uint32_t calculated_crc;
    WeightMetadata_t metadata;

    if (frame->len != 0U) {
        send_error(frame->seq, WEIGHT_ERR_CAT_LOGIC, WEIGHT_ERR_BAD_LENGTH, frame->len);
        return;
    }

    if (!session.declared || !session.erased) {
        send_error(frame->seq, WEIGHT_ERR_CAT_LOGIC, WEIGHT_ERR_BAD_STATE, 0U);
        return;
    }

    calculated_crc = flash_crc32(session.base_offset, session.size);
    if (calculated_crc != session.crc32) {
        send_error(frame->seq, WEIGHT_ERR_CAT_LOGIC, WEIGHT_ERR_CRC_FAIL, calculated_crc);
        return;
    }

    metadata.magic = WEIGHTS_METADATA_MAGIC;
    metadata.version = WEIGHTS_METADATA_VERSION;
    metadata.base_offset = session.base_offset;
    metadata.size = session.size;
    metadata.crc32 = session.crc32;

    if (!flash_erase_sector(WEIGHTS_METADATA_OFFSET_ADDR) ||
        !flash_write_bytes_checked(WEIGHTS_METADATA_OFFSET_ADDR,
                                   (const uint8_t *)&metadata,
                                   sizeof(metadata))) {
        send_error(frame->seq, WEIGHT_ERR_CAT_FLASH, WEIGHT_ERR_WRITE_FAIL, WEIGHTS_METADATA_OFFSET_ADDR);
        return;
    }

    uint8_t response[4];
    write_le32(response, calculated_crc);
    send_cached_response(frame->seq, WEIGHT_STATUS_ACK, response, sizeof(response));
}

static void process_frame(const WeightFrame_t *frame)
{
    if (last_response_valid && (frame->seq == last_valid_seq)) {
        replay_last_response(frame->seq);
        return;
    }

    last_valid_seq = frame->seq;

    switch (frame->cmd) {
    case WEIGHT_CMD_GET_CAP:
        handle_get_cap(frame);
        break;
    case WEIGHT_CMD_INFO:
        handle_info(frame);
        break;
    case WEIGHT_CMD_ERASE:
        handle_erase(frame);
        break;
    case WEIGHT_CMD_WRITE:
        handle_write(frame);
        break;
    case WEIGHT_CMD_VERIFY:
        handle_verify(frame);
        break;
    default:
        send_error(frame->seq, WEIGHT_ERR_CAT_LOGIC, WEIGHT_ERR_BAD_STATE, frame->cmd);
        break;
    }
}

void receive_and_flash_weights(void)
{
    spi_begin();

    session.declared = false;
    session.erased = false;
    last_response_valid = false;
    last_valid_seq = 0xFFU;

    while (1) {
        if (receive_frame(&current_frame)) {
            process_frame(&current_frame);

            if ((current_frame.cmd == WEIGHT_CMD_VERIFY) &&
                session.declared &&
                last_response_valid &&
                (last_response_status == WEIGHT_STATUS_ACK)) {
                break;
            }
        }
    }
}

void WeightReceiver_RunFlashLoader(void)
{
    receive_and_flash_weights();
}
