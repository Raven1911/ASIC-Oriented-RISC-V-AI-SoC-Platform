#ifndef HYPERRAM_TEST_H
#define HYPERRAM_TEST_H

#include "W95_HyperRAM.h"

#ifdef __cplusplus
extern "C" {
#endif

void HyperRAM_Test_RunAll(void);
void HyperRAM_Test_RunW95(W95_HandleTypeDef *hw95, const char *port_name);
void HyperRAM_Test_RunByteDump(W95_HandleTypeDef *hw95, const char *port_name, uint32_t start_addr);

#ifdef __cplusplus
}
#endif

#endif /* HYPERRAM_TEST_H */
