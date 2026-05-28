/* USER CODE BEGIN Header */
/**
 ******************************************************************************
 * @file    soc_hal.c
 * @brief   HAL module driver for custom RISC-V SoC.
 *          This is the common part of the HAL initialization.
 ******************************************************************************
 */
/* USER CODE END Header */

/* Includes ------------------------------------------------------------------*/
#include "soc_hal.h"

/* Private macro -------------------------------------------------------------*/
/* Private variables ---------------------------------------------------------*/
HAL_TickFreqTypeDef uwTickFreq = HAL_TICK_FREQ_DEFAULT; /* 1KHz */

/* Private function prototypes -----------------------------------------------*/
/* Exported functions --------------------------------------------------------*/

/** @defgroup HAL_Exported_Functions HAL Exported Functions
 * @{
 */

/**
 * @brief  This function is used to initialize the HAL Library; it must be the first
 *         instruction to be executed in the main program.
 * @retval HAL status
 */
HAL_StatusTypeDef HAL_Init(void)
{
  /* Init the low level hardware */
  HAL_MspInit();

  /* Initialize the timer for system tick if enabled */
#ifdef HAL_TIMER_MODULE_ENABLED
  timer_init();
#endif

  return HAL_OK;
}

/**
 * @brief  This function de-Initializes common part of the HAL.
 * @retval HAL status
 */
HAL_StatusTypeDef HAL_DeInit(void)
{
  /* De-Init the low level hardware */
  HAL_MspDeInit();

  return HAL_OK;
}

/**
 * @brief  Initialize the MSP.
 * @retval None
 */
__attribute__((weak)) void HAL_MspInit(void)
{
  /* NOTE : This function should not be modified, when the callback is needed,
            the HAL_MspInit could be implemented in the user file
   */
}

/**
 * @brief  DeInitialize the MSP.
 * @retval None
 */
__attribute__((weak)) void HAL_MspDeInit(void)
{
  /* NOTE : This function should not be modified, when the callback is needed,
            the HAL_MspDeInit could be implemented in the user file
   */
}

/**
 * @brief This function configures the source of the time base.
 * @retval HAL status
 */
__attribute__((weak)) HAL_StatusTypeDef HAL_InitTick(uint32_t TickPriority)
{
#ifdef HAL_TIMER_MODULE_ENABLED
  timer_init();
#endif
  return HAL_OK;
}

/**
 * @brief Provide a blocking delay in millisecond.
 * @param Delay specifies the delay time length, in milliseconds.
 * @retval None
 */
__attribute__((weak)) void HAL_Delay(uint32_t Delay)
{
#ifdef HAL_TIMER_MODULE_ENABLED
  delay(Delay);
#else
  uint32_t volatile wait = Delay * 1000;
  while (wait--)
    ; // Simple software loop if hardware timer is disabled
#endif
}

/**
 * @brief Provide a tick value in millisecond.
 * @retval tick value
 */
__attribute__((weak)) uint32_t HAL_GetTick(void)
{
#ifdef HAL_TIMER_MODULE_ENABLED
  return millis();
#else
  return 0;
#endif
}

/**
 * @brief Set new tick Freq.
 * @retval Status
 */
HAL_StatusTypeDef HAL_SetTickFreq(HAL_TickFreqTypeDef Freq)
{
  uwTickFreq = Freq;
  return HAL_OK;
}

/**
 * @brief Return tick frequency.
 * @retval tick period in Hz
 */
HAL_TickFreqTypeDef HAL_GetTickFreq(void)
{
  return uwTickFreq;
}

/**
 * @brief Suspend Tick increment.
 * @retval None
 */
__attribute__((weak)) void HAL_SuspendTick(void)
{
#ifdef HAL_TIMER_MODULE_ENABLED
  pause(); // Stop the hardware timer
#endif
}

/**
 * @brief Resume Tick increment.
 * @retval None
 */
__attribute__((weak)) void HAL_ResumeTick(void)
{
#ifdef HAL_TIMER_MODULE_ENABLED
  go(); // Resume the hardware timer
#endif
}

/**
 * @brief  Returns the device revision identifier.
 * @retval Device revision identifier
 */
uint32_t HAL_GetREVID(void)
{
  return 0U;
}

/**
 * @brief  Returns the device identifier.
 * @retval Device identifier
 */
uint32_t HAL_GetDEVID(void)
{
  return 0U;
}

/**
 * @}
 */