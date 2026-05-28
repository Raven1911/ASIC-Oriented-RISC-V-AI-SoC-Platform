#include "../Inc/GPIO_Driver.h"
#ifdef HAL_GPIO_MODULE_ENABLED

void gpio_init()
{
    // set all pins as output by default
    volatile uint32_t *gpio_define_io_reg = (uint32_t *)(GPIO_BASE_ADDR + GPIO_DEFINE_IO_OFFSET * 4);
    *gpio_define_io_reg = 0x00; // Set all 8 pins as input
}

void pinMode(uint8_t pin, uint8_t mode)
{
    // Set pin at address GPIO_DEFINE_IO_OFFSET as input or output
    volatile uint32_t *gpio_define_io_reg = (uint32_t *)(GPIO_BASE_ADDR + GPIO_DEFINE_IO_OFFSET * 4);
    if (mode) // Output mode
    {
        *gpio_define_io_reg |= (1U << pin);
    }
    else // Input mode
    {
        *gpio_define_io_reg &= ~(1U << pin);
    }
}

void DigitalWrite(uint8_t pin, uint8_t value)
{
    volatile uint32_t *gpio_write_enable_reg = (uint32_t *)(GPIO_BASE_ADDR + GPIO_DEFINE_IO_OFFSET * 4);
    volatile uint32_t *gpio_write_port_reg = (uint32_t *)(GPIO_BASE_ADDR + GPIO_WRITE_PORT_OFFSET * 4);

        if (value)
    {
        // Set the pin high 
        *gpio_write_port_reg |= (1U << pin);
    }
    else
    {
        // Set the pin low
        *gpio_write_port_reg &= ~(1U << pin);
    }
    *gpio_write_enable_reg |= (1U << (GPIO_WRITE_ENABLE_Pos + pin));
}

uint8_t DigitalRead(uint8_t pin)
{
    volatile uint32_t *gpio_read_port_reg = (uint32_t *)(GPIO_BASE_ADDR + GPIO_READ_PORT_OFFSET * 4);
    uint32_t port_value = *gpio_read_port_reg;

    return (port_value >> pin) & 0x1U;
}

void DigitalToggle(uint8_t pin) {
    uint8_t current_state = DigitalRead(pin);
    if (current_state == HIGH) {
        DigitalWrite(pin, LOW);
    } else {
        DigitalWrite(pin, HIGH);
    }
}

#endif // HAL_GPIO_MODULE_ENABLED