#ifndef OV5640_H
#define OV5640_H

#include <stdint.h>
#include <stdbool.h>
#include "I2C_Driver.h" // Chứa định nghĩa I2CDriver_t

// Địa chỉ I2C của OV5640 (7-bit)
#define OV5640_ADDR 0x3C

// Cấu trúc lưu trữ từng dòng cấu hình
typedef struct {
    uint8_t reg_high;
    uint8_t reg_low;
    uint8_t val;
} OV5640_RegSetting;

// Prototype hàm khởi tạo, nhận vào con trỏ I2C driver
void OV5640_Init(I2CDriver_t* i2c_drv);
void OV5640_Config(I2CDriver_t* i2c_drv);
void OV5640_ResetByI2C(I2CDriver_t* i2c_drv);
void OV5640_ResetVideoIP(void);
void OV5640_ToggleVideoIP(void);
void OV5640_ApplyDefaultIsp(I2CDriver_t* i2c_drv);
void OV5640_DisableLensCorrection(I2CDriver_t* i2c_drv);
void OV5640_FreezeAwb(I2CDriver_t* i2c_drv);
void OV5640_ApplyManualColorGain(I2CDriver_t* i2c_drv);
void OV5640_ApplyNeutralLensCorrection(I2CDriver_t* i2c_drv);

#endif // OV5640_H
