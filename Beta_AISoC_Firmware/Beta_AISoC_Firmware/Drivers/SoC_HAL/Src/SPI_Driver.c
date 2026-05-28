#include "../Inc/SPI_Driver.h"
#ifdef HAL_SPI_MODULE_ENABLED

SpiDriver_t spi0;
SpiDriver_t spi1;
// SpiDriver_t spi2;
static uint32_t spi0_ctrl_shadow = 0U;

static uint32_t spi_compute_divider(uint32_t clk_freq, uint32_t spi_freq)
{
    if (spi_freq > 0U && clk_freq > (2U * spi_freq))
    {
        return (clk_freq / (2U * spi_freq)) - 1U;
    }
    return 0xFFFFU;
}

void spi_init(SpiDriver_t *spi, uint32_t actual_hw_base_addr)
{
    spi->base_ptr = (volatile uint32_t *)actual_hw_base_addr;
}

void spi_write_reg(SpiDriver_t *spi, uint32_t offset, uint32_t value)
{
    spi->base_ptr[offset] = value;
}

uint32_t spi_read_reg(SpiDriver_t *spi, uint32_t offset)
{
    return spi->base_ptr[offset];
}

void spi_configure(SpiDriver_t *spi, uint8_t cpol, uint8_t cpha, uint32_t clk_freq, uint32_t spi_freq)
{
    uint32_t dvsr = spi_compute_divider(clk_freq, spi_freq);

    uint32_t ctrl_value = 0;
    ctrl_value |= (dvsr << SPI_CTRL_DIVIDER_Pos) & SPI_CTRL_DIVIDER_Msk;
    if (cpol)
    {
        ctrl_value |= SPI_CTRL_CPOL_Msk;
    }
    if (cpha)
    {
        ctrl_value |= SPI_CTRL_CPHA_Msk;
    }

    spi0_ctrl_shadow = ctrl_value;
    spi_write_reg(spi, SPI_CTRL_REG_OFFSET, spi0_ctrl_shadow);
}

void spi_select_slave(SpiDriver_t *spi, uint32_t slave_selection_mask)
{
    spi_write_reg(spi, SPI_SS_REG_OFFSET, ~slave_selection_mask);
}

bool spi_is_ready(SpiDriver_t *spi)
{
    return (spi_read_reg(spi, SPI_READ_REG_OFFSET) & SPI_STATUS_READY_Msk) != 0;
}

void spi_write_byte(SpiDriver_t *spi, uint8_t data)
{
    while (!spi_is_ready(spi))
    {
        // Busy wait for SPI to be ready
    }
    spi_write_reg(spi, SPI_DATA_REG_OFFSET, (uint32_t)data);
}

int16_t spi_read_byte(SpiDriver_t *spi)
{
    uint32_t reg_val = spi_read_reg(spi, SPI_READ_REG_OFFSET);
    if (!(reg_val & SPI_STATUS_READY_Msk))
    {
        return -1;
    }
    return (int16_t)((reg_val & SPI_RXDATA_Msk) >> SPI_RXDATA_Pos);
}

void spi_write_string(SpiDriver_t *spi, const char *str)
{
    while (*str)
    {
        spi_write_byte(spi, (uint8_t)(*str));
        str++;
    }
}

// --- Implementation of Arduino-like Functions for spi0 ---

void spi_begin(void) {
    spi_init(&spi0, SPI0_BASE_ADDR);
    
    uint8_t cpol = ((SPI_MODE0 & SPI_MODE_CPOL_MASK) >> SPI_MODE_CPOL_SHIFT) ? SPI_CPOL_HIGH : SPI_CPOL_LOW;
    uint8_t cpha = (SPI_MODE0 & SPI_MODE_CPHA_MASK) ? SPI_CPHA_TRAILING : SPI_CPHA_LEADING;
    
    spi_configure(&spi0, cpol, cpha, SYS_CLK_FREQ, SPI_DEFAULT_SPI_CLOCK_FREQ);
}

void spi_end(void) {
    spi0_ctrl_shadow = (0xFFFFU << SPI_CTRL_DIVIDER_Pos) & SPI_CTRL_DIVIDER_Msk;
    spi_write_reg(&spi0, SPI_CTRL_REG_OFFSET, spi0_ctrl_shadow);
    spi_select_slave(&spi0, 0U); // Deselect all
}

uint8_t spi_transfer(uint8_t data) {
    spi_write_byte(&spi0, data);
    while (!spi_is_ready(&spi0)) {
        // Busy wait
    }
    uint32_t reg_val = spi_read_reg(&spi0, SPI_READ_REG_OFFSET);
    return (uint8_t)((reg_val & SPI_RXDATA_Msk) >> SPI_RXDATA_Pos);
}

void spi_transfer_buffer(const uint8_t* tx_buffer, uint8_t* rx_buffer, uint32_t length) {
    for (uint32_t i = 0; i < length; ++i) {
        uint8_t byte_to_send = (tx_buffer != NULL) ? tx_buffer[i] : SPI_DUMMY_BYTE;
        uint8_t received_byte = spi_transfer(byte_to_send);
        if (rx_buffer != NULL) {
            rx_buffer[i] = received_byte;
        }
    }
}
void spi_set_data_mode(uint8_t spi_mode) {
    uint32_t ctrl_value = spi0_ctrl_shadow;

    ctrl_value &= ~(SPI_CTRL_CPOL_Msk | SPI_CTRL_CPHA_Msk);

    if (spi_mode & 0x02) { // CPOL is bit 1 of spi_mode (e.g., SPI_MODE2 or SPI_MODE3)
        ctrl_value |= SPI_CTRL_CPOL_Msk;
    }
    if (spi_mode & 0x01) { // CPHA is bit 0 of spi_mode (e.g., SPI_MODE1 or SPI_MODE3)
        ctrl_value |= SPI_CTRL_CPHA_Msk;
    }
    spi0_ctrl_shadow = ctrl_value;
    spi_write_reg(&spi0, SPI_CTRL_REG_OFFSET, spi0_ctrl_shadow);
}

void spi_set_clock_frequency(uint32_t system_clk_freq, uint32_t desired_spi_freq) {
    uint32_t ctrl_value = spi0_ctrl_shadow;
    ctrl_value &= ~SPI_CTRL_DIVIDER_Msk;
    uint32_t dvsr = spi_compute_divider(system_clk_freq, desired_spi_freq);
    ctrl_value |= (dvsr << SPI_CTRL_DIVIDER_Pos) & SPI_CTRL_DIVIDER_Msk;
    spi0_ctrl_shadow = ctrl_value;
    spi_write_reg(&spi0, SPI_CTRL_REG_OFFSET, spi0_ctrl_shadow);
}
void spi_set_slave(uint32_t slave_selection_mask) {
    spi_select_slave(&spi0, slave_selection_mask);
}


#endif // HAL_SPI_MODULE_ENABLED