#ifndef GPIO_H
#define GPIO_H

#include <soc_hal.h>

#define GPIO_BASE_ADDR 0x02007000U

// GPIO Define IO Register Offsets and Bit Masks
#define GPIO_DEFINE_IO_OFFSET 0x00U
#define GPIO_WRITE_ENABLE_Pos 0x08U
#define GPIO_WRITE_ENABLE_Msk (0x1U << GPIO_WRITE_ENABLE_Pos)

// GPIO Port Write and Read Offsets [7:0]
#define GPIO_WRITE_PORT_OFFSET 0x01U
#define GPIO_READ_PORT_OFFSET 0x02U

#define OUTPUT 1
#define INPUT 0
#define HIGH 1
#define LOW 0

#define D0 0
#define D1 1
#define D2 2
#define D3 3
#define D4 4
#define D5 5
#define D6 6
#define D7 7

void gpio_init();

void pinMode(uint8_t pin, uint8_t mode);
void DigitalWrite(uint8_t pin, uint8_t value);
uint8_t DigitalRead(uint8_t pin);
void DigitalToggle(uint8_t pin);

#endif // GPIO_H