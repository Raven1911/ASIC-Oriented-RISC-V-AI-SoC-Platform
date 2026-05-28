#ifndef ALLCNNC_96_QAT_SYMPAD_ACCEL_H
#define ALLCNNC_96_QAT_SYMPAD_ACCEL_H

#include <stdbool.h>

/*
 * QAT SymPad ALL-CNN-C-96 accelerator path for the 96x96, 3-class camera model.
 * Conv layers run on the accelerator; final global average pooling and argmax
 * run on CPU after the camera resize path fills the layer-1 IFMAP.
 */
bool AllCNNC96QATSymPad_Accel_RunTimingOnly(void);
bool AllCNNC96QATSymPad_Accel_RunCameraResultLoop(void);

#endif /* ALLCNNC_96_QAT_SYMPAD_ACCEL_H */
