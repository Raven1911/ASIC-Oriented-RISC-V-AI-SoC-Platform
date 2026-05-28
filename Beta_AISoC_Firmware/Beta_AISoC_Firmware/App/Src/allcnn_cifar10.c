#include "allcnn_cifar10.h"

#include <stdint.h>

#include "HyperRAM_Driver.h"
#include "W95_HyperRAM.h"
#include "weight_hyperram_loader.h"
#include "UART_Driver.h"
#include "timer.h"

/* ────────────────────────────────────────────────────────────────────────────
 * Test image: CIFAR-10 key_00000000_label_3.png (cat)
 * From feature/nnom-custom:App/Inc/input_data.h
 * Format: HWC, 32×32×3, BGR, INT8, input_zp = 0, input_scale = 0.0156863
 * ──────────────────────────────────────────────────────────────────────────*/
static const int8_t allcnn_test_image[3072] = {
    8, -3, -9, 10, -1, -8, 13, 3, -6, 9, 1, -6, 5, -2, -7, 0, -4, -9, 6, 1,
    -3, 1, -2, -5, 0, -5, -5, 3, -1, -8, 8, 5, -8, 1, -7, 2, 0, -7, -3, 8,
    4, -10, 9, 1, -6, 10, 3, -8, 13, 5, -9, 9, 2, -10, 9, -1, -13, 12, 0,
    -12, 9, -3, -13, 5, -2, -10, 8, 0, -9, 8, 2, -9, 10, 4, -7, 3, -2, -10,
    1, -4, -1, 4, -5, -2, 10, -3, -4, 6, -1, -2, -3, -2, 1, -10, -6, 0, 0,
    -1, -3, 1, 2, -12, 6, 5, -7, 6, -1, 2, 5, -2, -1, 3, 0, -6, 5, 3, -2,
    3, 0, -4, 6, 3, -1, -3, -5, -13, 0, 0, -6, 0, -6, 5, 1, -5, -1, 10, 4,
    -13, 12, 1, -13, 15, 2, -20, 15, 3, -24, 9, 1, -20, 8, 5, -12, 10, 10,
    -3, 8, 6, -2, 6, 3, 4, 9, 2, -1, 9, -2, -7, 17, 3, -6, 12, -2, -9, 9,
    0, -5, 8, -4, -9, 10, -2, -13, 5, -2, -12, -6, -4, -6, -7, -1, 2, 0, 0,
    -7, 5, 5, -17, 8, 4, -14, 10, -4, -3, 3, -9, -8, 4, 1, -6, 4, 1, -5, 6,
    3, -5, 6, 2, -7, 7, 3, -7, 3, 2, -2, -5, -12, 0, 1, -7, -5, 13, 5, -15,
    15, 4, -16, 18, 1, -22, 21, 3, -22, 16, 6, -12, 11, 11, 0, -8, -2, -6,
    -12, -3, -3, -17, -12, -1, -11, -11, -3, 4, -2, 1, 5, -5, -5, 15, 3, 4,
    17, 6, -2, 11, 1, -13, 13, 1, -15, 10, 2, -12, 2, 1, -7, -6, -2, -3, 10,
    -4, -18, 15, 7, -21, 14, 2, -24, 22, -2, -11, 13, -5, -9, 10, 4, -3, 6,
    3, -5, 8, 3, -4, 8, 1, -7, 8, 2, -10, 1, -2, -9, 7, 1, 11, 5, -5, -2,
    3, -6, -25, 14, 3, -16, 18, 0, -11, 19, 3, -7, 27, 16, 12, -16, -14,
    -10, -14, -9, 3, -19, -8, 8, -16, 0, 23, -22, -11, 7, -25, -21, -6, -8,
    -7, 5, -22, -22, -10, 3, 0, -5, 12, 5, -7, 15, 6, -10, 13, 5, -11, 9,
    5, -5, 0, 2, -5, 12, -9, -27, 16, 6, -12, 18, 5, -10, 21, -1, -13, 16,
    0, -13, 5, -2, -14, 8, 4, -6, 5, 0, -8, 6, -2, -12, 5, -1, -17, -3,
    -10, -23, 54, 55, 54, 15, 10, 12, 3, -3, -18, 13, 7, -4, 20, 12, 14,
    -1, -10, -6, -24, -29, -22, -15, -15, -1, 1, 3, 22, -10, -2, 20, -14,
    5, 27, -14, 0, 21, -6, 5, 22, -25, -15, 1, -12, -2, 16, -9, -1, 0, 3,
    4, -2, 10, 3, -6, 11, 3, -10, 5, -2, -14, 2, -2, -10, 10, -5, -19, 1,
    0, 6, 3, 3, 9, 13, 13, 4, 11, 3, -15, 10, -1, -17, 9, 2, -10, 10, 1,
    -9, 7, -3, -15, 13, 4, -16, 5, -3, -29, 9, 0, -3, 3, -3, -1, 0, 0, -8,
    -12, -13, -13, -30, -27, -17, -17, -11, -3, -16, -13, -4, -5, 0, 9, 0,
    3, 14, -5, 0, 11, -1, 6, 17, 3, 8, 20, -14, -7, 6, -2, 4, 18, -3, 7,
    21, -31, -15, -6, -18, -10, -4, 6, 3, 0, 20, 10, 2, 14, 0, -9, 10, -1,
    -9, -4, -12, -22, -2, 6, 32, -47, -42, -21, -24, -6, -11, 17, 16, -8,
    21, 6, -14, 13, 1, -12, 12, 4, -10, 12, 3, -15, 13, 2, -25, 22, 13,
    -26, 8, -2, -15, -5, -12, -11, 3, 3, 2, -5, -3, 8, -23, -9, 3, -9, 8,
    13, -15, -2, -1, -15, -5, -6, 8, 14, 15, 8, 10, 11, -1, -3, -3, -6, -9,
    -8, 1, -1, 2, 14, 11, 16, -9, -6, 3, -14, 5, 21, -30, -14, 1, -9, -10,
    -8, 22, 8, 2, 20, 1, -10, 12, -4, -14, -8, -8, -5, -10, 4, 32, -46,
    -25, 1, -39, -20, -7, 9, 6, -7, 21, 5, -21, 13, 3, -20, 12, 2, -21, 18,
    4, -15, 12, -1, -17, 6, 9, -10, -11, -7, -18, -8, -5, -7, 7, 10, 12,
    -2, -1, 6, -11, -2, 4, -3, 9, 12, -5, 4, 6, -15, -10, -11, 9, 9, 6, 25,
    21, 19, 6, -1, -1, -9, -12, -13, 6, 3, 3, 3, -2, 0, -2, -3, 2, -23,
    -10, 2, -18, -3, 11, -16, -13, -4, 10, 3, 0, 21, 8, -11, 16, 0, -20, 16,
    19, 25, -19, -5, 17, -47, -35, -11, -1, 14, 39, 5, -1, -4, 18, -1, -27,
    13, 6, -21, 13, 8, -16, -1, -13, -23, 10, -2, -3, -37, -34, -31, -11,
    -8, -8, 7, 10, 13, 11, 11, 16, 0, 0, 4, -11, -10, -7, -9, -5, -3, -3,
    3, 6, 2, 4, 6, -18, -24, -25, 11, 3, 2, 15, 10, 11, 0, -4, -3, -10,
    -12, -13, -7, -8, -8, 2, 1, 4, -6, 0, 3, -12, -5, 4, -24, -21, -10, -7,
    -7, -5, 27, 21, 2, 18, 7, -19, 11, 16, 18, 5, 16, 35, -34, -22, -1, 0,
    12, 33, 13, 8, 4, 10, -2, -29, 10, 7, -20, -5, -3, -19, 15, 18, 23, 26,
    26, 45, 26, 17, 29, -4, -13, -4, 13, 5, 16, -4, -8, 2, 2, -3, 6, -9,
    -9, -8, -2, 2, 2, -9, -4, -1, -11, -8, -6, -13, -16, -18, 8, 1, -1, 3,
    0, 2, 5, 2, 5, 5, 2, 1, -4, -5, -6, -4, -4, -2, -1, 3, 4, 1, 6, 9,
    -12, -7, -1, -26, -26, -23, 2, -1, -7, 24, 16, -1, 13, 17, 20, -32,
    -23, -8, 5, 16, 33, -7, 6, 26, 10, 8, 3, 2, -12, -40, 18, 13, -16, -34,
    -33, -35, 27, 39, 54, 8, 16, 50, 20, 3, 23, -9, -24, -9, 13, 3, 16, -2,
    -8, 0, -6, -13, -6, 11, 12, 11, -19, -14, -16, 3, 8, 10, -22, -17, -17,
    -13, -13, -14, 24, 19, 19, 2, -2, 0, 17, 15, 18, -2, -5, -5, -6, -7,
    -7, 9, 10, 13, -6, -4, -5, -6, -2, 0, -10, -6, 5, -19, -17, -5, -19,
    -19, -11, 12, 5, -3, 18, 23, 31, -32, -25, -10, -7, 3, 21, -7, 5, 27,
    19, 16, 11, 13, -6, -34, 29, 12, -19, 0, -9, -23, -38, -33, -17, 1, 10,
    45, 15, 0, 12, 10, -2, 5, 8, -1, 5, 19, 14, 15, -5, -10, -14, 0, 0, -5,
    -5, -2, -5, -5, 1, 1, -36, -29, -28, 2, 3, 4, 38, 34, 36, -3, -5, -5,
    12, 11, 11, -14, -13, -13, -6, -6, -5, -3, -2, 1, 8, 9, 7, -5, 0, 2,
    -6, -1, 14, -14, -12, 6, -12, -8, 8, -8, -16, -20, 19, 26, 35, -38,
    -32, -18, -15, -7, 10, 0, 13, 32, 13, 10, 10, 18, 0, -24, 27, 2, -32,
    29, 9, -21, -32, -33, -29, 7, 15, 39, 5, -2, -5, -19, -24, -29, 6, 2,
    0, 23, 22, 15, 0, 1, -11, -6, -3, -12, -1, 1, -1, 13, 18, 18, -38, -32,
    -30, 15, 16, 17, 15, 10, 11, 1, 0, 0, 0, -1, 0, -7, -6, -4, -2, 0, 2,
    -6, -5, 0, 5, 5, 2, -9, -7, -4, -7, -1, 13, -12, -7, 9, -4, 1, 13,
    -12, -18, -25, 17, 20, 29, -36, -36, -24, 8, 8, 22, 15, 22, 36, -29,
    -24, -19, 5, -1, -14, 28, 7, -27, 32, 10, -26, -18, -22, -27, 7, 14,
    27, -7, -10, -17, 7, 5, -1, 4, 2, -2, 31, 32, 28, 9, 12, 6, 0, 0, -5,
    -7, -9, -10, 8, 9, 11, -25, -20, -17, 12, 13, 17, 14, 10, 14, 4, 2, 2,
    -7, -8, -7, -13, -12, -10, -6, -3, -1, -13, -13, -8, -7, -9, -10, 1, 3,
    6, -5, 0, 11, -7, -2, 8, 5, 8, 10, 0, -8, -23, 20, 21, 27, -29, -34,
    -28, 17, 12, 19, 19, 18, 26, -32, -16, -3, -19, -8, -7, 22, 8, -24, 36,
    15, -27, -17, -18, -34, -15, -2, 4, -11, -10, -14, 15, 16, 16, -9, -10,
    -5, -4, -1, 5, -13, -9, 3, 13, 8, 7, 16, 10, 7, -8, -5, -2, -33, -25,
    -17, 8, 16, 25, 11, 12, 20, -11, -10, -7, 8, 10, 12, 7, 9, 13, -5, -1,
    2, 1, 4, 8, -5, -1, -1, -1, 5, 9, 0, 9, 21, -7, 1, 7, -11, -7, -15, 11,
    5, -18, 18, 16, 20, -14, -21, -13, 15, 5, 13, 13, 2, 8, -11, 2, 17,
    -40, -20, -10, 12, 6, -5, 22, 8, -18, -7, -8, -31, 7, 16, 8, -15, -14,
    -12, 30, 31, 37, 43, 45, 54, -22, -20, -7, -2, 1, 15, 0, -5, -5, 0, -3,
    -7, -1, 5, 5, -12, -8, -10, 0, 0, -4, 6, 6, 7, 10, 12, 14, -12, -11,
    -8, -14, -13, -10, -15, -11, -10, -5, -2, 4, 1, 5, 8, 1, 7, 8, 10, 10,
    11, -7, -9, -17, 10, 3, -20, 22, 7, -23, 15, 13, 18, -16, -17, 0, 6, -2,
    13, 15, -2, 6, 18, 18, 24, -41, -28, -15, 5, 13, 33, -8, -8, 0, 17, 15,
    -11, -20, -22, -52, 15, 16, 24, 3, 2, 9, -1, -4, -3, 3, 5, 1, -7, -4,
    -15, 1, 1, -8, -9, -1, -1, -4, 4, 1, -5, -17, -39, 45, 26, -3, 18, 13,
    -6, 6, 10, 6, 6, 8, 6, 11, 11, 11, -2, -2, 0, -4, -1, 4, -5, 1, 16,
    -7, -7, 3, -2, -15, -20, 13, -10, -25, 33, 6, -17, 25, 0, -30, 23, 21,
    23, -8, -7, 10, -4, -4, 14, 3, 0, 11, 15, 20, 25, -26, -18, -13, -19,
    -17, -3, 15, 14, 22, 15, 14, -3, -8, -9, -34, 10, 9, 11, 0, -3, -3, -9,
    -11, -13, -1, -1, -5, -10, -13, -21, 4, 5, 2, -18, -7, 0, -8, 4, 9, 22,
    18, 5, 3, -7, -24, -43, -41, -52, 11, 13, 10, 20, 20, 18, -12, -13, -15,
    -5, -5, -5, -13, -9, -4, -20, -9, 3, -8, 1, 11, -5, -7, -6, 15, 8, -2,
    17, 7, -11, 13, 3, -22, 24, 17, 10, 0, 3, 12, -5, 0, 14, -6, 0, 13, 8,
    15, 19, -3, 3, 4, -24, -22, -12, 9, 8, 19, 12, 10, 13, 4, 5, -5, -12,
    -17, -19, -24, -25, -27, 16, 14, 10, 3, 1, -4, 3, -1, -8, 11, 13, 14,
    -26, -13, -3, -15, -3, 4, 20, 18, 11, 6, 1, -8, 5, 8, 3, 4, 3, -1, -11,
    -14, -17, 2, 0, -3, -17, -17, -13, -8, -4, 5, -5, -11, -28, 19, 7, -18,
    26, 10, -20, 28, 11, -26, 22, 6, -37, 30, 4, -36, 27, 10, -7, 13, 8, 4,
    -3, -2, 1, 1, 4, 10, 5, 8, 10, 7, 10, 12, -26, -23, -13, -7, -6, 10,
    -20, -18, -5, 6, 8, 14, 38, 34, 30, -24, -28, -34, 25, 20, 13, -13, -17,
    -23, 2, -2, -7, 26, 23, 23, -9, -3, 5, -31, -24, -18, 21, 14, 5, 16, 8,
    -1, 23, 26, 23, 3, 3, 0, -11, -13, -14, 1, -1, 1, -17, -15, -8, 9, 14,
    28, 22, -5, -25, 45, 7, -25, 41, 1, -32, 40, 0, -35, 40, 3, -35, 38, 0,
    -44, 17, -7, -26, 29, 18, 6, 8, 1, -7, 8, -1, -5, 10, 5, 4, 12, 13, 15,
    -13, -12, -5, -5, -3, 11, 14, 13, 29, -41, -42, -31, -14, -16, -21, -10,
    -11, -20, -16, -18, -25, -10, -12, -13, 14, 13, 17, 16, 8, 6, 9, 7, 10,
    -6, -6, -3, -6, -17, -29, 4, -5, -19, -12, -10, -15, -10, -7, -9, -7,
    -5, -5, -22, -21, -19, -8, -5, 3, -17, -10, 3, 17, 3, -24, 37, 15, -25,
    32, 10, -28, 22, 3, -35, 26, 12, -23, 25, 5, -33, -13, -28, -37, 39, 31,
    19, 7, -2, -14, 15, -4, -10, 13, 4, 3, 0, 3, 4, -34, -34, -33, -13,
    -14, -6, 37, 32, 40, 27, 25, 32, -22, -19, -18, 10, 12, 9, 14, 15, 15,
    21, 20, 25, 16, 17, 27, 23, 11, 13, 19, 14, 19, 7, 7, 12, 22, 13, 6,
    -7, -15, -23, -17, -11, -15, -15, -9, -10, -1, 2, 3, 3, 5, 10, -2, 1,
    9, -11, -5, 8, -9, 6, 19, -22, -6, 8, -16, -4, 13, -18, -3, 16, -31,
    -7, 16, -34, -8, 22, -34, -28, -16, 36, 40, 39, 12, 5, 0, 16, -2, -6,
    11, 0, 1, -2, -2, -2, -30, -32, -35, 25, 19, 18, 18, 8, 7, 29, 18, 18,
    37, 44, 46, -6, 2, 2, -5, 0, 2, 1, 4, 11, -6, -4, 6, 5, -3, 2, 0, 2,
    11, -20, -13, -1, -6, -6, -5, -3, 0, 1, -5, 7, 13, -7, 2, 5, -8, -2,
    5, -7, 0, 8, -6, 1, 11, -10, -3, 9, -25, 1, 17, -22, 4, 21, -14, 8, 23,
    -23, 0, 19, -31, 0, 26, -34, 0, 24, -47, -23, 2, -12, 7, 13, 16, 18,
    16, 19, 5, 5, 15, 4, 6, 18, 14, 12, -2, -7, -13, 33, 26, 16, 25, 12,
    -1, 44, 31, 20, -24, -13, -8, -22, -14, -11, -17, -11, -8, -20, -15, -8,
    -17, -15, -4, -16, -18, -13, -16, -8, 6, -14, -1, 16, -9, -1, 6, -12,
    2, 9, -18, 3, 14, -7, 5, 9, -6, 2, 9, -9, -2, 8, -10, 0, 9, -10, -2,
    12, -12, -3, 9, -9, -3, 9, -6, -6, 5, -6, -6, 6, -8, -2, 15, -22, -9,
    10, -40, -7, 13, -43, -13, -1, -32, -15, -10, 9, 8, 11, 25, 21, 18, -15,
    -23, -34, 19, 3, -13, 32, 18, 5, 39, 30, 23, -3, -4, 2, -28, -16, -1,
    -11, -5, 6, -10, -4, 6, -6, -1, 10, -7, -2, 9, -2, 2, 4, -6, 2, 3, -9,
    0, 4, -10, 1, 3, -11, 0, 2, -10, 3, 5, -8, 0, 3, -10, -3, 2, -6, 0, 6,
    -8, -3, 2, -2, 3, 8, 3, -1, 3, 0, -3, 4, -3, 0, 11, -8, -2, 9, -17,
    -10, 3, -21, -3, 14, -18, 10, 25, -28, 2, 10, -26, -8, -3, -15, -11, -9,
    20, 16, 13, -5, -17, -27, 37, 18, 2, 47, 30, 16, 25, 18, 13, -39, -33,
    -25, -14, -4, 11, -12, -5, 4, -7, -2, 6, -5, 1, 9, -9, -4, 4, -6, -2,
    -2, -7, -3, -3, -6, -2, -3, -10, -1, -2, -7, -1, -2, -7, 0, 0, -9, -1,
    4, -7, -1, 4, -10, -5, 2, 0, 4, 7, 2, 4, 6, 5, 5, 3, 0, 6, 9, -9, 3,
    11, -20, -8, 3, -4, 6, 15, 4, 22, 35, -19, 4, 17, -21, 3, 11, -20, -2,
    4, -20, -13, -6, -16, -18, -14, 12, 2, 0, 47, 28, 16, 50, 34, 20, -10,
    -13, -21, -20, -12, -13, -14, -6, 5, -3, 2, 9, -5, -1, 6, -12, -9, -2,
    -5, -2, 5, -2, -1, 2, -4, -2, 1, -5, -2, 1, -4, 3, 4, -5, 0, 4, -6,
    -2, 2, -7, 3, 10, 0, 9, 16, -2, 5, 11, -4, 0, 6, -8, -5, -1, -9, -2,
    2, -21, -10, -5, -17, -5, 6, -1, 12, 21, 10, 19, 26, -2, 6, 17, -17, 1,
    14, -17, 3, 12, -20, -1, 9, -15, -3, 6, -15, -13, -1, -18, -23, -15, 56,
    43, 35, 46, 35, 19, -16, -13, -22, -5, 5, -1, -9, -2, 5, -14, -10, -4,
    -1, 2, 6, -7, -5, -1, -10, -7, -3, -4, -4, -1, -2, -2, 2, 0, 1, 6, -2,
    1, 7, -6, -5, 2, 0, 3, 8, -11, -1, 7, -14, -4, 4, -7, 2, 9, -5, 3, 9,
    -7, -1, 4, -20, -10, -5, -18, -2, 7, 3, 19, 30, 3, 16, 26, -13, -8, -3,
    -9, -9, -1, -15, -1, 12, -18, 0, 6, -15, 1, 11, -17, -4, 11, -10, -2,
    13, -20, -19, -8, -2, -7, -9, 58, 53, 39, -27, -22, -31, -4, 6, -1, -5,
    2, 5, -5, 1, 3, 2, 6, 9, -2, 3, 4, 0, 5, 6, -6, -7, -4, -7, -9, -4,
    -9, -9, -3, -5, -3, 6, -3, -2, 5, -7, -5, 2, -7, 4, 9, -7, 2, 9, -7,
    1, 5, -9, -3, 2, -10, -5, -1, -13, -2, 5, -1, 14, 25, -18, -2, 10, -18,
    -7, 2, -24, -28, -27, 9, 4, 10, 4, 15, 27, -10, 1, 6, -15, -4, 3, -9,
    0, 18, -14, -5, 12, -7, 1, 11, -23, -23, -21, 2, 2, -3, -8, -3, -9,
    -13, -2, -7, -15, -8, -7, -6, 0, 2, 0, 5, 7, 2, 8, 9, 2, 8, 9, -2, 0,
    1, 3, 1, 4, 4, 1, 6, -1, 0, 6, -7, -4, 1, -7, -4, 1, -5, 1, 5, -6, -2,
    3, -12, -6, -4, -9, -4, -3, -4, 1, 2, 1, 9, 17, -6, 6, 16, -9, 5, 16,
    -5, 8, 16, -23, -18, -15, 2, 1, 6, -8, 3, 16, -5, 1, 5, -12, -10, -4,
    -3, -1, 15, -13, -4, 11, -9, 2, 10, -5, 0, 5, -10, -8, -9, -2, 5, 3,
    -9, -1, -1, -9, -4, -2, -5, 0, 1, -11, -7, -5, -11, -7, -6, -7, 0, 0,
    3, 4, 4, 6, 6, 4, 4, 2, 1, 0, 3, 2, 7, 10, 12, 6, 8, 10, -7, -5, -3,
    -7, -6, -6, -9, -5, -6, -2, 0, 1, 3, 4, 7, 17, 19, 23, 7, 14, 22, -6,
    5, 15, -25, -13, -4, -6, 3, 7, -18, -20, -13, -12, 0, 17, 2, 6, 11, -5,
    -8, -4, -6, -8, 5, -13, -4, 6, -12, 4, 9, -11, 0, 2, -10, -5, -3, -7,
    -1, 3, -10, -5, -1, -12, -6, -4, -6, 0, 1, -11, -5, -3, -2, 3, 5, -14,
    -8, -6, -18, -15, -18, -9, -9, -14, -4, -2, -5, -2, 3, 2, 6, 13, 11, 1,
    7, 5, -5, -4, -5, -1, 0, -1, -11, -10, -10, 2, 4, 4, 8, 9, 9, 20, 18,
    18, 9, 13, 17, -14, -5, 6, -27, -14, -3, -6, 3, 12, -20, -15, -7
};

/* ────────────────────────────────────────────────────────────────────────────
 * Layer metadata  (feature/nnom-custom:App/Src/layer_metadata.c)
 * Byte offsets inside the weight blob loaded into HyperRAM0 by command 2.2.
 * Layout: [4-byte size header][all weights][all biases]
 * ──────────────────────────────────────────────────────────────────────────*/
typedef struct {
    uint32_t w_offset;
    uint32_t w_size;
    uint32_t b_offset;
    uint32_t b_size;
} AllCNN_Meta_t;

static const AllCNN_Meta_t allcnn_meta[9] = {
    {       4U,   2592U, 1368484U,  384U }, /* conv2d_1  3x3 s1 3→96   */
    {    2596U,  82944U, 1368868U,  384U }, /* conv2d_2  3x3 s1 96→96  */
    {   85540U,  82944U, 1369252U,  384U }, /* conv2d_3  3x3 s2 96→96  */
    {  168484U, 165888U, 1369636U,  768U }, /* conv2d_4  3x3 s1 96→192 */
    {  334372U, 331776U, 1370404U,  768U }, /* conv2d_5  3x3 s1 192→192*/
    {  666148U, 331776U, 1371172U,  768U }, /* conv2d_6  3x3 s2 192→192*/
    {  997924U, 331776U, 1371940U,  768U }, /* conv2d_7  3x3 s1 192→192*/
    { 1329700U,  36864U, 1372708U,  768U }, /* conv2d_8  1x1 s1 192→192*/
    { 1366564U,   1920U, 1373476U,   40U }, /* conv2d_9  1x1 s1 192→10 */
};

/* ────────────────────────────────────────────────────────────────────────────
 * Quantization parameters  (feature/nnom-custom:nnom/custom/weights.h)
 * ──────────────────────────────────────────────────────────────────────────*/
typedef struct {
    int8_t   in_zp;
    int8_t   out_zp;
    int8_t   wt_zp;
    int32_t  multiplier;
    int8_t   shift;
    uint16_t in_h;
    uint16_t in_w;
    uint16_t in_c;
    uint16_t out_c;
    uint8_t  k;       /* kernel size: 3 or 1 */
    uint8_t  stride;  /* 1 or 2             */
    uint8_t  pad;     /* TFLite pad_before for top/left */
    uint8_t  same;    /* use SAME output shape; pad may still be 0 for stride=2 */
} AllCNN_Layer_t;

static const AllCNN_Layer_t allcnn_layers[9] = {
  /* in_zp out_zp wt_zp  multiplier       shift in_h in_w in_c out_c  k stride pad same */
  {  0,   -128,   0, 1455152242,  38,  32, 32,   3,  96, 3, 1, 1, 1 }, /* conv1 SAME */
  { -128, -128,   0, 1129969507,  40,  32, 32,  96,  96, 3, 1, 1, 1 }, /* conv2 SAME */
  { -128, -128,   0, 1793910186,  41,  32, 32,  96,  96, 3, 2, 0, 1 }, /* conv3 SAME stride=2 */
  { -128, -128,   0, 1090411945,  41,  16, 16,  96, 192, 3, 1, 1, 1 }, /* conv4 SAME */
  { -128, -128,   0, 1923875740,  40,  16, 16, 192, 192, 3, 1, 1, 1 }, /* conv5 SAME */
  { -128, -128,   0, 1852283115,  40,  16, 16, 192, 192, 3, 2, 0, 1 }, /* conv6 SAME stride=2 */
  { -128, -128,   0, 1241329721,  40,   8,  8, 192, 192, 3, 1, 0, 0 }, /* conv7 VALID -> 6x6 */
  { -128, -128,   0, 1540656757,  39,   6,  6, 192, 192, 1, 1, 0, 0 }, /* conv8 1x1 */
  { -128, -128,   0, 1289010565,  39,   6,  6, 192,  10, 1, 1, 0, 0 }, /* conv9 1x1 */
};

/* GlobalAvgPool quant params */
#define AVGPOOL_IN_ZP    ((int8_t)(-128))
#define AVGPOOL_OUT_ZP   ((int8_t)(-128))
#define AVGPOOL_MULT     (1779742231)
#define AVGPOOL_SHIFT    ((int8_t)(34))

static const int8_t allcnn_golden_logits[10] = {
    -62, -38, -67, 6, -87, -25, -49, -76, -95, -77
};

/* ────────────────────────────────────────────────────────────────────────────
 * HyperRAM0 memory map
 *   [0x000004 .. ~0x14F5EC]  Weight blob (loaded by cmd 2.2)
 *   [0x200000 .. 0x21FFFF]   Activation BufA  (128 KB)
 *   [0x220000 .. 0x23FFFF]   Activation BufB  (128 KB)
 * ──────────────────────────────────────────────────────────────────────────*/
#define ALLCNN_WEIGHT_BLOB_BYTES 1373516U
#define ALLCNN_BUF_A  0x00200000U
#define ALLCNN_BUF_B  0x00220000U
#define ALLCNN_BUF_BYTES 0x00020000U

/* ────────────────────────────────────────────────────────────────────────────
 * SRAM Staging Buffers
 *   Max strip : 3 rows × 32 cols × 96 ch  = 9216 B (layer 2 or 5)
 *   Max weight: 8 filters × 192 in_c × 9  = 13824 B (layers 5-7)
 *   Max bias  : 192 × 4 bytes              = 768 B
 *   Max output: 1 row × 32 cols × out_c, tile of 8 ch = 256 B
 * ──────────────────────────────────────────────────────────────────────────*/
#define ALLCNN_TILE_C     8U
#define ALLCNN_CHUNK    256U

static uint8_t allcnn_strip[9216U];   /* CHW input strip for one output row */
static uint8_t allcnn_wbuf[13824U];   /* weight tile for TILE_C filters     */
static int32_t allcnn_bias[192U];     /* bias values for current layer       */
static int8_t  allcnn_otile[256U];    /* output tile: TILE_C × out_w         */
static bool allcnn_cpu_payload_ready;

typedef struct {
    tick_t total;
    tick_t input_load;
    tick_t conv[9];
    tick_t avgpool;
} AllCNN_Profile_t;

/* ────────────────────────────────────────────────────────────────────────────
 * Helper: saturate int32 to int8
 * ──────────────────────────────────────────────────────────────────────────*/
static int8_t saturate_i8(int32_t v)
{
    if (v > 127)  return  127;
    if (v < -128) return -128;
    return (int8_t)v;
}

/* ────────────────────────────────────────────────────────────────────────────
 * Helper: asymmetric per-tensor requantize accumulator → int8
 * ──────────────────────────────────────────────────────────────────────────*/
static int8_t requantize(int32_t acc, int32_t mult, int8_t shift, int8_t out_zp)
{
    int64_t scaled = (int64_t)acc * (int64_t)mult;
    int32_t q;
    if (shift > 0) {
        scaled += ((int64_t)1 << ((uint32_t)shift - 1U));
        q = (int32_t)(scaled >> (uint32_t)shift);
    } else {
        q = (int32_t)scaled;
    }
    return saturate_i8(q + (int32_t)out_zp);
}

/* ────────────────────────────────────────────────────────────────────────────
 * Helper: read bytes from HyperRAM0 in 256-byte chunks
 * ──────────────────────────────────────────────────────────────────────────*/
static void allcnn_hram_read(W95_HandleTypeDef *w95,
                              uint32_t addr,
                              uint8_t *dst,
                              uint32_t size)
{
    uint32_t done = 0U;
    while (done < size) {
        uint32_t chunk = size - done;
        if (chunk > ALLCNN_CHUNK) chunk = ALLCNN_CHUNK;
        W95_MemoryRead(w95, addr + done, dst + done, chunk, true);
        done += chunk;
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * Helper: write bytes to HyperRAM0 in 256-byte chunks
 * ──────────────────────────────────────────────────────────────────────────*/
static void allcnn_hram_write(W95_HandleTypeDef *w95,
                               uint32_t addr,
                               const uint8_t *src,
                               uint32_t size)
{
    uint32_t done = 0U;
    while (done < size) {
        uint32_t chunk = size - done;
        if (chunk > ALLCNN_CHUNK) chunk = ALLCNN_CHUNK;
        W95_MemoryWrite(w95, addr + done, src + done, chunk, true);
        done += chunk;
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * Helper: print decimal
 * ──────────────────────────────────────────────────────────────────────────*/
static void print_dec(int32_t v)
{
    char buf[12];
    uint32_t pos = 0U;
    bool neg = (v < 0);
    uint32_t u = neg ? (uint32_t)(-(v + 1)) + 1U : (uint32_t)v;
    if (u == 0U) { Uart_write('0'); return; }
    while (u > 0U && pos < sizeof(buf)) { buf[pos++] = (char)('0' + u % 10U); u /= 10U; }
    if (neg) Uart_write('-');
    while (pos > 0U) Uart_write((uint8_t)buf[--pos]);
}

static void print_u32(uint32_t v)
{
    char buf[10];
    uint32_t pos = 0U;
    if (v == 0U) { Uart_write('0'); return; }
    while (v > 0U && pos < sizeof(buf)) {
        buf[pos++] = (char)('0' + (v % 10U));
        v /= 10U;
    }
    while (pos > 0U) Uart_write((uint8_t)buf[--pos]);
}

static void print_hex32(uint32_t v)
{
    for (int8_t shift = 28; shift >= 0; shift -= 4) {
        uint8_t nibble = (uint8_t)((v >> (uint8_t)shift) & 0xFU);
        Uart_write((uint8_t)((nibble < 10U) ? ('0' + nibble) : ('A' + nibble - 10U)));
    }
}

static tick_t allcnn_elapsed_ticks(tick_t start, tick_t end)
{
    tick_t diff;

    diff.lower = end.lower - start.lower;
    diff.upper = (end.upper - start.upper) & COUNTER_MAX_UPPER;
    if (end.lower < start.lower) {
        diff.upper = (diff.upper - 1U) & COUNTER_MAX_UPPER;
    }

    return diff;
}

static uint32_t allcnn_ticks_to_ms(tick_t ticks)
{
    /* Avoid 64-bit division: 2^32 cycles are split into whole/remainder ms. */
#define ALLCNN_LOWER_WRAP_MS  ((uint32_t)(0x100000000ULL / CYCLES_PER_MS))
#define ALLCNN_LOWER_WRAP_REM ((uint32_t)(0x100000000ULL % CYCLES_PER_MS))
    uint32_t ms = ticks.upper * ALLCNN_LOWER_WRAP_MS + ticks.lower / CYCLES_PER_MS;
    uint32_t rem = ticks.upper * ALLCNN_LOWER_WRAP_REM + ticks.lower % CYCLES_PER_MS;

    ms += rem / CYCLES_PER_MS;
    return ms;
}

static uint8_t tick_cycles_to_decimal_digits(tick_t ticks, uint8_t *digits, uint8_t max_digits)
{
    uint8_t count = 0U;
    uint32_t upper = ticks.upper & COUNTER_MAX_UPPER;
    uint32_t lower = ticks.lower;

    do {
        uint32_t q_upper = upper / 10U;
        uint32_t upper_rem = upper - q_upper * 10U;
        uint32_t q_lower = lower / 10U;
        uint32_t digit = lower - q_lower * 10U;

        /*
         * Long-divide (upper:lower) by 10 using only 32-bit division:
         * 2^32 = 10 * 429496729 + 6.
         */
        for (uint32_t i = 0U; i < upper_rem; i++) {
            q_lower += 429496729U;
            digit += 6U;
            if (digit >= 10U) {
                digit -= 10U;
                q_lower++;
            }
        }

        digits[count++] = (uint8_t)digit;
        upper = q_upper;
        lower = q_lower;
    } while (((upper != 0U) || (lower != 0U)) && (count < max_digits));

    return count;
}

static void print_spaces(uint8_t count)
{
    while (count > 0U) {
        Uart_write(' ');
        count--;
    }
}

static uint8_t string_len_u8(const char *str)
{
    uint8_t len = 0U;
    while ((str != 0) && (*str != '\0') && (len < 255U)) {
        len++;
        str++;
    }
    return len;
}

static uint8_t u32_digit_count(uint32_t v)
{
    uint8_t count = 1U;
    while (v >= 10U) {
        v /= 10U;
        count++;
    }
    return count;
}

static void print_u32_padded(uint32_t v, uint8_t width)
{
    uint8_t digits = u32_digit_count(v);
    if (width > digits) {
        print_spaces((uint8_t)(width - digits));
    }
    print_u32(v);
}

static void print_tick_cycles_dec_padded(tick_t ticks, uint8_t width)
{
    uint8_t digits[20];
    uint8_t count = tick_cycles_to_decimal_digits(ticks, digits, sizeof(digits));

    if (width > count) {
        print_spaces((uint8_t)(width - count));
    }
    while (count > 0U) {
        Uart_write((uint8_t)('0' + digits[--count]));
    }
}

static void print_tick_cycles_dec(tick_t ticks)
{
    print_tick_cycles_dec_padded(ticks, 0U);
}

static void print_tick_time(const tick_t ticks)
{
    Uart_print("cycles=");
    print_tick_cycles_dec(ticks);
    Uart_print(" (0x");
    print_hex32(ticks.upper);
    print_hex32(ticks.lower);
    Uart_print(") ms=");
    print_u32(allcnn_ticks_to_ms(ticks));
}

static tick_t allcnn_add_ticks(tick_t a, tick_t b)
{
    tick_t sum;

    sum.lower = a.lower + b.lower;
    sum.upper = (a.upper + b.upper) & COUNTER_MAX_UPPER;
    if (sum.lower < a.lower) {
        sum.upper = (sum.upper + 1U) & COUNTER_MAX_UPPER;
    }

    return sum;
}

static void print_perf_row(const char *name, tick_t ticks, const char *note)
{
    uint8_t len;

    Uart_print("  ");
    Uart_print(name);
    len = string_len_u8(name);
    print_spaces((len < 16U) ? (uint8_t)(16U - len) : 1U);
    Uart_print("  ");
    print_tick_cycles_dec_padded(ticks, 16U);
    Uart_print("  ");
    print_u32_padded(allcnn_ticks_to_ms(ticks), 8U);
    Uart_print("  ");
    Uart_println(note);
}

static void allcnn_layer_output_dims(const AllCNN_Layer_t *l,
                                     uint16_t *out_h,
                                     uint16_t *out_w)
{
    if (l->same != 0U) {
        *out_h = (uint16_t)(((uint32_t)l->in_h + (uint32_t)l->stride - 1U)
                            / (uint32_t)l->stride);
        *out_w = (uint16_t)(((uint32_t)l->in_w + (uint32_t)l->stride - 1U)
                            / (uint32_t)l->stride);
    } else {
        *out_h = (uint16_t)((((uint32_t)l->in_h - (uint32_t)l->k)
                             / (uint32_t)l->stride) + 1U);
        *out_w = (uint16_t)((((uint32_t)l->in_w - (uint32_t)l->k)
                             / (uint32_t)l->stride) + 1U);
    }
}

static uint32_t allcnn_layer_macs(uint8_t layer_idx)
{
    const AllCNN_Layer_t *l = &allcnn_layers[layer_idx];
    uint16_t out_h;
    uint16_t out_w;

    allcnn_layer_output_dims(l, &out_h, &out_w);
    return (uint32_t)out_h * (uint32_t)out_w *
           (uint32_t)l->out_c * (uint32_t)l->k * (uint32_t)l->k *
           (uint32_t)l->in_c;
}

static uint32_t allcnn_total_macs(void)
{
    uint32_t total = 0U;
    for (uint8_t i = 0U; i < 9U; i++) {
        total += allcnn_layer_macs(i);
    }
    return total;
}

static void print_layer_shape(uint8_t layer_idx)
{
    const AllCNN_Layer_t *l = &allcnn_layers[layer_idx];
    uint16_t out_h;
    uint16_t out_w;

    allcnn_layer_output_dims(l, &out_h, &out_w);
    Uart_print("  layer "); print_dec(layer_idx + 1);
    Uart_print(" ");
    print_dec(l->in_h); Uart_write('x'); print_dec(l->in_w);
    Uart_print("x"); print_dec(l->in_c);
    Uart_print(" -> ");
    print_dec(out_h); Uart_write('x'); print_dec(out_w);
    Uart_print("x"); print_dec(l->out_c);
    Uart_print(" | k="); print_dec(l->k);
    Uart_print(" s="); print_dec(l->stride);
    Uart_print(" p0="); print_dec(l->pad);
    Uart_print(" | MACs="); print_u32(allcnn_layer_macs(layer_idx));
    Uart_println("");
}

static void print_layer_profile(uint8_t layer_idx, tick_t elapsed)
{
    uint32_t ms = allcnn_ticks_to_ms(elapsed);
    uint32_t macs = allcnn_layer_macs(layer_idx);

    Uart_print("    time: ");
    print_tick_time(elapsed);
    Uart_print(" | kMAC/s=");
    print_u32((ms > 0U) ? (macs / ms) : 0U);
    Uart_println("");
}

/* ────────────────────────────────────────────────────────────────────────────
 * Load input strip for output row out_y (CHW format).
 *
 * The activation buffer in HyperRAM stores data in CHW:
 *   buf_base + ic * in_h * in_w + y * in_w
 *
 * Strip is placed in allcnn_strip as:
 *   strip[ic * k * in_w + ky_local * in_w + x]
 * where ky_local = 0..k-1 (pre-zeroed with in_zp for padding).
 * ──────────────────────────────────────────────────────────────────────────*/
static void load_strip(W95_HandleTypeDef *w95,
                       uint32_t buf_base,
                       const AllCNN_Layer_t *l,
                       uint16_t out_y)
{
    int16_t pad = (int16_t)l->pad;
    int16_t in_y0 = (int16_t)((int16_t)out_y * (int16_t)l->stride) - pad;

    /* pre-fill with in_zp so out-of-bounds rows remain zero-padded */
    {
        uint8_t fill = (uint8_t)(int8_t)l->in_zp;
        uint32_t sz  = (uint32_t)l->k * (uint32_t)l->in_w * (uint32_t)l->in_c;
        for (uint32_t fi = 0U; fi < sz; fi++) { allcnn_strip[fi] = fill; }
    }

    for (uint16_t ic = 0U; ic < l->in_c; ic++) {
        for (uint8_t ky = 0U; ky < l->k; ky++) {
            int16_t in_y = in_y0 + (int16_t)ky;
            if ((in_y < 0) || (in_y >= (int16_t)l->in_h)) continue;

            uint32_t src = buf_base
                           + (uint32_t)ic * (uint32_t)l->in_h * (uint32_t)l->in_w
                           + (uint32_t)in_y * (uint32_t)l->in_w;
            uint32_t dst_off = (uint32_t)ic * (uint32_t)l->k * (uint32_t)l->in_w
                               + (uint32_t)ky * (uint32_t)l->in_w;

            allcnn_hram_read(w95, src, allcnn_strip + dst_off, l->in_w);
        }
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * Run one Conv2D layer: ping-pong BufA → BufB, then swap pointers.
 *
     * SAME layers use out_h=ceil(in_h / stride). For 3x3 stride=2 on even
     * input sizes, TFLite uses asymmetric padding: pad_before=0, pad_after=1.
     * VALID/1x1 layers use pad=0 and normal convolution output size.
 * Weights layout in HyperRAM follows TFLite OHWI:
 *   OC, KH, KW, IC.
 * ──────────────────────────────────────────────────────────────────────────*/
static void run_conv_layer(W95_HandleTypeDef *w95,
                            uint32_t *in_addr,
                            uint32_t *out_addr,
                            uint8_t layer_idx)
{
    const AllCNN_Layer_t *l   = &allcnn_layers[layer_idx];
    const AllCNN_Meta_t  *m   = &allcnn_meta[layer_idx];
    uint16_t out_h;
    uint16_t out_w;
    int16_t pad = (int16_t)l->pad;

    allcnn_layer_output_dims(l, &out_h, &out_w);

    /* Load bias once for the whole layer */
    allcnn_hram_read(w95, m->b_offset,
                     (uint8_t *)allcnn_bias, m->b_size);

    for (uint16_t oy = 0U; oy < out_h; oy++) {
        load_strip(w95, *in_addr, l, oy);

        /* process output channels in groups of TILE_C */
        for (uint16_t oc_start = 0U; oc_start < l->out_c;
             oc_start += ALLCNN_TILE_C) {

            uint16_t tile = (uint16_t)(l->out_c - oc_start);
            if (tile > ALLCNN_TILE_C) tile = ALLCNN_TILE_C;

            /* load weight tile: tile × in_c × k × k bytes */
            uint32_t wt_size = (uint32_t)tile
                               * (uint32_t)l->in_c
                               * (uint32_t)l->k * (uint32_t)l->k;
            uint32_t wt_base = m->w_offset
                               + (uint32_t)oc_start
                               * (uint32_t)l->in_c
                               * (uint32_t)l->k * (uint32_t)l->k;
            allcnn_hram_read(w95, wt_base, allcnn_wbuf, wt_size);

            /* compute 8 output channels together for one output x */
            uint32_t kernel_span = (uint32_t)l->k * (uint32_t)l->k * (uint32_t)l->in_c;
            for (uint16_t ox = 0U; ox < out_w; ox++) {
                int32_t acc[ALLCNN_TILE_C];

                for (uint16_t t = 0U; t < tile; t++) {
                    acc[t] = allcnn_bias[oc_start + t];
                }

                for (uint16_t ic = 0U; ic < l->in_c; ic++) {
                    uint32_t strip_ic_base = (uint32_t)ic * (uint32_t)l->k * (uint32_t)l->in_w;
                    for (uint8_t ky = 0U; ky < l->k; ky++) {
                        uint32_t strip_row_base = strip_ic_base + (uint32_t)ky * (uint32_t)l->in_w;
                        for (uint8_t kx = 0U; kx < l->k; kx++) {
                            int16_t in_x = (int16_t)((int16_t)ox * (int16_t)l->stride)
                                           + (int16_t)kx - pad;
                            if ((in_x < 0) || (in_x >= (int16_t)l->in_w)) continue;

                            int32_t in_delta = (int32_t)(int8_t)allcnn_strip[strip_row_base + (uint32_t)in_x]
                                               - (int32_t)l->in_zp;
                            if (in_delta == 0) continue;

                            uint32_t wt_ic_idx = ((uint32_t)ky * (uint32_t)l->k + (uint32_t)kx)
                                                 * (uint32_t)l->in_c + (uint32_t)ic;

                            for (uint16_t t = 0U; t < tile; t++) {
                                int32_t wt_delta = (int32_t)(int8_t)allcnn_wbuf[(uint32_t)t * kernel_span + wt_ic_idx]
                                                   - (int32_t)l->wt_zp;
                                acc[t] += in_delta * wt_delta;
                            }
                        }
                    }
                }

                for (uint16_t t = 0U; t < tile; t++) {
                    allcnn_otile[(uint32_t)t * (uint32_t)out_w + (uint32_t)ox] =
                        requantize(acc[t], l->multiplier, l->shift, l->out_zp);
                }
            }

            /* write each output channel row to HyperRAM (CHW) */
            for (uint16_t t = 0U; t < tile; t++) {
                uint32_t dst = *out_addr
                               + (uint32_t)(oc_start + t)
                               * (uint32_t)out_h * (uint32_t)out_w
                               + (uint32_t)oy * (uint32_t)out_w;
                allcnn_hram_write(w95, dst,
                                  (const uint8_t *)&allcnn_otile[(uint32_t)t * (uint32_t)out_w],
                                  out_w);
            }
        }
    }

    /* swap ping-pong */
    uint32_t tmp = *in_addr;
    *in_addr  = *out_addr;
    *out_addr = tmp;
}

/* ────────────────────────────────────────────────────────────────────────────
 * GlobalAvgPool: 6×6 spatial → 10 values
 * Input: CHW at in_addr, shape 6×6×10 (after conv9)
 * Output: 10 int8 values written to out[10]
 * ──────────────────────────────────────────────────────────────────────────*/
static void run_global_avgpool(W95_HandleTypeDef *w95,
                                uint32_t in_addr,
                                int8_t *out)
{
    /* Read one 6×6 channel (36 bytes) at a time — reuses allcnn_strip as scratch */
    for (uint8_t c = 0U; c < 10U; c++) {
        allcnn_hram_read(w95, in_addr + (uint32_t)c * 36U, allcnn_strip, 36U);
        int32_t sum = 0;
        for (uint32_t i = 0U; i < 36U; i++) {
            sum += (int32_t)(int8_t)allcnn_strip[i] - (int32_t)AVGPOOL_IN_ZP;
        }
        out[c] = requantize(sum, AVGPOOL_MULT, AVGPOOL_SHIFT, AVGPOOL_OUT_ZP);
    }
}

/* ────────────────────────────────────────────────────────────────────────────
 * HWC → CHW transpose for the 32×32×3 input image.
 * Source: allcnn_test_image (HWC, 3072 bytes)
 * Dest  : HyperRAM BufA  (CHW, 3072 bytes)
 * ──────────────────────────────────────────────────────────────────────────*/
static void load_input_to_hram(W95_HandleTypeDef *w95)
{
    /* Transpose HWC→CHW one row at a time, reusing allcnn_strip as scratch.
     * Writes 32-byte rows directly to HyperRAM — no extra SRAM buffer needed. */
    for (uint32_t c = 0U; c < 3U; c++) {
        for (uint32_t y = 0U; y < 32U; y++) {
            for (uint32_t x = 0U; x < 32U; x++) {
                allcnn_strip[x] = (uint8_t)allcnn_test_image[y * 96U + x * 3U + c];
            }
            allcnn_hram_write(w95, ALLCNN_BUF_A + c * 1024U + y * 32U,
                              allcnn_strip, 32U);
        }
    }
}

const int8_t *AllCNN_CIFAR10_GetTestImageHWC(void)
{
    return allcnn_test_image;
}

bool AllCNN_CIFAR10_PrepareHyperRAM0Payload(void)
{
    WeightHyperRAM_LoadInfo_t load_info;
    W95_HandleTypeDef w95;

    if (!WeightHyperRAM_LoadWeightsFromFlashMetadata(WEIGHTS_ALLCNN_METADATA_OFFSET_ADDR,
                                                     &load_info)) {
        Uart_println("Failed to load ALLCNN weights from flash.");
        return false;
    }
    if (load_info.flash_size != ALLCNN_WEIGHT_BLOB_BYTES) {
        Uart_println("Unexpected ALLCNN weight size.");
        return false;
    }

    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    W95_Init(&w95, &hyperram0,
             WEIGHT_HYPERRAM0_READ_LATENCY,
             WEIGHT_HYPERRAM0_READ_RECOVERY,
             WEIGHT_HYPERRAM0_READ_CAPTURE_SHMOO);

    Uart_println("");
    Uart_println("=== Prepare ALL_CNN_C CPU payload ===");
    Uart_println("ALLCNN weights are loaded from flash automatically.");
    Uart_println("Loading cat image HWC -> CHW into HyperRAM0 BufA...");
    Uart_print("  IFMAP HyperRAM0 @ 0x");
    print_hex32(ALLCNN_BUF_A);
    Uart_println("");

    load_input_to_hram(&w95);
    allcnn_cpu_payload_ready = true;

    Uart_println("ALL_CNN_C CPU payload -> PASS");
    Uart_println("Run 4.0 to profile CPU inference without input-load time.");
    return true;
}

/* ────────────────────────────────────────────────────────────────────────────
 * Public entry point
 * ──────────────────────────────────────────────────────────────────────────*/
bool AllCNN_CIFAR10_RunFromHyperRAM0(void)
{
    static const char *const cifar10_labels[10] = {
        "airplane", "automobile", "bird", "cat", "deer",
        "dog",      "frog",       "horse", "ship", "truck"
    };

    W95_HandleTypeDef w95;

    if (!allcnn_cpu_payload_ready) {
        Uart_println("ALL_CNN_C CPU payload not prepared. Run 4.6 first.");
        return false;
    }

    HyperRAM_init(&hyperram0, HYPERRAM_0_BASE_ADDR);
    W95_Init(&w95, &hyperram0,
             WEIGHT_HYPERRAM0_READ_LATENCY,
             WEIGHT_HYPERRAM0_READ_RECOVERY,
             WEIGHT_HYPERRAM0_READ_CAPTURE_SHMOO);
    AllCNN_Profile_t profile;
    tick_t total_start;
    tick_t stage_start;

    Uart_println("");
    Uart_println("=======================================================");
    Uart_println("   ALL_CNN_C CIFAR-10  (feature/nnom-custom port)");
    Uart_println("=======================================================");
    Uart_println("Test image: key_00000000_label_3.png  (expected: cat)");
    Uart_println("Using prepared CPU payload from HyperRAM0.");
    Uart_println("");
    Uart_println("Benchmark notes:");
    Uart_println("  Path   : PicoRV32 firmware + HyperRAM0 weights/activations");
    Uart_println("  Timer  : SoC timer cycles and ms");
    Uart_println("  Metric : Conv MACs only; UART print time is kept outside layer timers");
    Uart_println("");
    Uart_println("Memory/workload map:");
    Uart_print("  Weight blob : HyperRAM0 0x00000000..0x");
    print_hex32(ALLCNN_WEIGHT_BLOB_BYTES);
    Uart_print(" ("); print_u32(ALLCNN_WEIGHT_BLOB_BYTES); Uart_println(" bytes)");
    Uart_print("  Act BufA    : 0x"); print_hex32(ALLCNN_BUF_A);
    Uart_print("..0x"); print_hex32(ALLCNN_BUF_A + ALLCNN_BUF_BYTES);
    Uart_print(" ("); print_u32(ALLCNN_BUF_BYTES); Uart_println(" bytes)");
    Uart_print("  Act BufB    : 0x"); print_hex32(ALLCNN_BUF_B);
    Uart_print("..0x"); print_hex32(ALLCNN_BUF_B + ALLCNN_BUF_BYTES);
    Uart_print(" ("); print_u32(ALLCNN_BUF_BYTES); Uart_println(" bytes)");
    Uart_print("  Input shape : 32x32x3 int8, HWC source -> CHW HyperRAM");
    Uart_println("");
    Uart_print("  Total Conv MACs: "); print_u32(allcnn_total_macs());
    Uart_print("  (~"); print_u32(allcnn_total_macs() * 2U);
    Uart_println(" int8 ops if MAC=mul+add)");
    Uart_println("");

    total_start = read_tick();
    Uart_println("Using prepared input image in HyperRAM0 BufA.");
    profile.input_load.lower = 0U;
    profile.input_load.upper = 0U;

    uint32_t buf_in  = ALLCNN_BUF_A;
    uint32_t buf_out = ALLCNN_BUF_B;

    Uart_println("Running inference:");
    for (uint8_t i = 0U; i < 9U; i++) {
        print_layer_shape(i);
        stage_start = read_tick();
        run_conv_layer(&w95, &buf_in, &buf_out, i);
        profile.conv[i] = allcnn_elapsed_ticks(stage_start, read_tick());
        print_layer_profile(i, profile.conv[i]);
    }

    Uart_println("Running GlobalAvgPool...");
    int8_t logits[10];
    stage_start = read_tick();
    run_global_avgpool(&w95, buf_in, logits);
    profile.avgpool = allcnn_elapsed_ticks(stage_start, read_tick());
    profile.total = allcnn_elapsed_ticks(total_start, read_tick());

    bool logits_match = true;
    for (uint8_t i = 0U; i < 10U; i++) {
        if (logits[i] != allcnn_golden_logits[i]) {
            logits_match = false;
        }
    }

    uint8_t best = 0U;
    for (uint8_t i = 1U; i < 10U; i++) {
        if (logits[i] > logits[best]) best = i;
    }

    Uart_print("Predicted: ");
    print_dec((int32_t)best);
    Uart_print(" (");
    Uart_print(cifar10_labels[best]);
    Uart_println(")");
    Uart_print("Expected : 3 (cat)  -> ");
    Uart_println((best == 3U) ? "PASS" : "FAIL");
    Uart_print("Golden logits compare -> ");
    Uart_println(logits_match ? "PASS" : "FAIL");

    tick_t conv_ticks_sum = {0U, 0U};
    for (uint8_t i = 0U; i < 9U; i++) {
        conv_ticks_sum = allcnn_add_ticks(conv_ticks_sum, profile.conv[i]);
    }
    tick_t compute_ticks = allcnn_add_ticks(conv_ticks_sum, profile.avgpool);
    tick_t stage_ticks = allcnn_add_ticks(profile.input_load, compute_ticks);
    uint32_t compute_ms = allcnn_ticks_to_ms(compute_ticks);
    uint32_t total_macs = allcnn_total_macs();

    Uart_println("");
    Uart_println("CPU-only performance baseline:");
    Uart_println("  Section              Cycles(dec)        ms  Note");
    Uart_println("  ------------------------------------------------------------");
    print_perf_row("Input load", profile.input_load, "prepared before run");
    print_perf_row("Conv layers", conv_ticks_sum, "9 Conv2D layers");
    print_perf_row("GlobalAvgPool", profile.avgpool, "final 6x6 mean");
    print_perf_row("Compute-only", compute_ticks, "Conv + GlobalAvgPool");
    print_perf_row("Stage sum", stage_ticks, "Input load + Compute");
    print_perf_row("Wall section", profile.total, "includes small UART status prints");
    Uart_println("  ------------------------------------------------------------");
    Uart_print("  Total Conv MACs      : "); print_u32(total_macs); Uart_println("");
    Uart_print("  CPU throughput       : ");
    print_u32((compute_ms > 0U) ? (total_macs / compute_ms) : 0U);
    Uart_println(" kMAC/s (compute-only)");

    Uart_println("");
    Uart_println("Golden source: feature/nnom-custom TFLite MEAN output before Softmax.");

    allcnn_cpu_payload_ready = false;
    return (best == 3U) && logits_match;
}
