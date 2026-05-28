#ifndef ALLCNN_CIFAR10_ACCEL_H
#define ALLCNN_CIFAR10_ACCEL_H

#include <stdbool.h>

/*
 * ALL_CNN_C hardware accelerator helpers for real-board bring-up:
 *   - 2.3 prepares Conv1 payload, then 3.3 runs Conv1 and compares it with
 *     an in-place CPU golden.
 *   - 2.4 prepares all accelerator layer payloads, then 3.4 runs the full
 *     accelerator sequence layer-by-layer.
 */
bool AllCNN_CIFAR10_Accel_PrepareConv1Payload(void);
bool AllCNN_CIFAR10_Accel_RunConv1Bringup(void);
bool AllCNN_CIFAR10_Accel_PrepareFullPayload(void);
bool AllCNN_CIFAR10_Accel_RunFullModel(void);
bool AllCNN_CIFAR10_Accel_RunFullModelCameraIfmap(void);
bool AllCNN_CIFAR10_Accel_RunUartAccuracyStream(void);

#endif /* ALLCNN_CIFAR10_ACCEL_H */
