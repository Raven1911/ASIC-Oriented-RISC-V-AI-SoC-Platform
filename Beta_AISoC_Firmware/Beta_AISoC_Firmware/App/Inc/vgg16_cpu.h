#ifndef VGG16_CPU_H
#define VGG16_CPU_H

#include <stdbool.h>

/*
 * VGG16 CPU-only timing profiler.
 *
 * This path measures CPU-side compute cost for the VGG16 layer schedule without
 * using the CNN accelerator. It is intended for performance comparison, not for
 * classification correctness.
 */
bool VGG16_CPU_RunTimingOnly(void);

#endif /* VGG16_CPU_H */
