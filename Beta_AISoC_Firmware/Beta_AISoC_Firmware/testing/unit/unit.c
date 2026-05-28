#include "unit.h"

int main(void)
{
	Uart_begin(115200);

	/* TEST UART*/
#ifdef TEST_UART
	Uart_println("--- STARTING UART TEST ---");
	Uart_println("Please enter a string (Press Enter to finish).");
	Uart_println("Note: Empty input will result in a FAILED test.");
	Uart_write(0x3f); // triggle moniror

	char rx_buf[128];
	int rx_index = 0;
	uint8_t recv_data;
	bool uart_done = false;

	while (!uart_done)
	{
		if (Uart_read(&recv_data))
		{
			Uart_write((uint32_t)recv_data);

			if (recv_data == '\n' || recv_data == '\r')
			{
				rx_buf[rx_index] = '\0';
				Uart_println("");

				if (rx_index > 0)
				{
					Uart_print("The string you entered is: ");
					Uart_println(rx_buf);
					Uart_println("UART Test: PASS!");
				}
				else
				{
					Uart_println("No data received!");
					Uart_println("UART Test: FAILED!");
				}

				uart_done = true;
			}
			else if (rx_index < 127)
			{
				rx_buf[rx_index++] = (char)recv_data;
			}
		}
	}
#endif
	/* END OF TEST UART*/

	/* TEST I2C */
#ifdef TEST_I2C
	Uart_println("--- STARTING I2C TEST (32 BYTES) ---");
	uint32_t i2c_freq = 100000;
	uint8_t slave_addr_7bit = 0x50;
	I2CDriver_t i2c;

	I2C_driver_init(&i2c, I2C_BASE_ADDR);
	I2C_init(&i2c, SYS_CLK_FREQ, i2c_freq);

	bool i2c_pass = true;

	uint8_t write_payload[33] = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
								 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
								 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
								 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20};

	uint8_t read_data[32] = {0};

	Uart_println("Writing 32 bytes to I2C Slave...");
	if (!I2C_write_transaction(&i2c, slave_addr_7bit, write_payload, 33, true))
	{
		Uart_println("Error: Cannot write to I2C (No ACK)!");
		i2c_pass = false;
	}
	else
	{
		Uart_println("I2C write successful! Reading back 32 bytes...");

		uint8_t reg_addr = 0x00;
		if (!I2C_write_transaction(&i2c, slave_addr_7bit, &reg_addr, 1, true))
		{
			Uart_println("Error: Cannot send register address!");
			i2c_pass = false;
		}
		else
		{
			if (!I2C_read_transaction(&i2c, slave_addr_7bit, read_data, 32, true))
			{
				Uart_println("Error: Cannot read data from I2C Slave!");
				i2c_pass = false;
			}
			else
			{
				bool data_match = true;
				for (int i = 0; i < 32; i++)
				{
					if (read_data[i] != write_payload[i + 1])
					{
						data_match = false;
						break;
					}
				}

				if (data_match)
				{
					Uart_println("All 32 bytes match exactly!");
				}
				else
				{
					Uart_println("Read data does NOT match!");
					i2c_pass = false;
				}
			}
		}
	}
	if (i2c_pass)
	{
		Uart_println("I2C Test: PASS!");
	}
	else
	{
		Uart_println("I2C Test: FAILED!");
	}
#endif
	/* END OF TEST I2C*/

	/* TEST OSPI */
#ifdef TEST_OSPI
	Uart_println("--- STARTING OSPI TEST ---");
	uint8_t read_buffer[32];
	const uint8_t write_data0[32] = {0xAA, 0x55, 0xAA, 0x55, 0xCC, 0x33, 0xCC, 0x33,
									 0xDD, 0x44, 0xDD, 0x44, 0xEE, 0x55, 0xEE, 0x55,
									 0xFF, 0x66, 0xFF, 0x66, 0x11, 0x77, 0x11, 0x77,
									 0x22, 0x88, 0x22, 0x88, 0x33, 0x99, 0x33, 0x99};
	int i;
	bool test_pass = true;

	OSPI_init(&ospi, OSPI_BASE_ADDR);
	OSPI_set_config(&ospi, 2, 0, 0, 16);

	while (!OSPI_is_start_ready(&ospi))
		;
	uint32_t target_addr_lower = 0x00000000;
	uint16_t write_cmd_upper = 0x0000;
	OSPI_set_cmd_addr(&ospi, target_addr_lower, write_cmd_upper);
	OSPI_burst_write(&ospi, write_data0, 32);
	OSPI_start(&ospi);

	while (!OSPI_is_start_ready(&ospi))
		;
	uint16_t read_cmd_upper = 0x8000;
	OSPI_set_cmd_addr(&ospi, target_addr_lower, read_cmd_upper);
	OSPI_start(&ospi);
	OSPI_burst_read(&ospi, read_buffer, 32);

	for (i = 0; i < 32; i++)
	{
		if (read_buffer[i] != write_data0[i])
		{
			test_pass = false;
			break;
		}
	}

	if (test_pass)
	{
		Uart_println("OSPI Test: PASS!");
	}
	else
	{
		Uart_println("OSPI Test: FAILED!");
	}

	/* END OF TEST OSPI */
#endif

	/* TEST GPIO */
#ifdef TEST_GPIO
	Uart_println("--- STARTING 8-PIN GPIO TEST ---");
	gpio_init();

	pinMode(D0, OUTPUT);
	pinMode(D1, OUTPUT);
	pinMode(D2, OUTPUT);
	pinMode(D3, OUTPUT);

	pinMode(D4, INPUT);
	pinMode(D5, INPUT);
	pinMode(D6, INPUT);
	pinMode(D7, INPUT);

	DigitalWrite(D0, HIGH);
	DigitalWrite(D1, LOW);
	DigitalWrite(D2, HIGH);
	DigitalWrite(D3, LOW);
	Uart_println("Wrote HIGH to D0, D2 and LOW to D1, D3.");

	Uart_println("Reading states of input pins D4-D7:");

	if (DigitalRead(D4) == HIGH)
	{
		Uart_println("Pin D4 state: HIGH");
	}
	else
	{
		Uart_println("Pin D4 state: LOW");
	}

	if (DigitalRead(D5) == HIGH)
	{
		Uart_println("Pin D5 state: HIGH");
	}
	else
	{
		Uart_println("Pin D5 state: LOW");
	}

	if (DigitalRead(D6) == HIGH)
	{
		Uart_println("Pin D6 state: HIGH");
	}
	else
	{
		Uart_println("Pin D6 state: LOW");
	}

	if (DigitalRead(D7) == HIGH)
	{
		Uart_println("Pin D7 state: HIGH");
	}
	else
	{
		Uart_println("Pin D7 state: LOW");
	}

	Uart_println("--- END OF 8-PIN GPIO TEST ---");
#endif
	/* END OF TEST GPIO */

	/* TEST TIMER */
#ifdef TEST_TIMER
	Uart_begin(115200);
	Uart_println("--- STARTING TIMER TEST ---");

	timer_init();

	Uart_println("Testing 5ms delay...");
	uint32_t start_time = millis();
	delay(5);
	uint32_t end_time = millis();
	if ((end_time - start_time) >= 5)
	{
		Uart_println("Timer Test: PASS!");
	}
	else
	{
		Uart_println("Timer Test: FAILED!");
	}

	Uart_println("Testing 10ms delay...");
	start_time = millis();
	delay(10);
	end_time = millis();
	if ((end_time - start_time) >= 10)
	{
		DigitalToggle(D0);
		Uart_println("Timer Test: PASS!");
	}
	else
	{
		Uart_println("Timer Test: FAILED!");
	}

	Uart_println("Testing 20ms delay...");
	start_time = millis();
	delay(20);
	end_time = millis();
	if ((end_time - start_time) >= 20)
	{
		Uart_println("Timer Test: PASS!");
	}
	else
	{
		Uart_println("Timer Test: FAILED!");
	}

	Uart_println("--- END OF TIMER TEST ---");
#endif
	/* END OF TEST TIMER */

	return 0;
}
