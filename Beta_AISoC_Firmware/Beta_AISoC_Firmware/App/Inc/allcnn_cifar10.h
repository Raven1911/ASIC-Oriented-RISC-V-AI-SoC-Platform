#ifndef ALLCNN_CIFAR10_H
#define ALLCNN_CIFAR10_H

#include <stdbool.h>
#include <stdint.h>

#define ALLCNN_CIFAR10_TEST_IMAGE_BYTES 3072U

/*
 * ALL_CNN_C CIFAR-10 inference on Beta_AISoC.
 *
 * Prerequisites (same as TinyAlexNet):
 *   1. Run command 2.1 to flash Build/allcnn_cifar10_weights.hex
 *      or Build/weights.hex after regenerating it for ALL_CNN_C.
 *   2. Run command 2.2 to copy flash → HyperRAM0.
 *
 * The function loads the hardcoded CIFAR-10 test image, runs all 9 Conv2D
 * layers + GlobalAvgPool, and reports the predicted class vs. expected class 3
 * (cat, key_00000000_label_3.png from feature/nnom-custom).
 */
bool AllCNN_CIFAR10_PrepareHyperRAM0Payload(void);
bool AllCNN_CIFAR10_RunFromHyperRAM0(void);
const int8_t *AllCNN_CIFAR10_GetTestImageHWC(void);

#endif /* ALLCNN_CIFAR10_H */
