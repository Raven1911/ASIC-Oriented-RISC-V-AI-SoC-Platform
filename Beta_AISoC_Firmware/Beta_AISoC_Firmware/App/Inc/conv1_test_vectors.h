#ifndef CONV1_TEST_VECTORS_H
#define CONV1_TEST_VECTORS_H

#include <stdint.h>

/*
 * Generated from feature/nnom-custom:
 * - App/Inc/weights_tf.h:nnom_input_data
 * - nnom/custom/golden_outputs/conv1_op0_tid20.npy
 * Golden is stored in CHW order to match the custom tiled Conv2D output path.
 */

#define CONV1_TEST_INPUT_SIZE 784U
#define CONV1_TEST_GOLDEN_SIZE 6272U

extern const int8_t conv1_test_input_nhwc[CONV1_TEST_INPUT_SIZE];
extern const int8_t conv1_test_golden_chw[CONV1_TEST_GOLDEN_SIZE];

#endif /* CONV1_TEST_VECTORS_H */
