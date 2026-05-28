/* USER CODE BEGIN Header */
/**
 ******************************************************************************
 * @file    soc_hal_config.h
 * @brief   HAL configuration file.
 ******************************************************************************
 */
/* USER CODE END Header */

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __SOC_HAL_CONFIG_H
#define __SOC_HAL_CONFIG_H

#ifdef __cplusplus
extern "C"
{
#endif

/* Exported types ------------------------------------------------------------*/
/* Exported constants --------------------------------------------------------*/

/* ########################## Module Selection ############################## */
/**
 * @brief This is the list of modules to be used in the HAL driver
 */
#define HAL_MODULE_ENABLED
#define HAL_SPI_MODULE_ENABLED
#define HAL_MEM_MODULE_ENABLED
#define HAL_GPIO_MODULE_ENABLED
#define HAL_UART_MODULE_ENABLED
#define HAL_I2C_MODULE_ENABLED
#define HAL_OSPI_MODULE_ENABLED
#define HAL_HYPERRAM_MODULE_ENABLED
#define HAL_TIMER_MODULE_ENABLED
#define HAL_VIDEO_STREAMING_MODULE_ENABLED
#define HAL_INTERRUPT_MODULE_ENABLED
#define HAL_CNN_ACCEL_MODULE_ENABLED

  /* ########################### System Configuration ######################### */

#define SYS_CLK_FREQ 200000000U                  /* 200000000U */
#define CYCLES_PER_MS (SYS_CLK_FREQ / 1000UL)    /* 200000U */
#define CYCLES_PER_US (SYS_CLK_FREQ / 1000000UL) /* 200U */
/**
 * @brief This is the HAL system configuration section
 */
#define VDD_VALUE ((uint32_t)3300U)      /*!< Value of VDD in mv */
#define TICK_INT_PRIORITY ((uint32_t)0U) /*!< tick interrupt priority */
#define PREFETCH_ENABLE 1U
#define INSTRUCTION_CACHE_ENABLE 1U
#define DATA_CACHE_ENABLE 1U

#ifdef __cplusplus
}
#endif

#endif /* __SOC_HAL_CONFIG_H */
