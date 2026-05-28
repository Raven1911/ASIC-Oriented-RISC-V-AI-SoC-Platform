#ifndef SQUEEZENET_ACCEL_H
#define SQUEEZENET_ACCEL_H

#include <stdbool.h>

/*
 * SqueezeNet-96 accelerator timing runner.
 *
 * This path uses the layer schedule from config_SqueezeNet_96.txt and is a
 * bring-up scaffold: it measures accelerator conv layers plus CPU max-pool/GAP
 * stages, but does not validate classification correctness. Weight, bias,
 * IFMAP, and quantization payloads can be added later by replacing the
 * placeholder quant fields and loading the configured HyperRAM regions.
 */
bool SqueezeNet_Accel_RunTimingOnly(void);

#endif /* SQUEEZENET_ACCEL_H */
