#ifndef ALLCNNC_160_ACCEL_H
#define ALLCNNC_160_ACCEL_H

#include <stdbool.h>

/*
 * ALL-CNN-C-160 accelerator path for the 160x160, 3-class camera model.
 * Conv layers run on the accelerator; final global average pooling and argmax
 * run on CPU after the camera resize path fills the layer-1 IFMAP.
 */
bool AllCNNC160_Accel_RunTimingOnly(void);
bool AllCNNC160_Accel_RunCameraResultLoop(void);

#endif /* ALLCNNC_160_ACCEL_H */
