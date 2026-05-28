#ifndef VGG16_ACCEL_H
#define VGG16_ACCEL_H

#include <stdbool.h>

/*
 * VGG16 accelerator timing runner.
 *
 * This path is intended for performance bring-up only. It programs the CNN
 * accelerator with the VGG16 layer table, uses HyperRAM0 for filter/bias
 * traffic and HyperRAM1 for activation traffic, then reports per-layer timing.
 * It does not validate classification correctness.
 */
bool VGG16_Accel_RunTimingOnly(void);
bool VGG16_Accel_RunLayer11Only(void);
bool VGG16_Accel_RunLayer12Only(void);
bool VGG16_Accel_RunLayer11WithFakeInput(void);
bool VGG16_Accel_RunLayer11LowAddress(void);
bool VGG16_Accel_RunLayer10ThenLayer11LowAddress(void);
bool VGG16_Accel_RunLayer10ThenTwoLowAddress(void);

#endif /* VGG16_ACCEL_H */
