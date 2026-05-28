// /**
//  * @file example.c
//  * @brief Example application to demonstrate utilizing the Decoupled Interrupt Architecture.
//  */

// #include "picorv32_timer_hal.h"
// #include <stdbool.h>
// #include "UART_Driver.h"

// /* Global variables modified inside ISR must be declared volatile */
// volatile uint32_t g_system_uptime_ms = 10;

// /* Global timer configuration object */
// Timer_Config_t g_SystemTimer;

// /**
//  * @brief User application callback executed upon timer timeout.
//  * * @param htim Pointer to the timer configuration that caused the interrupt.
//  */
// void HAL_Timer_TimeoutCallback(const Timer_Config_t *htim) {
//     /* Optional: Ensure the interrupt came from the expected timer */
//     if (htim == &g_SystemTimer) {
//         g_system_uptime_ms++;
//         // Uart_println("A");
//     }
// }

// int main(void) {
//     /* 1. Setup Timer Configuration:
//      * - CPU Clock: 200 MHz
//      * - Prescaler: 199 (Virtual Clock = 1 MHz / 1us per tick)
//      * - Period: 1000 ticks = 1 ms
//      * - Auto-reload: Enabled
//      * - time  = (Prescaler + 1) * Period / ClockFreqHz = (199 + 1) * 1000 / 200,000,000 = 1 ms
//      */
//     Uart_begin(115200);
//     // Uart_println("System Booting... Timer & UART Test Initialized.");
//     HAL_Timer_SetConfig(&g_SystemTimer, 200000000, 199, 1000, true);

//     /* 2. Initialize and Start the hardware */
//     HAL_Timer_Init(&g_SystemTimer);
//     HAL_Timer_Start();
//     /* 3. Main Application Loop */
//     while (1) {
//         /* Example: Trigger a task every 1 second (1000 ms) */
//         if (g_system_uptime_ms >= 2000) {
//             g_system_uptime_ms = 0;
//             // Uart_println("hello");
//             Uart_println("Hello!");
//             /* Insert your periodic task logic here (e.g., toggle an LED) */
//         }
//     }

//     return 0;
// }