#include "../Inc/main.h"
#include "hyperram_test.h"
#include "ov5640.h"
#include "system_init.h"
#include "weight_hyperram_loader.h"
#include "weight_receiver.h"

#ifndef ENABLE_ALLCNN_CPU_MENU
#define ENABLE_ALLCNN_CPU_MENU 0
#endif

#ifndef ENABLE_ALLCNN_ACCEL_MENU
#define ENABLE_ALLCNN_ACCEL_MENU 0
#endif

#ifndef ENABLE_VGG16_MENU
#define ENABLE_VGG16_MENU 0
#endif

#ifndef ENABLE_VGG16_CPU_MENU
#define ENABLE_VGG16_CPU_MENU 0
#endif

#ifndef ENABLE_SQUEEZENET_MENU
#define ENABLE_SQUEEZENET_MENU 0
#endif

#ifndef ENABLE_SQUEEZENET1_1_IMAGENET_MENU
#define ENABLE_SQUEEZENET1_1_IMAGENET_MENU 1
#endif

#ifndef ENABLE_ALLCNNC160_MENU
#define ENABLE_ALLCNNC160_MENU 0
#endif

#ifndef ENABLE_ALLCNNC96_MENU
#define ENABLE_ALLCNNC96_MENU 0
#endif

#ifndef ENABLE_ALLCNNC96_QAT_MENU
#define ENABLE_ALLCNNC96_QAT_MENU 0
#endif

#ifndef ENABLE_ALLCNNC96_QAT_SYMPAD_MENU
#define ENABLE_ALLCNNC96_QAT_SYMPAD_MENU 1
#endif

#if ENABLE_ALLCNN_CPU_MENU
#include "allcnn_cifar10.h"
#endif

#if ENABLE_ALLCNN_ACCEL_MENU
#include "allcnn_cifar10_accel.h"
#endif

#if ENABLE_VGG16_MENU
#include "vgg16_accel.h"
#endif

#if ENABLE_VGG16_CPU_MENU
#include "vgg16_cpu.h"
#endif

#if ENABLE_SQUEEZENET_MENU
#include "squeezenet_accel.h"
#endif

#if ENABLE_SQUEEZENET1_1_IMAGENET_MENU
#include "squeezenet1_1_imagenet_accel.h"
#endif

#if ENABLE_ALLCNNC160_MENU
#include "allcnnc_160_accel.h"
#endif

#if ENABLE_ALLCNNC96_MENU
#include "allcnnc_96_accel.h"
#endif

#if ENABLE_ALLCNNC96_QAT_MENU
#include "allcnnc_96_qat_accel.h"
#endif

#if ENABLE_ALLCNNC96_QAT_SYMPAD_MENU
#include "allcnnc_96_qat_sympad_accel.h"
#endif

static Timer_Config_t g_timer_1ms;
static bool g_timer_1ms_started = false;
static bool g_uart_greeting_mode_active = false;
static volatile bool g_uart_greeting_enabled = false;
static volatile bool g_uart_greeting_pending = false;
static volatile uint32_t g_uart_greeting_elapsed_ms = 0U;
static volatile uint32_t g_uart_greeting_interval_ms = 2000U;

#define UART_COMMAND_BUFFER_SIZE 64U
#define TIMER_1MS_PRESCALER ((SYS_CLK_FREQ / 1000000U) - 1U)
#define TIMER_1MS_PERIOD_US 1000U

void HAL_Timer_TimeoutCallback(const Timer_Config_t *htim)
{
    if (htim == &g_timer_1ms) {
        if (g_uart_greeting_enabled) {
            g_uart_greeting_elapsed_ms++;
            if (g_uart_greeting_elapsed_ms >= g_uart_greeting_interval_ms) {
                g_uart_greeting_elapsed_ms = 0U;
                g_uart_greeting_pending = true;
            }
        }
    }
}

static char ascii_to_lower(char ch)
{
    if ((ch >= 'A') && (ch <= 'Z')) {
        return (char)(ch + ('a' - 'A'));
    }

    return ch;
}

static bool command_equals(const char *cmd, const char *expected)
{
    while ((*cmd != '\0') && (*expected != '\0')) {
        if (ascii_to_lower(*cmd) != ascii_to_lower(*expected)) {
            return false;
        }

        cmd++;
        expected++;
    }

    return (*cmd == '\0') && (*expected == '\0');
}

static bool is_config_ov5640_command(const char *cmd)
{
    return command_equals(cmd, "1.1");
}

static bool is_reset_ov5640_command(const char *cmd)
{
    return command_equals(cmd, "1.2");
}

static bool is_reset_video_ip_command(const char *cmd)
{
    return command_equals(cmd, "1.3");
}

static bool is_toggle_video_ip_command(const char *cmd)
{
    return command_equals(cmd, "1.4");
}

static bool is_ov5640_default_isp_command(const char *cmd)
{
    return command_equals(cmd, "1.5");
}

static bool is_ov5640_lenc_off_command(const char *cmd)
{
    return command_equals(cmd, "1.6");
}

static bool is_ov5640_awb_freeze_command(const char *cmd)
{
    return command_equals(cmd, "1.7");
}

static bool is_ov5640_manual_gain_command(const char *cmd)
{
    return command_equals(cmd, "1.8");
}

static bool is_ov5640_neutral_lenc_command(const char *cmd)
{
    return command_equals(cmd, "1.9");
}

static bool is_weight_transfer_command(const char *cmd)
{
    return command_equals(cmd, "2.1");
}

static bool is_weight_hyperram_load_command(const char *cmd)
{
    return command_equals(cmd, "2.2");
}

static bool is_weight_hyperram_load_sympad_command(const char *cmd)
{
    return command_equals(cmd, "2.3");
}

static bool is_uart_greeting_toggle_command(const char *cmd)
{
    return command_equals(cmd, "11.1");
}

static bool is_accel_conv1_prepare_command(const char *cmd)
{
    return command_equals(cmd, "4.1");
}

static bool is_accel_full_prepare_command(const char *cmd)
{
    return command_equals(cmd, "4.3");
}

static bool is_hyperram_test_command(const char *cmd)
{
    return command_equals(cmd, "3.1");
}

#if ENABLE_ALLCNN_CPU_MENU
static bool is_allcnn_cifar10_prepare_cpu_command(const char *cmd)
{
    return command_equals(cmd, "4.6");
}

static bool is_allcnn_cifar10_command(const char *cmd)
{
    return command_equals(cmd, "4.0");
}
#endif

static bool is_allcnn_cifar10_accel_conv1_command(const char *cmd)
{
    return command_equals(cmd, "4.2");
}

static bool is_allcnn_cifar10_accel_full_command(const char *cmd)
{
    return command_equals(cmd, "4.4");
}

static bool is_allcnn_cifar10_accel_accuracy_stream_command(const char *cmd)
{
    return command_equals(cmd, "4.5");
}

static bool is_allcnn_cifar10_accel_camera_ifmap_command(const char *cmd)
{
    return command_equals(cmd, "4.7");
}

#if ENABLE_VGG16_CPU_MENU
static bool is_vgg16_cpu_timing_command(const char *cmd)
{
    return command_equals(cmd, "5.0");
}
#endif

#if ENABLE_VGG16_MENU
static bool is_vgg16_accel_timing_command(const char *cmd)
{
    return command_equals(cmd, "5.1");
}

static bool is_vgg16_layer12_command(const char *cmd)
{
    return command_equals(cmd, "5.2");
}

static bool is_vgg16_layer11_command(const char *cmd)
{
    return command_equals(cmd, "5.3");
}

static bool is_vgg16_layer11_fake_ifmap_command(const char *cmd)
{
    return command_equals(cmd, "5.4");
}

static bool is_vgg16_layer11_low_addr_command(const char *cmd)
{
    return command_equals(cmd, "5.5");
}

static bool is_vgg16_layer10_then_layer11_low_addr_command(const char *cmd)
{
    return command_equals(cmd, "5.6");
}

static bool is_vgg16_layer10_then_two_low_addr_command(const char *cmd)
{
    return command_equals(cmd, "5.7");
}
#endif

#if ENABLE_SQUEEZENET_MENU
static bool is_squeezenet_accel_timing_command(const char *cmd)
{
    return command_equals(cmd, "6.1");
}
#endif

#if ENABLE_SQUEEZENET1_1_IMAGENET_MENU
static bool is_squeezenet1_1_imagenet_accel_timing_command(const char *cmd)
{
    return command_equals(cmd, "12.1");
}

static bool is_squeezenet1_1_imagenet_static_image_command(const char *cmd)
{
    return command_equals(cmd, "12.2");
}
#endif

#if ENABLE_ALLCNNC160_MENU
static bool is_allcnnc160_accel_timing_command(const char *cmd)
{
    return command_equals(cmd, "7.1");
}

static bool is_allcnnc160_camera_loop_command(const char *cmd)
{
    return command_equals(cmd, "7.2");
}
#endif

#if ENABLE_ALLCNNC96_MENU
static bool is_allcnnc96_accel_timing_command(const char *cmd)
{
    return command_equals(cmd, "8.1");
}

static bool is_allcnnc96_camera_loop_command(const char *cmd)
{
    return command_equals(cmd, "8.2");
}
#endif

#if ENABLE_ALLCNNC96_QAT_MENU
static bool is_allcnnc96_qat_accel_timing_command(const char *cmd)
{
    return command_equals(cmd, "9.1");
}

static bool is_allcnnc96_qat_camera_loop_command(const char *cmd)
{
    return command_equals(cmd, "9.2");
}
#endif

#if ENABLE_ALLCNNC96_QAT_SYMPAD_MENU
static bool is_allcnnc96_qat_sympad_accel_timing_command(const char *cmd)
{
    return command_equals(cmd, "10.1");
}

static bool is_allcnnc96_qat_sympad_camera_loop_command(const char *cmd)
{
    return command_equals(cmd, "10.2");
}
#endif

static void print_uart_menu(void)
{
    Uart_println("");
    Uart_println("UART menu:");
    Uart_println("");
    Uart_println("[1] Camera / Video");
    Uart_println("  1.1  Config OV5640 camera");
    Uart_println("  1.2  Reset OV5640 by I2C");
    Uart_println("  1.3  Reset video IP");
    Uart_println("  1.4  Enb/Dis video IP");
    Uart_println("  1.5  OV5640 default ISP");
    Uart_println("  1.6  OV5640 LENC off");
    Uart_println("  1.7  OV5640 freeze AWB");
    Uart_println("  1.8  OV5640 manual R/B gain");
    Uart_println("  1.9  OV5640 neutral LENC");
    Uart_println("");
    Uart_println("[2] Weights");
    Uart_println("  2.1  Update weights");
    Uart_println("  2.2  Load ALLCNN weights from Flash to HyperRAM0");
#if ENABLE_ALLCNNC96_QAT_SYMPAD_MENU
    Uart_println("  2.3  Load 96 QAT SymPad weights from Flash to HyperRAM0");
#endif
    Uart_println("");
    Uart_println("[3] HyperRAM");
    Uart_println("  3.1  Test HyperRAM ports");
#if ENABLE_ALLCNN_ACCEL_MENU || ENABLE_ALLCNN_CPU_MENU
    Uart_println("");
    Uart_println("[4] ALL_CNN_C");
#if ENABLE_ALLCNN_CPU_MENU
    Uart_println("  4.6  Prepare CPU full payload");
    Uart_println("  4.0  Run CPU full static image");
#endif
#if ENABLE_ALLCNN_ACCEL_MENU
    Uart_println("  4.3  Prepare accel full payload");
    Uart_println("  4.4  Run accel full static image");
#endif
#endif
#if ENABLE_VGG16_MENU || ENABLE_VGG16_CPU_MENU
    Uart_println("");
    Uart_println("[5] VGG16");
#if ENABLE_VGG16_CPU_MENU
    Uart_println("  5.0  Run VGG16 CPU-only timing");
#endif
#if ENABLE_VGG16_MENU
    Uart_println("  5.1  Run VGG16 CPU + accel timing");
    Uart_println("  5.2  Run VGG16 layer 12 only");
    Uart_println("  5.3  Run VGG16 layer 11 only");
    Uart_println("  5.4  Run VGG16 layer 11 with fake IFMAP");
    Uart_println("  5.5  Run VGG16 layer 11 shape at low addresses");
    Uart_println("  5.6  Run VGG16 layer 10, then layer 11 low-address");
    Uart_println("  5.7  Run VGG16 layer 10, then two low-address 14x14 layers");
#endif
#endif
#if ENABLE_SQUEEZENET_MENU
    Uart_println("");
    Uart_println("[6] SqueezeNet");
    Uart_println("  6.1  Run SqueezeNet-96 accel timing");
#endif
#if ENABLE_ALLCNNC160_MENU
    Uart_println("");
    Uart_println("[7] ALL-CNN-C-160");
    Uart_println("  7.1  Run ALL-CNN-C-160 accel timing");
    Uart_println("  7.2  Run ALL-CNN-C-160 camera result loop");
#endif
#if ENABLE_ALLCNNC96_MENU
    Uart_println("");
    Uart_println("[8] ALL-CNN-C-96 INT8");
    Uart_println("  8.1  Run ALL-CNN-C-96 accel timing");
    Uart_println("  8.2  Run ALL-CNN-C-96 camera result loop");
#endif
#if ENABLE_ALLCNNC96_QAT_MENU
    Uart_println("");
    Uart_println("[9] ALL-CNN-C-96 QAT INT8");
    Uart_println("  9.1  Run ALL-CNN-C-96 QAT accel timing");
    Uart_println("  9.2  Run ALL-CNN-C-96 QAT camera result loop");
#endif
#if ENABLE_ALLCNNC96_QAT_SYMPAD_MENU
    Uart_println("");
    Uart_println("[10] ALL-CNN-C-96 QAT SymPad INT8");
    Uart_println("  10.1 Run ALL-CNN-C-96 QAT SymPad accel timing");
    Uart_println("  10.2 Run ALL-CNN-C-96 QAT SymPad camera result loop");
#endif
    Uart_println("");
    Uart_println("[11] Timer UART");
    Uart_println("  11.1 UART greeting timer");
#if ENABLE_SQUEEZENET1_1_IMAGENET_MENU
    Uart_println("");
    Uart_println("[12] SqueezeNet1.1 ImageNet");
    Uart_println("  12.1 Run SqueezeNet1.1 ImageNet accel/CPU-fallback timing");
    Uart_println("  12.2 Run SqueezeNet1.1 static dog image from flash");
#endif
    Uart_println("");
#if !(ENABLE_ALLCNN_ACCEL_MENU || ENABLE_ALLCNN_CPU_MENU)
#if ENABLE_VGG16_MENU || ENABLE_VGG16_CPU_MENU
    Uart_println("VGG16 flow:");
#if ENABLE_VGG16_CPU_MENU
    Uart_println("  5.0 runs VGG16 CPU-only timing/profile.");
#endif
#if ENABLE_VGG16_MENU
    Uart_println("  5.1 runs VGG16 conv layers on accel and max-pool layers on CPU.");
    Uart_println("  5.2 runs Conv5_2 only for debug.");
    Uart_println("  5.3 runs Conv5_1 only for debug.");
    Uart_println("  5.4 fills Conv5_1 IFMAP in HR1, then runs Conv5_1.");
    Uart_println("  5.5 runs Conv5_1 shape using low HRAM addresses.");
    Uart_println("  5.6 checks whether Conv5_1 needs a previous accel layer.");
    Uart_println("  5.7 checks whether consecutive Conv5-shaped layers hang.");
#endif
#endif
#endif
    Uart_print("> ");
}

static void ensure_timer_1ms_started(void)
{
    if (!g_timer_1ms_started) {
        HAL_Timer_SetConfig(&g_timer_1ms,
                            SYS_CLK_FREQ,
                            TIMER_1MS_PRESCALER,
                            TIMER_1MS_PERIOD_US,
                            true);
        HAL_Timer_Init(&g_timer_1ms);
        HAL_Timer_Start();
        g_timer_1ms_started = true;
    }
}

static void print_uart_greeting_prompt(void)
{
    Uart_print("timer> ");
}

static void print_uart_greeting_mode_menu(void)
{
    Uart_println("");
    Uart_println("UART timer: 500/1/2, q quit");
    print_uart_greeting_prompt();
}

static void set_uart_greeting_interval(uint32_t interval_ms)
{
    g_uart_greeting_interval_ms = interval_ms;
    g_uart_greeting_elapsed_ms = 0U;
    g_uart_greeting_pending = false;
    g_uart_greeting_enabled = true;
    Uart_println("OK");
}

static void start_uart_greeting_mode(void)
{
    ensure_timer_1ms_started();
    g_uart_greeting_elapsed_ms = 0U;
    g_uart_greeting_pending = false;
    g_uart_greeting_enabled = true;
    g_uart_greeting_mode_active = true;
    print_uart_greeting_mode_menu();
}

static void stop_uart_greeting_mode(void)
{
    g_uart_greeting_enabled = false;
    g_uart_greeting_elapsed_ms = 0U;
    g_uart_greeting_pending = false;
    g_uart_greeting_mode_active = false;
    Uart_println("Timer stopped.");
}

static void handle_uart_greeting_mode_command(const char *cmd)
{
    if (command_equals(cmd, "500")) {
        set_uart_greeting_interval(500U);
        print_uart_greeting_prompt();
    } else if (command_equals(cmd, "1")) {
        set_uart_greeting_interval(1000U);
        print_uart_greeting_prompt();
    } else if (command_equals(cmd, "2")) {
        set_uart_greeting_interval(2000U);
        print_uart_greeting_prompt();
    } else if (command_equals(cmd, "q")) {
        stop_uart_greeting_mode();
        print_uart_menu();
    } else {
        Uart_println("Use 500, 1, 2, q");
        print_uart_greeting_mode_menu();
    }
}

static void service_uart_greeting_timer(void)
{
    if (g_uart_greeting_pending) {
        g_uart_greeting_pending = false;
        Uart_println("Xin chào thầy và các bạn");
        if (g_uart_greeting_mode_active) {
            print_uart_greeting_prompt();
        } else {
            Uart_print("> ");
        }
    }
}

static bool handle_uart_command(const char *cmd)
{
    if (is_config_ov5640_command(cmd)) {
        OV5640_Config(&i2c0);
    } else if (is_reset_ov5640_command(cmd)) {
        OV5640_ResetByI2C(&i2c0);
    } else if (is_reset_video_ip_command(cmd)) {
        OV5640_ResetVideoIP();
    } else if (is_toggle_video_ip_command(cmd)) {
        OV5640_ToggleVideoIP();
    } else if (is_ov5640_default_isp_command(cmd)) {
        OV5640_ApplyDefaultIsp(&i2c0);
    } else if (is_ov5640_lenc_off_command(cmd)) {
        OV5640_DisableLensCorrection(&i2c0);
    } else if (is_ov5640_awb_freeze_command(cmd)) {
        OV5640_FreezeAwb(&i2c0);
    } else if (is_ov5640_manual_gain_command(cmd)) {
        OV5640_ApplyManualColorGain(&i2c0);
    } else if (is_ov5640_neutral_lenc_command(cmd)) {
        OV5640_ApplyNeutralLensCorrection(&i2c0);
    } else if (is_weight_transfer_command(cmd)) {
        WeightReceiver_RunFlashLoader();
        return false;
    } else if (is_weight_hyperram_load_command(cmd)) {
        WeightHyperRAM_RunFlashToHyperRAMLoader();
#if ENABLE_ALLCNNC96_QAT_SYMPAD_MENU
    } else if (is_weight_hyperram_load_sympad_command(cmd)) {
        WeightHyperRAM_RunFlashToHyperRAMLoaderMetadata(WEIGHTS_ALLCNNC96_QAT_SYMPAD_METADATA_OFFSET_ADDR);
#endif
    } else if (is_uart_greeting_toggle_command(cmd)) {
        start_uart_greeting_mode();
        return false;
#if ENABLE_ALLCNN_ACCEL_MENU
    } else if (is_accel_conv1_prepare_command(cmd)) {
        AllCNN_CIFAR10_Accel_PrepareConv1Payload();
    } else if (is_accel_full_prepare_command(cmd)) {
        AllCNN_CIFAR10_Accel_PrepareFullPayload();
#endif
    } else if (is_hyperram_test_command(cmd)) {
        HyperRAM_Test_RunAll();
#if ENABLE_ALLCNN_CPU_MENU
    } else if (is_allcnn_cifar10_prepare_cpu_command(cmd)) {
        AllCNN_CIFAR10_PrepareHyperRAM0Payload();
    } else if (is_allcnn_cifar10_command(cmd)) {
        AllCNN_CIFAR10_RunFromHyperRAM0();
#endif
#if ENABLE_ALLCNN_ACCEL_MENU
    } else if (is_allcnn_cifar10_accel_conv1_command(cmd)) {
        AllCNN_CIFAR10_Accel_RunConv1Bringup();
    } else if (is_allcnn_cifar10_accel_full_command(cmd)) {
        AllCNN_CIFAR10_Accel_RunFullModel();
    } else if (is_allcnn_cifar10_accel_accuracy_stream_command(cmd)) {
        AllCNN_CIFAR10_Accel_RunUartAccuracyStream();
        return false;
    } else if (is_allcnn_cifar10_accel_camera_ifmap_command(cmd)) {
        AllCNN_CIFAR10_Accel_RunFullModelCameraIfmap();
#endif
    }
#if ENABLE_VGG16_CPU_MENU
    else if (is_vgg16_cpu_timing_command(cmd)) {
        VGG16_CPU_RunTimingOnly();
    }
#endif
#if ENABLE_VGG16_MENU
    else if (is_vgg16_accel_timing_command(cmd)) {
        VGG16_Accel_RunTimingOnly();
    } else if (is_vgg16_layer12_command(cmd)) {
        VGG16_Accel_RunLayer12Only();
    } else if (is_vgg16_layer11_command(cmd)) {
        VGG16_Accel_RunLayer11Only();
    } else if (is_vgg16_layer11_fake_ifmap_command(cmd)) {
        VGG16_Accel_RunLayer11WithFakeInput();
    } else if (is_vgg16_layer11_low_addr_command(cmd)) {
        VGG16_Accel_RunLayer11LowAddress();
    } else if (is_vgg16_layer10_then_layer11_low_addr_command(cmd)) {
        VGG16_Accel_RunLayer10ThenLayer11LowAddress();
    } else if (is_vgg16_layer10_then_two_low_addr_command(cmd)) {
        VGG16_Accel_RunLayer10ThenTwoLowAddress();
    }
#endif
#if ENABLE_SQUEEZENET_MENU
    else if (is_squeezenet_accel_timing_command(cmd)) {
        SqueezeNet_Accel_RunTimingOnly();
    }
#endif
#if ENABLE_SQUEEZENET1_1_IMAGENET_MENU
    else if (is_squeezenet1_1_imagenet_accel_timing_command(cmd)) {
        Squeezenet11Imagenet_Accel_RunTimingOnly();
    } else if (is_squeezenet1_1_imagenet_static_image_command(cmd)) {
        Squeezenet11Imagenet_Accel_RunStaticImageFromFlash();
    }
#endif
#if ENABLE_ALLCNNC160_MENU
    else if (is_allcnnc160_accel_timing_command(cmd)) {
        AllCNNC160_Accel_RunTimingOnly();
    } else if (is_allcnnc160_camera_loop_command(cmd)) {
        AllCNNC160_Accel_RunCameraResultLoop();
    }
#endif
#if ENABLE_ALLCNNC96_MENU
    else if (is_allcnnc96_accel_timing_command(cmd)) {
        AllCNNC96_Accel_RunTimingOnly();
    } else if (is_allcnnc96_camera_loop_command(cmd)) {
        AllCNNC96_Accel_RunCameraResultLoop();
    }
#endif
#if ENABLE_ALLCNNC96_QAT_MENU
    else if (is_allcnnc96_qat_accel_timing_command(cmd)) {
        AllCNNC96QAT_Accel_RunTimingOnly();
    } else if (is_allcnnc96_qat_camera_loop_command(cmd)) {
        AllCNNC96QAT_Accel_RunCameraResultLoop();
    }
#endif
#if ENABLE_ALLCNNC96_QAT_SYMPAD_MENU
    else if (is_allcnnc96_qat_sympad_accel_timing_command(cmd)) {
        AllCNNC96QATSymPad_Accel_RunTimingOnly();
    } else if (is_allcnnc96_qat_sympad_camera_loop_command(cmd)) {
        AllCNNC96QATSymPad_Accel_RunCameraResultLoop();
    }
#endif
    else {
        Uart_print("Unknown command: ");
        Uart_println(cmd);
    }

    return true;
}

static void process_uart_byte(uint8_t rx_data, char *cmd_buffer, uint32_t *cmd_len)
{
    if (g_uart_greeting_mode_active && (*cmd_len == 0U) &&
        (ascii_to_lower((char)rx_data) == 'q')) {
        Uart_write(rx_data);
        Uart_println("");
        stop_uart_greeting_mode();
        print_uart_menu();
        return;
    }

    if ((rx_data == '\r') || (rx_data == '\n')) {
        if (*cmd_len > 0U) {
            cmd_buffer[*cmd_len] = '\0';
            Uart_println("");
            if (g_uart_greeting_mode_active) {
                handle_uart_greeting_mode_command(cmd_buffer);
            } else if (handle_uart_command(cmd_buffer)) {
                print_uart_menu();
            }
            *cmd_len = 0U;
        }
        return;
    }

    if ((rx_data == '\b') || (rx_data == 0x7FU)) {
        if (*cmd_len > 0U) {
            (*cmd_len)--;
            Uart_print("\b \b");
        }
        return;
    }

    if ((rx_data < ' ') || (rx_data > '~')) {
        return;
    }

    if (*cmd_len >= (UART_COMMAND_BUFFER_SIZE - 1U)) {
        *cmd_len = 0U;
        cmd_buffer[0] = '\0';
        Uart_println("");
        Uart_println("Command too long. Try again.");
        print_uart_menu();
        return;
    }

    cmd_buffer[*cmd_len] = (char)rx_data;
    (*cmd_len)++;
    Uart_write(rx_data);
}

int main()
{

    char uart_cmd[UART_COMMAND_BUFFER_SIZE];
    uint32_t uart_cmd_len = 0U;
    uint8_t rx_data;

    System_Init_All();
    Uart_println("Send command.");
    print_uart_menu();

    while (1) {
        service_uart_greeting_timer();
        if (Uart_read(&rx_data)) {
            process_uart_byte(rx_data, uart_cmd, &uart_cmd_len);
        }
    }

    return 0;
}
