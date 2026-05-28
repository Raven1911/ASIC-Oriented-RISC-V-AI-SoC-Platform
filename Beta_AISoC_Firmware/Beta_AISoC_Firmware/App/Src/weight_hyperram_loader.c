#include "weight_hyperram_loader.h"

#include "flash_utils.h"
#include "HyperRAM_Driver.h"
#include "SPI_Driver.h"
#include "UART_Driver.h"
#include "W95_HyperRAM.h"

#if WEIGHT_HYPERRAM_BANK > WEIGHT_HYPERRAM_BANK_1
#error "WEIGHT_HYPERRAM_BANK must be WEIGHT_HYPERRAM_BANK_0 or WEIGHT_HYPERRAM_BANK_1"
#endif

#if WEIGHT_HYPERRAM_COPY_CHUNK_BYTES == 0U
#error "WEIGHT_HYPERRAM_COPY_CHUNK_BYTES must be non-zero"
#endif

#if (WEIGHT_HYPERRAM_COPY_CHUNK_BYTES & 1U) != 0U
#error "WEIGHT_HYPERRAM_COPY_CHUNK_BYTES must be even for W957A8MFYA5I"
#endif

#if WEIGHT_HYPERRAM_COPY_CHUNK_BYTES > 510U
#error "WEIGHT_HYPERRAM_COPY_CHUNK_BYTES must be <= 510 bytes"
#endif

#define WEIGHT_HYPERRAM_MAX_TRANSACTION_BYTES ((WEIGHT_HYPERRAM_COPY_CHUNK_BYTES + 1U) & ~1U)

#if WEIGHT_HYPERRAM_BANK == WEIGHT_HYPERRAM_BANK_0
#define WEIGHT_HYPERRAM_ACTIVE_WRITE_CAPTURE_SHMOO WEIGHT_HYPERRAM0_WRITE_CAPTURE_SHMOO
#define WEIGHT_HYPERRAM_ACTIVE_WRITE_RECOVERY      WEIGHT_HYPERRAM0_WRITE_RECOVERY
#define WEIGHT_HYPERRAM_ACTIVE_WRITE_LATENCY       WEIGHT_HYPERRAM0_WRITE_LATENCY
#define WEIGHT_HYPERRAM_ACTIVE_READ_CAPTURE_SHMOO  WEIGHT_HYPERRAM0_READ_CAPTURE_SHMOO
#define WEIGHT_HYPERRAM_ACTIVE_READ_RECOVERY       WEIGHT_HYPERRAM0_READ_RECOVERY
#define WEIGHT_HYPERRAM_ACTIVE_READ_LATENCY        WEIGHT_HYPERRAM0_READ_LATENCY
#else
#define WEIGHT_HYPERRAM_ACTIVE_WRITE_CAPTURE_SHMOO WEIGHT_HYPERRAM1_WRITE_CAPTURE_SHMOO
#define WEIGHT_HYPERRAM_ACTIVE_WRITE_RECOVERY      WEIGHT_HYPERRAM1_WRITE_RECOVERY
#define WEIGHT_HYPERRAM_ACTIVE_WRITE_LATENCY       WEIGHT_HYPERRAM1_WRITE_LATENCY
#define WEIGHT_HYPERRAM_ACTIVE_READ_CAPTURE_SHMOO  WEIGHT_HYPERRAM1_READ_CAPTURE_SHMOO
#define WEIGHT_HYPERRAM_ACTIVE_READ_RECOVERY       WEIGHT_HYPERRAM1_READ_RECOVERY
#define WEIGHT_HYPERRAM_ACTIVE_READ_LATENCY        WEIGHT_HYPERRAM1_READ_LATENCY
#endif

static uint8_t weight_hram_staging[WEIGHT_HYPERRAM_COPY_CHUNK_BYTES + 1U];
static uint8_t weight_hram_compare[WEIGHT_HYPERRAM_COPY_CHUNK_BYTES + 1U];

static uint32_t align2(uint32_t value)
{
    return (value + 1U) & ~1U;
}

static void copy_bytes(uint8_t *dst, const uint8_t *src, uint32_t size)
{
    for (uint32_t i = 0; i < size; i++) {
        dst[i] = src[i];
    }
}

static void weight_hram_print(const char *text)
{
#if WEIGHT_HYPERRAM_LOG_ENABLED
    Uart_print(text);
#else
    (void)text;
#endif
}

static void weight_hram_println(const char *text)
{
#if WEIGHT_HYPERRAM_LOG_ENABLED
    Uart_println(text);
#else
    (void)text;
#endif
}

static void weight_hram_print_hex(const char *prefix, uint32_t value)
{
#if WEIGHT_HYPERRAM_LOG_ENABLED
    Uart_print(prefix);
    Uart_print_hex_32(value);
    Uart_println("");
#else
    (void)prefix;
    (void)value;
#endif
}

static void weight_hram_print_u8_hex(uint8_t value)
{
#if WEIGHT_HYPERRAM_LOG_ENABLED
    static const char hex_map[] = "0123456789ABCDEF";
    char text[3];

    text[0] = hex_map[(value >> 4) & 0x0FU];
    text[1] = hex_map[value & 0x0FU];
    text[2] = '\0';
    Uart_print(text);
#else
    (void)value;
#endif
}

static void weight_hram_print_bank(uint8_t bank)
{
#if WEIGHT_HYPERRAM_LOG_ENABLED
    Uart_print("HyperRAM");
    Uart_write((uint8_t)('0' + bank));
    Uart_print(" (bank ");
    Uart_write((uint8_t)('0' + bank));
    Uart_print(")");
#else
    (void)bank;
#endif
}

static HyperRAM_Driver_t *selected_hyperram(void)
{
#if WEIGHT_HYPERRAM_BANK == WEIGHT_HYPERRAM_BANK_0
    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    return &hyperram0;
#else
    HyperRAM_init(&hyperram1, HYPERRAM_1_BASE_ADDR);
    return &hyperram1;
#endif
}

static bool wait_hyperram_ready(HyperRAM_Driver_t *drv)
{
    for (uint32_t timeout = 0; timeout < WEIGHT_HYPERRAM_READY_TIMEOUT; timeout++) {
        if (HyperRAM_is_start_ready(drv)) {
            return true;
        }
    }

    return false;
}

static bool set_transaction_config(HyperRAM_Driver_t *drv,
                                   uint8_t capture_shmoo,
                                   uint8_t recovery,
                                   uint8_t latency,
                                   uint32_t size_bytes)
{
    uint32_t aligned_size = align2(size_bytes);
    uint32_t burst_halfwords = aligned_size / 2U;

    if ((aligned_size == 0U) || (burst_halfwords == 0U) || (burst_halfwords > 255U)) {
        return false;
    }

    HyperRAM_set_config(drv,
                        capture_shmoo,
                        recovery,
                        latency,
                        (uint8_t)burst_halfwords);
    return true;
}

static bool hyperram_write_transaction(HyperRAM_Driver_t *drv,
                                       uint32_t dram_addr,
                                       const uint8_t *data,
                                       uint32_t size_bytes)
{
    uint32_t aligned_size = align2(size_bytes);

    if ((data == 0) || ((dram_addr & 1U) != 0U) ||
        (aligned_size > WEIGHT_HYPERRAM_MAX_TRANSACTION_BYTES)) {
        return false;
    }

    if (!set_transaction_config(drv,
                                WEIGHT_HYPERRAM_ACTIVE_WRITE_CAPTURE_SHMOO,
                                WEIGHT_HYPERRAM_ACTIVE_WRITE_RECOVERY,
                                WEIGHT_HYPERRAM_ACTIVE_WRITE_LATENCY,
                                aligned_size)) {
        return false;
    }

    if (!wait_hyperram_ready(drv)) {
        return false;
    }

    if (!W95_SetMemoryCommandAddress(drv, dram_addr, W95_CMD_MEM_WRITE_LINEAR)) {
        return false;
    }

    HyperRAM_burst_write(drv, data, aligned_size);
    HyperRAM_start(drv);

    return true;
}

static bool hyperram_read_transaction(HyperRAM_Driver_t *drv,
                                      uint32_t dram_addr,
                                      uint8_t *data,
                                      uint32_t size_bytes)
{
    uint32_t aligned_size = align2(size_bytes);

    if ((data == 0) || ((dram_addr & 1U) != 0U) ||
        (aligned_size > WEIGHT_HYPERRAM_MAX_TRANSACTION_BYTES)) {
        return false;
    }

    if (!set_transaction_config(drv,
                                WEIGHT_HYPERRAM_ACTIVE_READ_CAPTURE_SHMOO,
                                WEIGHT_HYPERRAM_ACTIVE_READ_RECOVERY,
                                WEIGHT_HYPERRAM_ACTIVE_READ_LATENCY,
                                aligned_size)) {
        return false;
    }

    if (!wait_hyperram_ready(drv)) {
        return false;
    }

    if (!W95_SetMemoryCommandAddress(drv, dram_addr, W95_CMD_MEM_READ_LINEAR)) {
        return false;
    }

    HyperRAM_start(drv);
    HyperRAM_burst_read(drv, data, aligned_size);

    return true;
}

static bool read_source_info(WeightHyperRAM_LoadInfo_t *info, uint32_t metadata_offset)
{
    if (info == 0) {
        return false;
    }

    info->bank = (uint8_t)WEIGHT_HYPERRAM_BANK;
    info->dram_base = WEIGHT_HYPERRAM_DRAM_BASE_ADDR;
    info->dram_end = WEIGHT_HYPERRAM_DRAM_END_ADDR;

#if WEIGHT_HYPERRAM_USE_FLASH_METADATA
    WeightMetadata_t metadata;

    flash_read_data(metadata_offset,
                    (uint8_t *)&metadata,
                    sizeof(metadata));

    if ((metadata.magic != WEIGHTS_METADATA_MAGIC) ||
        (metadata.version != WEIGHTS_METADATA_VERSION)) {
        weight_hram_println("Invalid weight metadata in SPI flash.");
        weight_hram_print_hex("  Metadata addr: 0x", metadata_offset);
        return false;
    }

    info->flash_offset = metadata.base_offset;
    info->flash_size = metadata.size;
    info->flash_crc32 = metadata.crc32;
#else
    (void)metadata_offset;
    info->flash_offset = WEIGHT_HYPERRAM_MANUAL_FLASH_OFFSET;
    info->flash_size = WEIGHT_HYPERRAM_MANUAL_FLASH_SIZE;
    info->flash_crc32 = WEIGHT_HYPERRAM_MANUAL_CRC32;
#endif

    return true;
}

static bool validate_source_info(const WeightHyperRAM_LoadInfo_t *info)
{
    if (info == 0) {
        return false;
    }

    if (info->flash_size == 0U) {
        weight_hram_println("Weight size is zero.");
        return false;
    }

    if ((info->dram_base & 1U) != 0U) {
        weight_hram_println("HyperRAM destination address must be even for W957A8MFYA5I.");
        return false;
    }

    if ((info->flash_size & 1U) != 0U) {
        weight_hram_println("Weight payload size must be even for W957A8MFYA5I.");
        return false;
    }

    if (info->flash_offset < WEIGHTS_FLASH_MIN_OFFSET) {
        weight_hram_println("Weight flash offset is below the safe region.");
        return false;
    }

    if ((info->flash_offset >= SOC_FLASH_SIZE) ||
        (info->flash_size > (SOC_FLASH_SIZE - info->flash_offset))) {
        weight_hram_println("Weight flash range is outside SPI flash.");
        return false;
    }

    if ((info->dram_end != 0U) &&
        ((info->dram_base >= info->dram_end) ||
         (info->flash_size > (info->dram_end - info->dram_base)))) {
        weight_hram_println("Weight payload does not fit in the configured HyperRAM range.");
        return false;
    }

    return true;
}

static uint32_t crc32_update(uint32_t crc, const uint8_t *data, uint32_t size)
{
    for (uint32_t i = 0; i < size; i++) {
        crc ^= data[i];
        for (uint8_t bit = 0; bit < 8U; bit++) {
            crc = (crc >> 1) ^ ((uint32_t)(-((int32_t)(crc & 1U))) & 0xEDB88320U);
        }
    }

    return crc;
}

static void debug_print_byte_row(const char *label,
                                 uint32_t absolute_offset,
                                 const uint8_t *data,
                                 uint32_t size)
{
#if WEIGHT_HYPERRAM_LOG_ENABLED
    Uart_print(label);
    Uart_print(" @ +0x");
    Uart_print_hex_32(absolute_offset);
    Uart_print(":");

    for (uint32_t i = 0; i < size; i++) {
        Uart_write(' ');
        weight_hram_print_u8_hex(data[i]);
    }

    Uart_println("");
#else
    (void)label;
    (void)absolute_offset;
    (void)data;
    (void)size;
#endif
}

static bool debug_read_compare_window(const WeightHyperRAM_LoadInfo_t *info,
                                      uint32_t offset,
                                      uint32_t size)
{
    HyperRAM_Driver_t *drv = selected_hyperram();
    uint32_t read_size = align2(size);

    if ((info == 0) || (size == 0U) || (read_size > WEIGHT_HYPERRAM_MAX_TRANSACTION_BYTES)) {
        return false;
    }

    flash_read_data(info->flash_offset + offset, weight_hram_staging, size);
    if (read_size != size) {
        weight_hram_staging[size] = 0U;
    }

    return hyperram_read_transaction(drv,
                                     info->dram_base + offset,
                                     weight_hram_compare,
                                     read_size);
}

static bool debug_find_first_mismatch(const WeightHyperRAM_LoadInfo_t *info,
                                      uint32_t *mismatch_offset,
                                      uint8_t *flash_byte,
                                      uint8_t *hram_byte)
{
    uint32_t checked = 0U;

    if ((info == 0) || (mismatch_offset == 0) ||
        (flash_byte == 0) || (hram_byte == 0)) {
        return false;
    }

    while (checked < info->flash_size) {
        uint32_t chunk = info->flash_size - checked;

        if (chunk > WEIGHT_HYPERRAM_COPY_CHUNK_BYTES) {
            chunk = WEIGHT_HYPERRAM_COPY_CHUNK_BYTES;
        }

        if (!debug_read_compare_window(info, checked, chunk)) {
            return false;
        }

        for (uint32_t i = 0; i < chunk; i++) {
            if (weight_hram_staging[i] != weight_hram_compare[i]) {
                *mismatch_offset = checked + i;
                *flash_byte = weight_hram_staging[i];
                *hram_byte = weight_hram_compare[i];
                return true;
            }
        }

        checked += chunk;
    }

    return false;
}

static void debug_dump_flash_hyperram_mismatch(const WeightHyperRAM_LoadInfo_t *info)
{
#if WEIGHT_HYPERRAM_LOG_ENABLED && (WEIGHT_HYPERRAM_DEBUG_DUMP_BYTES > 0U)
    uint32_t mismatch_offset = 0U;
    uint32_t dump_offset = 0U;
    uint32_t dump_size = WEIGHT_HYPERRAM_DEBUG_DUMP_BYTES;
    uint8_t flash_byte = 0U;
    uint8_t hram_byte = 0U;

    if ((info == 0) || (info->flash_size == 0U)) {
        return;
    }

    if (dump_size > WEIGHT_HYPERRAM_COPY_CHUNK_BYTES) {
        dump_size = WEIGHT_HYPERRAM_COPY_CHUNK_BYTES;
    }

    if (dump_size > info->flash_size) {
        dump_size = info->flash_size;
    }

    if (debug_find_first_mismatch(info, &mismatch_offset, &flash_byte, &hram_byte)) {
        weight_hram_print_hex("  First mismatch offset: 0x", mismatch_offset);
        Uart_print("    Flash   : 0x");
        weight_hram_print_u8_hex(flash_byte);
        Uart_println("");
        Uart_print("    HyperRAM: 0x");
        weight_hram_print_u8_hex(hram_byte);
        Uart_println("");

        dump_offset = mismatch_offset & ~0x0FU;
        if ((dump_offset + dump_size) > info->flash_size) {
            dump_size = info->flash_size - dump_offset;
        }
    } else {
        weight_hram_println("  Could not find first mismatching byte during debug scan.");
    }

    if (!debug_read_compare_window(info, dump_offset, dump_size)) {
        weight_hram_println("  Debug dump read failed.");
        return;
    }

    weight_hram_print_hex("  Debug dump payload offset: 0x", dump_offset);
    for (uint32_t row = 0U; row < dump_size; row += 16U) {
        uint32_t row_size = dump_size - row;

        if (row_size > 16U) {
            row_size = 16U;
        }

        debug_print_byte_row("    Flash   ", dump_offset + row, &weight_hram_staging[row], row_size);
        debug_print_byte_row("    HyperRAM", dump_offset + row, &weight_hram_compare[row], row_size);
    }
#else
    (void)info;
#endif
}

static void debug_dump_flash_hyperram_success(const WeightHyperRAM_LoadInfo_t *info)
{
#if WEIGHT_HYPERRAM_LOG_ENABLED && (WEIGHT_HYPERRAM_SUCCESS_DUMP_BYTES > 0U)
    uint32_t dump_size = WEIGHT_HYPERRAM_SUCCESS_DUMP_BYTES;

    if ((info == 0) || (info->flash_size == 0U)) {
        return;
    }

    if (dump_size > WEIGHT_HYPERRAM_COPY_CHUNK_BYTES) {
        dump_size = WEIGHT_HYPERRAM_COPY_CHUNK_BYTES;
    }

    if (dump_size > info->flash_size) {
        dump_size = info->flash_size;
    }

    if (!debug_read_compare_window(info, 0U, dump_size)) {
        weight_hram_println("  Verify dump read failed.");
        return;
    }

    weight_hram_print_hex("  Verify dump payload offset: 0x", 0U);
    for (uint32_t row = 0U; row < dump_size; row += 16U) {
        uint32_t row_size = dump_size - row;

        if (row_size > 16U) {
            row_size = 16U;
        }

        debug_print_byte_row("    Flash   ", row, &weight_hram_staging[row], row_size);
        debug_print_byte_row("    HyperRAM", row, &weight_hram_compare[row], row_size);
    }
#else
    (void)info;
#endif
}

bool WeightHyperRAM_WriteBuffer(uint32_t dram_addr, const uint8_t *data, uint32_t size)
{
    HyperRAM_Driver_t *drv = selected_hyperram();
    uint32_t written = 0U;

    if ((data == 0) && (size != 0U)) {
        return false;
    }

    while (written < size) {
        uint32_t chunk = size - written;
        uint32_t write_size;

        if (chunk > WEIGHT_HYPERRAM_COPY_CHUNK_BYTES) {
            chunk = WEIGHT_HYPERRAM_COPY_CHUNK_BYTES;
        }

        copy_bytes(weight_hram_staging, &data[written], chunk);
        write_size = align2(chunk);

        if (write_size != chunk) {
            weight_hram_staging[chunk] = 0U;
        }

        if (!hyperram_write_transaction(drv,
                                        dram_addr + written,
                                        weight_hram_staging,
                                        write_size)) {
            return false;
        }

        written += chunk;
    }

    return true;
}

bool WeightHyperRAM_ReadBuffer(uint32_t dram_addr, uint8_t *data, uint32_t size)
{
    HyperRAM_Driver_t *drv = selected_hyperram();
    uint32_t read = 0U;

    if ((data == 0) && (size != 0U)) {
        return false;
    }

    while (read < size) {
        uint32_t chunk = size - read;
        uint32_t read_size;

        if (chunk > WEIGHT_HYPERRAM_COPY_CHUNK_BYTES) {
            chunk = WEIGHT_HYPERRAM_COPY_CHUNK_BYTES;
        }

        read_size = align2(chunk);
        if (!hyperram_read_transaction(drv,
                                       dram_addr + read,
                                       weight_hram_staging,
                                       read_size)) {
            return false;
        }

        copy_bytes(&data[read], weight_hram_staging, chunk);
        read += chunk;
    }

    return true;
}

bool WeightHyperRAM_Crc32(uint32_t dram_addr, uint32_t size, uint32_t *crc32_out)
{
    HyperRAM_Driver_t *drv = selected_hyperram();
    uint32_t read = 0U;
    uint32_t crc = 0xFFFFFFFFU;

    if (crc32_out == 0) {
        return false;
    }

    while (read < size) {
        uint32_t chunk = size - read;
        uint32_t read_size;

        if (chunk > WEIGHT_HYPERRAM_COPY_CHUNK_BYTES) {
            chunk = WEIGHT_HYPERRAM_COPY_CHUNK_BYTES;
        }

        read_size = align2(chunk);
        if (!hyperram_read_transaction(drv,
                                       dram_addr + read,
                                       weight_hram_staging,
                                       read_size)) {
            return false;
        }

        crc = crc32_update(crc, weight_hram_staging, chunk);
        read += chunk;
    }

    *crc32_out = ~crc;
    return true;
}

bool WeightHyperRAM_VerifyFlashToHyperRAM(const WeightHyperRAM_LoadInfo_t *info,
                                          uint32_t *flash_crc32_out,
                                          uint32_t *hram_crc32_out)
{
    uint32_t flash_crc;
    uint32_t hram_crc;

    if ((info == 0) || (info->flash_size == 0U)) {
        return false;
    }

    flash_crc = flash_crc32(info->flash_offset, info->flash_size);
    if (!WeightHyperRAM_Crc32(info->dram_base, info->flash_size, &hram_crc)) {
        return false;
    }

    if (flash_crc32_out != 0) {
        *flash_crc32_out = flash_crc;
    }

    if (hram_crc32_out != 0) {
        *hram_crc32_out = hram_crc;
    }

    if ((info->flash_crc32 != 0U) && (flash_crc != info->flash_crc32)) {
        weight_hram_println("SPI flash CRC32 does not match weight metadata.");
        weight_hram_print_hex("  Metadata CRC32: 0x", info->flash_crc32);
        weight_hram_print_hex("  Flash CRC32   : 0x", flash_crc);
        return false;
    }

    if (flash_crc != hram_crc) {
        weight_hram_println("Flash -> HyperRAM CRC32 mismatch.");
        weight_hram_print_hex("  Flash CRC32   : 0x", flash_crc);
        weight_hram_print_hex("  HyperRAM CRC32: 0x", hram_crc);
        debug_dump_flash_hyperram_mismatch(info);
        return false;
    }

    return true;
}

bool WeightHyperRAM_LoadWeightsFromFlashMetadata(uint32_t metadata_offset,
                                                 WeightHyperRAM_LoadInfo_t *info_out)
{
    WeightHyperRAM_LoadInfo_t info;
    HyperRAM_Driver_t *drv;
    uint32_t copied = 0U;

    spi_begin();

    if (!read_source_info(&info, metadata_offset) || !validate_source_info(&info)) {
        return false;
    }

    drv = selected_hyperram();

    weight_hram_println("Loading weights from SPI flash to HyperRAM...");
    weight_hram_print_hex("  Flash offset : 0x", info.flash_offset);
    weight_hram_print_hex("  Flash size   : 0x", info.flash_size);
    weight_hram_print_hex("  HyperRAM dst : 0x", info.dram_base);
    weight_hram_print_hex("  Copy chunk   : 0x", WEIGHT_HYPERRAM_COPY_CHUNK_BYTES);
    weight_hram_print("  Load target  : ");
#if WEIGHT_HYPERRAM_LOG_ENABLED
    weight_hram_print_bank(info.bank);
    Uart_println("");
#endif

    while (copied < info.flash_size) {
        uint32_t chunk = info.flash_size - copied;
        uint32_t write_size;

        if (chunk > WEIGHT_HYPERRAM_COPY_CHUNK_BYTES) {
            chunk = WEIGHT_HYPERRAM_COPY_CHUNK_BYTES;
        }

        flash_read_data(info.flash_offset + copied, weight_hram_staging, chunk);
        write_size = align2(chunk);

        if (write_size != chunk) {
            weight_hram_staging[chunk] = 0U;
        }

        if (!hyperram_write_transaction(drv,
                                        info.dram_base + copied,
                                        weight_hram_staging,
                                        write_size)) {
            weight_hram_println("HyperRAM write transaction failed.");
            return false;
        }

        copied += chunk;
    }

#if WEIGHT_HYPERRAM_VERIFY_FLASH_TO_HRAM
    {
        uint32_t flash_crc32_read;
        uint32_t hram_crc32_read;

        weight_hram_println("Verifying Flash -> HyperRAM CRC32...");
        if (!WeightHyperRAM_VerifyFlashToHyperRAM(&info,
                                                  &flash_crc32_read,
                                                  &hram_crc32_read)) {
            return false;
        }

        weight_hram_print_hex("  Flash CRC32   : 0x", flash_crc32_read);
        weight_hram_print_hex("  HyperRAM CRC32: 0x", hram_crc32_read);
        debug_dump_flash_hyperram_success(&info);
    }
#endif

    if (info_out != 0) {
        *info_out = info;
    }

    weight_hram_print("Weight load to ");
#if WEIGHT_HYPERRAM_LOG_ENABLED
    weight_hram_print_bank(info.bank);
#endif
    weight_hram_println(" complete.");
    return true;
}

bool WeightHyperRAM_LoadWeightsFromFlashEx(WeightHyperRAM_LoadInfo_t *info_out)
{
    return WeightHyperRAM_LoadWeightsFromFlashMetadata(WEIGHT_HYPERRAM_METADATA_OFFSET_ADDR,
                                                       info_out);
}

bool WeightHyperRAM_LoadWeightsFromFlash(void)
{
    return WeightHyperRAM_LoadWeightsFromFlashEx(0);
}

void WeightHyperRAM_RunFlashToHyperRAMLoaderMetadata(uint32_t metadata_offset)
{
    if (!WeightHyperRAM_LoadWeightsFromFlashMetadata(metadata_offset, 0)) {
        weight_hram_println("Weight load to HyperRAM failed.");
    }
}

void WeightHyperRAM_RunFlashToHyperRAMLoader(void)
{
    if (!WeightHyperRAM_LoadWeightsFromFlash()) {
        weight_hram_println("Weight load to HyperRAM failed.");
    }
}
