/* USER CODE BEGIN Header */
/**
 ******************************************************************************
 * @file           : unit.h
 * @brief          : Header for unit.c file.
 *                   This file contains the common defines of unit tests.
 ******************************************************************************
 */
/* USER CODE END Header */

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __UNIT_H
#define __UNIT_H

#ifdef __cplusplus
extern "C"
{
#endif

    /* Local HAL config for unit tests -------------------------------------------*/

#ifndef __SOC_HAL_CONFIG_H
#define __SOC_HAL_CONFIG_H
#endif

    /* Configuration unit tests --------------------------------------------------*/

#define TEST_UART
#define TEST_I2C
#define TEST_OSPI
#define TEST_GPIO
#define TEST_TIMER

#define HAL_MODULE_ENABLED
#define HAL_SPI_MODULE_ENABLED
#define HAL_MEM_MODULE_ENABLED

#ifdef TEST_GPIO
#define HAL_GPIO_MODULE_ENABLED
#endif

#ifdef TEST_UART
#define HAL_UART_MODULE_ENABLED
#endif

#ifdef TEST_I2C
#define HAL_I2C_MODULE_ENABLED
#endif

#ifdef TEST_OSPI
#define HAL_OSPI_MODULE_ENABLED
#endif

#ifdef TEST_TIMER
#define HAL_TIMER_MODULE_ENABLED
#endif

#define SYS_CLK_FREQ 200000000U
#define CYCLES_PER_MS (SYS_CLK_FREQ / 1000UL)
#define CYCLES_PER_US (SYS_CLK_FREQ / 1000000UL)

#define VDD_VALUE ((uint32_t)3300U)
#define TICK_INT_PRIORITY ((uint32_t)0U)
#define PREFETCH_ENABLE 1U
#define INSTRUCTION_CACHE_ENABLE 1U
#define DATA_CACHE_ENABLE 1U

/* Includes ------------------------------------------------------------------*/
#include "../../Drivers/SoC_HAL/Inc/soc_hal.h"

    /* Exported functions prototypes ---------------------------------------------*/
    int main(void);

#ifdef __cplusplus
}
#endif

#endif /* __UNIT_H */
