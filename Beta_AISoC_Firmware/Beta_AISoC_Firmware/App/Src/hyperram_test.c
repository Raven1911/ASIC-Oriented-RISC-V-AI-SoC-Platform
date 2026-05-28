#include "hyperram_test.h"

#define HYPERRAM_MAX_TEST_SIZE 510U
#define HYPERRAM_NUM_TEST_CASES 10U

typedef struct {
    uint32_t addr;
    uint16_t size;
    bool is_linear;
} HyperRAMTestCase_t;

static uint8_t read_buffer[HYPERRAM_MAX_TEST_SIZE];
static uint8_t write_data[HYPERRAM_MAX_TEST_SIZE];

static const HyperRAMTestCase_t test_cases[HYPERRAM_NUM_TEST_CASES] = {
    {0x00000000U, 32U,  true},
    {0x00000400U, 32U,  false},
    {0x00001000U, 128U, true},
    {0x00008000U, 510U, true},
    {0x00010008U, 16U,  false},
    {0x00055554U, 64U,  true},
    {0x00100000U, 256U, true},
    {0x00400000U, 510U, true},
    {0x007FF000U, 32U,  true},
    {0x007FFF00U, 32U,  false}
};

static bool case_results[HYPERRAM_NUM_TEST_CASES];

static void print_u32_hex8(uint32_t value)
{
    static const char hex_map[] = "0123456789ABCDEF";
    char text[11];

    text[0] = '0';
    text[1] = 'x';
    for (uint32_t i = 0U; i < 8U; i++) {
        uint8_t nibble = (uint8_t)((value >> (28U - (i * 4U))) & 0x0FU);
        text[2U + i] = hex_map[nibble];
    }
    text[10] = '\0';

    Uart_print(text);
}

static void print_u32_dec(uint32_t value)
{
    char text[11];
    uint32_t pos = 0U;

    if (value == 0U) {
        Uart_write('0');
        return;
    }

    while ((value > 0U) && (pos < sizeof(text))) {
        text[pos++] = (char)('0' + (value % 10U));
        value /= 10U;
    }

    while (pos > 0U) {
        Uart_write((uint8_t)text[--pos]);
    }
}

static void print_u8_hex(uint8_t value)
{
    static const char hex_map[] = "0123456789ABCDEF";
    char text[3];

    text[0] = hex_map[(value >> 4) & 0x0F];
    text[1] = hex_map[value & 0x0F];
    text[2] = '\0';

    Uart_print(text);
}

void HyperRAM_Test_RunW95(W95_HandleTypeDef *hw95, const char *port_name)
{
    bool all_tests_pass = true;

    Uart_println("\n=======================================================");
    Uart_print("    STARTING W95 HYPERRAM TESTS ON: ");
    Uart_println(port_name);
    Uart_println("=======================================================");

    for (uint32_t c = 0U; c < HYPERRAM_NUM_TEST_CASES; c++) {
        const HyperRAMTestCase_t *tc = &test_cases[c];
        bool case_pass = true;
        int32_t error_idx = -1;

        Uart_println("");
        Uart_print(">>> Running Test Case ");
        print_u32_dec(c + 1U);
        Uart_println("...");

        Uart_print("    Address : ");
        print_u32_hex8(tc->addr);
        Uart_println("");
        Uart_print("    Type    : ");
        Uart_println(tc->is_linear ? "Linear" : "Wrapped");
        Uart_print("    Size    : ");
        print_u32_dec(tc->size);
        Uart_println(" bytes");

        for (uint32_t i = 0U; i < tc->size; i++) {
            write_data[i] = (uint8_t)((i + c + (tc->addr >> 8)) & 0xFFU);
            read_buffer[i] = 0x00U;
        }

        W95_MemoryWrite(hw95, tc->addr, write_data, tc->size, tc->is_linear);
        W95_MemoryRead(hw95, tc->addr, read_buffer, tc->size, tc->is_linear);

        for (uint32_t i = 0U; i < tc->size; i++) {
            if (read_buffer[i] != write_data[i]) {
                case_pass = false;
                all_tests_pass = false;
                error_idx = (int32_t)i;
                break;
            }
        }

        if (case_pass) {
            Uart_print("    Write[0]: 0x");
            print_u8_hex(write_data[0]);
            Uart_println("");
            Uart_print("    Read[0] : 0x");
            print_u8_hex(read_buffer[0]);
            Uart_println("");
            Uart_println("    STATUS  : PASS!");
        } else {
            Uart_print("    [!] FAILED at Index: ");
            print_u32_dec((uint32_t)error_idx);
            Uart_println("");

            Uart_print("        Expected: 0x");
            print_u8_hex(write_data[error_idx]);
            Uart_println("");

            Uart_print("        Read    : 0x");
            print_u8_hex(read_buffer[error_idx]);
            Uart_println("");
        }

        case_results[c] = case_pass;
    }

    Uart_println("\n-------------------------------------------------------");
    if (all_tests_pass) {
        Uart_print("FINAL RESULT FOR ");
        Uart_print(port_name);
        Uart_println(": ALL 10 CASES PASSED!");
    } else {
        Uart_print("FINAL RESULT FOR ");
        Uart_print(port_name);
        Uart_println(": FAILED ON CASES:");
        for (uint32_t c = 0U; c < HYPERRAM_NUM_TEST_CASES; c++) {
            if (!case_results[c]) {
                Uart_print("  - Case ");
                print_u32_dec(c + 1U);
                Uart_println("");
            }
        }
    }
    Uart_println("-------------------------------------------------------\n");
}

void HyperRAM_Test_RunByteDump(W95_HandleTypeDef *hw95, const char *port_name, uint32_t start_addr)
{
    const uint16_t test_size = 32U;
    bool test_pass = true;

    Uart_println("\n=======================================================");
    Uart_print("    STARTING 32-BYTE DUMP TEST ON: ");
    Uart_println(port_name);
    Uart_println("=======================================================");

    for (uint32_t i = 0U; i < test_size; i++) {
        write_data[i] = (uint8_t)(i & 0xFFU);
        read_buffer[i] = 0x00U;
    }

    W95_MemoryWrite(hw95, start_addr, write_data, test_size, true);
    W95_MemoryRead(hw95, start_addr, read_buffer, test_size, true);

    Uart_println("    --- BYTE-BY-BYTE DUMP ---");
    for (uint32_t i = 0U; i < test_size; i++) {
        bool match = (read_buffer[i] == write_data[i]);

        if (!match) {
            test_pass = false;
        }

        Uart_print("    Idx: ");
        if (i < 10U) {
            Uart_print(" ");
        }
        print_u32_dec(i);

        Uart_print(" | Write: 0x");
        print_u8_hex(write_data[i]);

        Uart_print(" | Read: 0x");
        print_u8_hex(read_buffer[i]);

        if (!match) {
            Uart_println("  <-- ERROR");
        } else {
            Uart_println("");
        }
    }

    Uart_println("-------------------------------------------------------");
    if (test_pass) {
        Uart_println("    STATUS: ALL 32 BYTES MATCH! (PASS)");
    } else {
        Uart_println("    STATUS: MISMATCH DETECTED! (FAILED)");
    }
    Uart_println("=======================================================\n");
}

void HyperRAM_Test_RunAll(void)
{
    HyperRAM_Driver_t hram_port0;
    HyperRAM_Driver_t hram_port1;
    W95_HandleTypeDef w95_chip0;
    W95_HandleTypeDef w95_chip1;

    Uart_begin(UART_BAUD_RATE);

    HyperRAM_init(&hram_port0, HYPERRAM_0_BASE_ADDR);
    HyperRAM_init(&hram_port1, HYPERRAM_1_BASE_ADDR);

    W95_Init(&w95_chip0, &hram_port0, 7U, 0U, 2U);
    W95_Init(&w95_chip1, &hram_port1, 7U, 0U, 1U);

    HyperRAM_Test_RunW95(&w95_chip0, "PORT 0 (Base: 0x02005000)");
    HyperRAM_Test_RunByteDump(&w95_chip0, "PORT 0 (Base 0x02005000)", 0x00000000U);

    HyperRAM_Test_RunW95(&w95_chip1, "PORT 1 (Base: 0x02005100)");
    HyperRAM_Test_RunByteDump(&w95_chip1, "PORT 1 (Base 0x02005100)", 0x00000000U);
}
