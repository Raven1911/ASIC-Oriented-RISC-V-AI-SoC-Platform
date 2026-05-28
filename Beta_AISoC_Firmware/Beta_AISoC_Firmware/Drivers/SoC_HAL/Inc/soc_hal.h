/* USER CODE BEGIN Header */
/**
 ******************************************************************************
 * @file    soc_hal.h
 * @brief   This file contains all the functions prototypes for the HAL
 *          module driver.
 ******************************************************************************
 */
/* USER CODE END Header */

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __SOC_HAL_H
#define __SOC_HAL_H

#ifdef __cplusplus
extern "C"
{
#endif

/* Includes ------------------------------------------------------------------*/
#include "../../../App/Inc/soc_hal_config.h"
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef HAL_GPIO_MODULE_ENABLED
#include "GPIO_Driver.h"
#endif

#ifdef HAL_SPI_MODULE_ENABLED
#include "SPI_Driver.h"
#endif

#ifdef HAL_I2C_MODULE_ENABLED
#include "I2C_Driver.h"
#endif

#ifdef HAL_OSPI_MODULE_ENABLED
#include "OSPI_Driver.h"
#endif

#ifdef HAL_TIMER_MODULE_ENABLED
#include "timer.h"
#endif

#ifdef HAL_MEM_MODULE_ENABLED
#include "mem.h"
#endif

#ifdef HAL_UART_MODULE_ENABLED
#include "UART_Driver.h"
#endif

#ifdef HAL_VIDEO_STREAMING_MODULE_ENABLED
#include "VideoStreaming_Driver.h"
#endif

#ifdef HAL_INTERRUPT_MODULE_ENABLED
#include "Interrupt_Driver.h"
#endif

#ifdef HAL_CNN_ACCEL_MODULE_ENABLED
#include "CNN_Accel_Driver.h"
#endif

#ifndef __IO
#define __IO volatile
#endif

  /* Exported types ------------------------------------------------------------*/
  /** @defgroup HAL_TICK_FREQ Tick Frequency
   * @{
   */
  typedef enum
  {
    HAL_TICK_FREQ_10HZ = 100U,
    HAL_TICK_FREQ_100HZ = 10U,
    HAL_TICK_FREQ_1KHZ = 1U,
    HAL_TICK_FREQ_DEFAULT = HAL_TICK_FREQ_1KHZ
  } HAL_TickFreqTypeDef;
  /**
   * @}
   */

  /* Exported constants --------------------------------------------------------*/
  /** @defgroup HAL_Exported_Constants HAL Exported Constants
   * @{
   */

  /** @defgroup HAL_Status HAL Status
   * @{
   */
  typedef enum
  {
    HAL_OK = 0x00U,
    HAL_ERROR = 0x01U,
    HAL_BUSY = 0x02U,
    HAL_TIMEOUT = 0x03U
  } HAL_StatusTypeDef;
  /**
   * @}
   */

  /**
   * @}
   */

  /* Exported macro ------------------------------------------------------------*/

#define HAL_MAX_DELAY 0xFFFFFFFFU

  /* Exported functions --------------------------------------------------------*/
  /** @defgroup HAL_Exported_Functions HAL Exported Functions
   * @{
   */

  /** @defgroup HAL_Exported_Functions_Group1 Initialization and de-initialization Functions
   * @{
   */
  HAL_StatusTypeDef HAL_Init(void);
  HAL_StatusTypeDef HAL_DeInit(void);
  void HAL_MspInit(void);
  void HAL_MspDeInit(void);
  HAL_StatusTypeDef HAL_InitTick(uint32_t TickPriority);
  /**
   * @}
   */

  /** @defgroup HAL_Exported_Functions_Group2 HAL Control functions
   * @{
   */
  void HAL_Delay(uint32_t Delay);
  uint32_t HAL_GetTick(void);
  HAL_StatusTypeDef HAL_SetTickFreq(HAL_TickFreqTypeDef Freq);
  HAL_TickFreqTypeDef HAL_GetTickFreq(void);
  void HAL_SuspendTick(void);
  void HAL_ResumeTick(void);
  uint32_t HAL_GetREVID(void);
  uint32_t HAL_GetDEVID(void);
  /**
   * @}
   */

  /**
   * @}
   */

  /* Private types -------------------------------------------------------------*/
  /* Private variables ---------------------------------------------------------*/
  /* Private constants ---------------------------------------------------------*/
  /* Private macros ------------------------------------------------------------*/

#ifdef __cplusplus
}
#endif

#endif /* __SOC_HAL_H */
