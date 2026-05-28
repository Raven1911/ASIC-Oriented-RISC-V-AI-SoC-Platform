#include "../Inc/mem.h"
#ifdef HAL_MEM_MODULE_ENABLED
uint32_t mem_read_word(uint32_t segment_base_word_offset, uint32_t word_offset_in_segment)
{
    uint32_t absolute_word_offset = segment_base_word_offset + word_offset_in_segment;

    // Create a volatile pointer to the target memory address
    // Pointer arithmetic on (volatile uint32_t*) automatically handles scaling by sizeof(uint32_t)
    volatile uint32_t *address_to_read = ((volatile uint32_t *)APPLICATION_START_ADDRESS) + absolute_word_offset;

    return *address_to_read;
}

void mem_write_word(uint32_t segment_base_word_offset, uint32_t word_offset_in_segment, uint32_t data)
{
    uint32_t absolute_word_offset = segment_base_word_offset + word_offset_in_segment;
    *(((volatile uint32_t *)APPLICATION_START_ADDRESS) + absolute_word_offset) = data;
}

uint32_t mem_read_bits(uint32_t segment_base_word_offset, uint32_t word_offset_in_segment, uint8_t start_bit, uint8_t num_bits)
{
    // Validate parameters
    if (num_bits == 0 || num_bits > 32 || start_bit >= 32 || (start_bit + num_bits) > 32)
    {
        return 0; // Return 0 for invalid parameters
    }

    uint32_t full_word = mem_read_word(segment_base_word_offset, word_offset_in_segment);

    // Create a mask for the desired number of bits
    // (1UL << num_bits) ensures the shift operates on an unsigned long if num_bits is large,
    // preventing overflow issues with '1' being treated as a signed int.
    uint32_t mask = (num_bits == 32) ? 0xFFFFFFFFUL : ((1UL << num_bits) - 1);

    // Shift the word to align the desired bits to LSB, then apply the mask
    return (full_word >> start_bit) & mask;
}

void mem_write_bits(uint32_t segment_base_word_offset, uint32_t word_offset_in_segment, uint32_t data_to_write, uint8_t start_bit, uint8_t num_bits)
{
    // Validate parameters
    if (num_bits == 0 || num_bits > 32 || start_bit >= 32 || (start_bit + num_bits) > 32)
    {
        return;
    }

    uint32_t absolute_word_offset = segment_base_word_offset + word_offset_in_segment;
    volatile uint32_t *reg_ptr = ((volatile uint32_t *)APPLICATION_START_ADDRESS) + absolute_word_offset;

    // Read the current value from the register (Read-Modify-Write operation)
    uint32_t current_value = *reg_ptr;

    // Create a mask for the field to be written
    uint32_t field_mask = (num_bits == 32) ? 0xFFFFFFFFUL : ((1UL << num_bits) - 1);

    // Create a mask to clear the bits that will be written
    // This mask has 0s at the bit positions to be written and 1s elsewhere
    uint32_t clear_mask = ~(field_mask << start_bit);

    // Clear the target bits in the current value
    uint32_t value_with_bits_cleared = current_value & clear_mask;

    // Prepare the new data: mask it to ensure it fits and shift it to the correct position
    uint32_t shifted_new_data = (data_to_write & field_mask) << start_bit;

    // Combine the cleared value with the new data
    uint32_t final_value_to_write = value_with_bits_cleared | shifted_new_data;

    // Write the modified value back to the register
    *reg_ptr = final_value_to_write;
}

#endif // HAL_MEM_MODULE_ENABLED