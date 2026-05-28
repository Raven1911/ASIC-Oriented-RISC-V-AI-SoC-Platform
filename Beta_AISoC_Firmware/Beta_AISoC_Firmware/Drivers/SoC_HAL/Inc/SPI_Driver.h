#ifndef SPI_H
#define SPI_H

#include <soc_hal.h>
#include <stdbool.h> // For bool type

#define SPI0_BASE_ADDR 0x02003000U
#define SPI1_BASE_ADDR 0x02003100U
// #define SPI2_BASE_ADDR 0x02003200U

//-----------------------------------------------------------------------
// SPI Configuration Defaults
//-----------------------------------------------------------------------
#define SPI_DEFAULT_SPI_CLOCK_FREQ (10U * 1000 * 1000) // Default SPI Clock for spi_begin (e.g., 10 MHz)
#define SPI_DUMMY_BYTE 0xFFU                          // Dummy byte for SPI transfers when only reading

//-----------------------------------------------------------------------
// SPI Modes (CPOL << 1 | CPHA)
//-----------------------------------------------------------------------
#define SPI_MODE0 0x00U // CPOL = 0, CPHA = 0 (Clock idle low, data sampled on leading edge)
#define SPI_MODE1 0x01U // CPOL = 0, CPHA = 1 (Clock idle low, data sampled on trailing edge)
#define SPI_MODE2 0x02U // CPOL = 1, CPHA = 0 (Clock idle high, data sampled on leading edge)
#define SPI_MODE3 0x03U // CPOL = 1, CPHA = 1 (Clock idle high, data sampled on trailing edge)

//-----------------------------------------------------------------------
// SPI Mode Bitfield Extraction Helpers
//-----------------------------------------------------------------------
#define SPI_MODE_GET_CPOL(mode) (((mode) & 0x02U) >> 1) // Extract CPOL bit from mode
#define SPI_MODE_GET_CPHA(mode) ((mode) & 0x01U)        // Extract CPHA bit from mode

//-----------------------------------------------------------------------
// SPI Clock Polarity (CPOL) Values
//-----------------------------------------------------------------------
#define SPI_CPOL_LOW 0U  // Clock is LOW when idle (Active High)
#define SPI_CPOL_HIGH 1U // Clock is HIGH when idle (Active Low)

//-----------------------------------------------------------------------
// SPI Clock Phase (CPHA) Values
//-----------------------------------------------------------------------
#define SPI_CPHA_LEADING 0U  // Data sampled on leading edge, shifted on trailing
#define SPI_CPHA_TRAILING 1U // Data shifted on leading edge, sampled on trailing

//-----------------------------------------------------------------------
// SPI Mode Bit Masks for Extraction
//-----------------------------------------------------------------------
#define SPI_MODE_CPOL_MASK 0x02U // Mask to extract CPOL bit from mode
#define SPI_MODE_CPHA_MASK 0x01U // Mask to extract CPHA bit from mode
#define SPI_MODE_CPOL_SHIFT 1U   // Bit position of CPOL in mode byte

//-----------------------------------------------------------------------
// SPI Register Offsets (word offsets from the peripheral base address)
// These offsets are used with base_ptr in SpiDriver_t.
// E.g., to access control register: spi->base_ptr[SPI_CTRL_REG_OFFSET]
//-----------------------------------------------------------------------
#define SPI_READ_REG_OFFSET 0x00U // Offset for Read Data and Status Register
#define SPI_SS_REG_OFFSET 0x01U   // Offset for Slave Select Register
#define SPI_DATA_REG_OFFSET 0x02U // Offset for Write Data Register (Transmit Data)
#define SPI_CTRL_REG_OFFSET 0x03U // Offset for Control Register

//-----------------------------------------------------------------------
// SPI Slave Selection Defines
//-----------------------------------------------------------------------
#define SPI_SLAVE_0 (1U << 0) // Slave 0 selection bit
#define SPI_SLAVE_1 (1U << 1) // Slave 1 selection bit
#define SPI_SLAVE_2 (1U << 2) // Slave 2 selection bit
#define SPI_SLAVE_3 (1U << 3) // Slave 3 selection bit
#define SPI_SLAVE_ALL 0xFFU   // All slaves deselected
#define SPI_SLAVE_NONE 0x00U  // No slaves selected

//-----------------------------------------------------------------------
// Bitfield definitions for SPI Read Register (at SPI_READ_REG_OFFSET)
// This register is assumed to provide both received data and status.
//-----------------------------------------------------------------------
/**
 * @name SPI Read/Status Register bit definitions
 * @{
 */
/** @defgroup SPI_RXDATA Received Data
 * @brief Bits 7:0: Holds the received data byte from the SPI bus.
 * @{
 */
#define SPI_RXDATA_Pos (0U)                      /*!< RXDATA bit position */
#define SPI_RXDATA_Msk (0xFFU << SPI_RXDATA_Pos) /*!< RXDATA bit mask (bits 0-7) */
/** @} */

/** @defgroup SPI_STATUS_READY SPI Ready Status
 * @brief Bit 8: Indicates if the SPI peripheral is ready.
 * - 1: SPI is ready for a new transaction (e.g., TX buffer empty, or operation complete).
 * - 0: SPI is busy.
 * @{
 */
#define SPI_STATUS_READY_Pos (8U)                           /*!< READY bit position */
#define SPI_STATUS_READY_Msk (0x1U << SPI_STATUS_READY_Pos) /*!< READY bit mask (bit 8) */
/** @} */
/** @} */ // end of SPI Read/Status Register bit definitions

//-----------------------------------------------------------------------
// Bitfield definitions for SPI Control Register (at SPI_CTRL_REG_OFFSET)
//-----------------------------------------------------------------------
/**
 * @name SPI Control Register bit definitions
 * @{
 */
/** @defgroup SPI_CTRL_DIVIDER Clock Divider
 * @brief Bits 15:0: Sets the SPI clock rate divisor.
 * Formula: SPI_CLK = SystemClock / (2 * (DIVIDER + 1))
 * The original code implies: dvsr = (clk_freq / (2 * spi_freq)) - 1
 * So, DIVIDER field should store 'dvsr'.
 * @{
 */
#define SPI_CTRL_DIVIDER_Pos (0U)                              /*!< DIVIDER bit position */
#define SPI_CTRL_DIVIDER_Msk (0xFFFFU << SPI_CTRL_DIVIDER_Pos) /*!< DIVIDER bit mask (bits 0-15) */
/** @} */

/** @defgroup SPI_CTRL_CPOL Clock Polarity
 * @brief Bit 16: Defines the clock polarity.
 * - 0: Active high clock (SCK is low when idle).
 * - 1: Active low clock (SCK is high when idle).
 * @{
 */
#define SPI_CTRL_CPOL_Pos (16U)                       /*!< CPOL bit position */
#define SPI_CTRL_CPOL_Msk (0x1U << SPI_CTRL_CPOL_Pos) /*!< CPOL bit mask (bit 16) */
/** @} */

/** @defgroup SPI_CTRL_CPHA Clock Phase
 * @brief Bit 17: Defines the clock phase.
 * - 0: Data is sampled on the leading (first) clock edge and shifted on the trailing (second) clock edge.
 * - 1: Data is shifted on the leading (first) clock edge and sampled on the trailing (second) clock edge.
 * @{
 */
#define SPI_CTRL_CPHA_Pos (17U)                       /*!< CPHA bit position */
#define SPI_CTRL_CPHA_Msk (0x1U << SPI_CTRL_CPHA_Pos) /*!< CPHA bit mask (bit 17) */
/** @} */
/** @} */ // end of SPI Control Register bit definitions

//-----------------------------------------------------------------------
// SPI Driver Structure
//-----------------------------------------------------------------------
typedef struct
{
    volatile uint32_t *base_ptr; // Pointer to the base memory address of the SPI peripheral
} SpiDriver_t;

// Global instances (SPI0 là instance mặc định cho API mức cao)
extern SpiDriver_t spi0;
extern SpiDriver_t spi1;
// extern SpiDriver_t spi2;

//-----------------------------------------------------------------------
// Function Prototypes
//-----------------------------------------------------------------------
void spi_init(SpiDriver_t *spi, uint32_t actual_hw_base_addr);
void spi_write_reg(SpiDriver_t *spi, uint32_t offset, uint32_t value);
uint32_t spi_read_reg(SpiDriver_t *spi, uint32_t offset);
void spi_configure(SpiDriver_t *spi, uint8_t cpol, uint8_t cpha, uint32_t clk_freq, uint32_t spi_freq);
void spi_select_slave(SpiDriver_t *spi, uint32_t slave_selection_mask);
void spi_write_byte(SpiDriver_t *spi, uint8_t data);
int16_t spi_read_byte(SpiDriver_t *spi);
bool spi_is_ready(SpiDriver_t *spi);
void spi_write_string(SpiDriver_t *spi, const char *str);

/**
 * @brief Initializes and configures SPI0 with default settings.
 */
void spi_begin(void);

/**
 * @brief Disables the SPI0 peripheral or sets it to a safe state.
 */
void spi_end(void);

/**
 * @brief Transfers a single byte over SPI0 (sends and receives).
 * @param data The byte to send.
 * @return The byte received.
 */
uint8_t spi_transfer(uint8_t data);

/**
 * @brief Transfers a buffer of data over SPI0.
 * @param tx_buffer Pointer to the transmit buffer (or NULL).
 * @param rx_buffer Pointer to the receive buffer (or NULL).
 * @param length Number of bytes to transfer.
 */
void spi_transfer_buffer(const uint8_t *tx_buffer, uint8_t *rx_buffer, uint32_t length);

/**
 * @brief Sets the SPI0 data mode (CPOL and CPHA).
 * @param spi_mode The SPI mode (SPI_MODE0, SPI_MODE1, SPI_MODE2, or SPI_MODE3).
 */
void spi_set_data_mode(uint8_t spi_mode);

/**
 * @brief Sets the SPI0 clock frequency.
 * @param system_clk_freq The system clock frequency.
 * @param desired_spi_freq The desired SPI clock frequency.
 */
void spi_set_clock_frequency(uint32_t system_clk_freq, uint32_t desired_spi_freq);

/**
 * @brief Sets the slave selection mask for SPI0.
 * @param slave_selection_mask Bitmask to select slaves (e.g., 0x01 for slave 0, 0x02 for slave 1).
 */
void spi_set_slave(uint32_t slave_selection_mask);

#endif // SPI_H