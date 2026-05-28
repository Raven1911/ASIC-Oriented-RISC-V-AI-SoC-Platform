#ifndef MEM_H
#define MEM_H

#include <soc_hal.h>

#define APPLICATION_START_ADDRESS 0x01100000U
// Memory function declarations


/**
 * @brief Reads a 32-bit word from a specified memory location.
 * @param segment_base_word_offset The base word offset of the memory segment.
 * @param word_offset_in_segment The word offset within that segment.
 * @return The 32-bit data read from memory.
 */
uint32_t mem_read_word(uint32_t segment_base_word_offset, uint32_t word_offset_in_segment);

/**
 * @brief Reads a specified number of bits from a 32-bit word in memory.
 * @param segment_base_word_offset The base word offset of the memory segment.
 * @param word_offset_in_segment The word offset within that segment.
 * @param start_bit The starting bit position (0-31) from LSB.
 * @param num_bits The number of bits to read (1-32).
 * @return The extracted bits, right-aligned. Returns 0 on parameter error.
 */
uint32_t mem_read_bits(uint32_t segment_base_word_offset, uint32_t word_offset_in_segment, uint8_t start_bit, uint8_t num_bits);

/**
 * @brief Writes a 32-bit word to a specified memory location.
 * @param segment_base_word_offset The base word offset of the memory segment.
 * @param word_offset_in_segment The word offset within that segment.
 * @param data The 32-bit data to write.
 */
void mem_write_word(uint32_t segment_base_word_offset, uint32_t word_offset_in_segment, uint32_t data);

/**
 * @brief Writes a specified number of bits to a 32-bit word in memory (read-modify-write).
 * @param segment_base_word_offset The base word offset of the memory segment.
 * @param word_offset_in_segment The word offset within that segment.
 * @param data_to_write The data to write (only the lower num_bits are used).
 * @param start_bit The starting bit position (0-31) from LSB where data will be written.
 * @param num_bits The number of bits to write (1-32).
 */
void mem_write_bits(uint32_t segment_base_word_offset, uint32_t word_offset_in_segment, uint32_t data_to_write, uint8_t start_bit, uint8_t num_bits);

#endif // MEM_H