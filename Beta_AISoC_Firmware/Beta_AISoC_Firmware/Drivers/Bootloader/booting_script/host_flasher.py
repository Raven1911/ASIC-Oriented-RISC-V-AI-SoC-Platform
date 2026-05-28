"""
@file host_flasher.py
@author Tran Nhat Minh
@brief Ultimate Python Host Flasher for PROT-BOOT-H v4.0
@details Implements Stop-and-Wait ARQ, Dynamic Timeouts, Stream Sync, Hunter Mode, and Linux Buffer Fix.
"""

import serial
import struct
import time
import zlib
import os
import argparse

# ==========================================================================
# PROTOCOL CONSTANTS
# ==========================================================================
FRAME_SOF       = 0xA5
FRAME_EOF       = 0x55
MAX_PAYLOAD     = 1024

# Command Opcodes
CMD_INFO        = 0x02
CMD_ERASE       = 0x03
CMD_WRITE       = 0x04
CMD_VERIFY      = 0x05
CMD_JUMP        = 0x06
CMD_GET_CAP     = 0x07

# Target Status Responses
STATUS_ACK      = 0x79
STATUS_NACK     = 0x1F
STATUS_ERROR    = 0xEE

# Memory Constants (Must match Target's memory map)
BOOT_FLASH_IMAGE_OFFSET = 0x00001000

# Dictionaries for Debug Printing
CMD_NAMES = {CMD_INFO: "INFO", CMD_ERASE: "ERASE", CMD_WRITE: "WRITE", 
             CMD_VERIFY: "VERIFY", CMD_JUMP: "JUMP", CMD_GET_CAP: "GET_CAP"}
STATUS_NAMES = {STATUS_ACK: "ACK", STATUS_NACK: "NACK", STATUS_ERROR: "ERROR"}

class ProtBootHost:
    def __init__(self, port: str, baudrate: int = 230400, default_timeout: float = 2.0, debug: bool = False):
        self.port = port
        self.baudrate = baudrate
        self.default_timeout = default_timeout
        self.debug = debug
        self.ser = None
        self.seq = 0

    def connect(self):
        """Opens the serial port and clears OS-level buffers."""
        try:
            self.ser = serial.Serial(self.port, self.baudrate, timeout=self.default_timeout)
            self.ser.reset_input_buffer()
            self.ser.reset_output_buffer()
            print(f"[+] Connected to {self.port} at {self.baudrate} bps")
        except Exception as e:
            print(f"[-] Failed to connect: {e}")
            exit(1)

    def disconnect(self):
        """Safely closes the serial port."""
        if self.ser and self.ser.is_open:
            self.ser.close()
            print("[+] Disconnected")

    def calc_crc16(self, data: bytes) -> int:
        """Calculates CRC-16-CCITT (Poly 0x1021, Init 0xFFFF)."""
        crc = 0xFFFF
        for byte in data:
            crc ^= (byte << 8)
            for _ in range(8):
                if crc & 0x8000:
                    crc = ((crc << 1) ^ 0x1021) & 0xFFFF
                else:
                    crc = (crc << 1) & 0xFFFF
        return crc

    def send_frame(self, cmd: int, payload: bytes = b'', max_retries: int = 10) -> tuple:
        """Packs data, calculates CRC, transmits to Target, and handles ARQ retries."""
        payload_len = len(payload)
        if payload_len > MAX_PAYLOAD:
            raise ValueError("Payload exceeds maximum allowed size.")

        header = struct.pack('<BBBH', FRAME_SOF, self.seq, cmd, payload_len)
        crc_data = struct.pack('<BBH', self.seq, cmd, payload_len) + payload
        crc16 = self.calc_crc16(crc_data)
        footer = struct.pack('<HB', crc16, FRAME_EOF)
        frame = header + payload + footer

        if self.debug:
            cmd_str = CMD_NAMES.get(cmd, f"0x{cmd:02X}")
            hex_data = payload.hex().upper()
            if len(hex_data) > 32: hex_data = hex_data[:32] + "..."
            print(f"\n[DEBUG-TX] SEQ: {self.seq:03d} | CMD: {cmd_str:8s} | LEN: {payload_len:4d} | DATA: {hex_data:32s} | CRC: 0x{crc16:04X}")

        for attempt in range(max_retries):
            self.ser.write(frame)
            self.ser.flush()

            status, res_data = self.receive_response(expected_seq=self.seq)

            if status == STATUS_ACK:
                self.seq = (self.seq + 1) % 256
                return True, res_data
            elif status == STATUS_NACK:
                if self.debug: print(f"[!] NACK received. Retrying {attempt + 1}/{max_retries}...")
                continue
            elif status == STATUS_ERROR:
                self._parse_error(res_data)
                return False, b''
            elif status is None:
                # Nếu đang ở chế độ chờ Sync (Hunter Mode) thì không in lỗi ồn ào
                if cmd != CMD_GET_CAP: 
                    print(f"\n[!] Timeout waiting for response. Retrying {attempt + 1}/{max_retries}...")
                continue
                
        if cmd != CMD_GET_CAP:
            print("[-] Max retries reached. Communication failed.")
        return False, b''

    def receive_response(self, expected_seq: int = None) -> tuple:
        """Reads and validates the response frame. Implements Stream Synchronization."""
        original_timeout = self.ser.timeout
        deadline = time.time() + original_timeout

        try:
            while time.time() < deadline:
                sof_found = False

                # 1. SCAN FOR SOF
                while time.time() < deadline:
                    if self.ser.in_waiting > 0:
                        byte = self.ser.read(1)
                        if byte and byte[0] == FRAME_SOF:
                            sof_found = True
                            break
                    else:
                        time.sleep(0.001)

                if not sof_found:
                    break

                # 2. READ HEADER
                self.ser.timeout = max(0.001, deadline - time.time())
                header = self.ser.read(4)
                if len(header) < 4:
                    return None, b''

                seq_m, status, res_len = struct.unpack('<BBH', header)
                if res_len > MAX_PAYLOAD:
                    if self.debug:
                        print(f"  -> [RX-FAIL] Response length too large: {res_len}")
                    continue

                # [DYNAMIC TIMEOUT] Tính toán thời gian cần thiết để hứng trọn Payload
                dynamic_read_timeout = (res_len * 10.0 / self.baudrate) + 0.5
                if dynamic_read_timeout > original_timeout:
                    self.ser.timeout = dynamic_read_timeout

                # 3. READ PAYLOAD
                res_data = self.ser.read(res_len) if res_len > 0 else b''
                if len(res_data) < res_len:
                    return None, b''

                # 4. READ FOOTER
                footer = self.ser.read(3)
                if len(footer) < 3:
                    return None, b''

                crc_recv, eof = struct.unpack('<HB', footer)

                if self.debug:
                    st_str = STATUS_NAMES.get(status, f"0x{status:02X}")
                    hex_data = res_data.hex().upper()
                    if len(hex_data) > 32: hex_data = hex_data[:32] + "..."
                    print(f"[DEBUG-RX] SEQ: {seq_m:03d} | ST : {st_str:8s} | LEN: {res_len:4d} | DATA: {hex_data:32s} | CRC: 0x{crc_recv:04X} | EOF: 0x{eof:02X}")

                # 5. INTEGRITY VALIDATION
                if eof != FRAME_EOF:
                    if self.debug: print("  -> [RX-FAIL] Missing EOF Marker!")
                    return STATUS_NACK, b''

                crc_check_data = struct.pack('<BBH', seq_m, status, res_len) + res_data
                if self.calc_crc16(crc_check_data) != crc_recv:
                    if self.debug: print("  -> [RX-FAIL] CRC16 Mismatch!")
                    return STATUS_NACK, b''

                if expected_seq is not None and seq_m != expected_seq:
                    if self.debug:
                        print(f"  -> [RX-STALE] Expected SEQ {expected_seq:03d}, got {seq_m:03d}. Ignoring stale response.")
                    continue

                return status, res_data
        finally:
            self.ser.timeout = original_timeout

        return None, b''

    def _parse_error(self, err_data: bytes):
        """Decodes the 6-byte Error Diagnostic Payload."""
        if len(err_data) != 6:
            print(f"\n[-] Unknown error format: {err_data.hex()}")
            return
            
        err_cat, err_code, info = struct.unpack('<BBI', err_data)
        cat_str = {1: "COMM", 2: "LOGIC", 3: "FLASH"}.get(err_cat, "UNKNOWN")
        print(f"\n[-] TARGET ERROR -> Category: {cat_str}, Code: 0x{err_code:02X}, Info: 0x{info:08X}")

    # ==========================================================================
    # COMMAND IMPLEMENTATIONS
    # ==========================================================================

    def sync_with_target(self):
        """Hunter Mode: Liên tục Ping chờ Target Reset để bắt 'Cửa sổ vàng 2 giây'"""
        print("\n" + "="*60)
        print("[*] WAITING FOR TARGET BOOTLOADER...")
        print("[!] ACTION REQUIRED: Please press the RESET button on your FPGA board!")
        print("="*60 + "\n")
        
        original_timeout = self.ser.timeout
        self.ser.timeout = 0.2  # Timeout 200ms để Ping liên tục
        
        attempt = 0
        while True:
            self.ser.reset_input_buffer() 
            success, data = self.send_frame(CMD_GET_CAP, max_retries=1)
            
            if success and len(data) >= 14:
                print("\n\n[+] TARGET SYNCHRONIZED SUCCESSFULLY!")
                self.ser.timeout = original_timeout 
                
                ver, f_size, sec_size, page_size, imem = struct.unpack('<H I H H I', data)
                print(f"    - Bootloader Ver: {ver >> 8}.{ver & 0xFF}")
                print(f"    - Flash Size    : {f_size // 1024} KB")
                print(f"    - Page/Sector   : {page_size}B / {sec_size}B")
                print(f"    - IMEM Base     : 0x{imem:08X}")
                return page_size
            
            if not self.debug:
                print(".", end="", flush=True)
                if attempt % 40 == 0 and attempt > 0: print(" [Waiting...]")
            time.sleep(0.05)
            attempt += 1

    def flash_firmware(self, filepath: str, page_size: int):
        file_size = os.path.getsize(filepath)
        
        with open(filepath, 'rb') as f:
            firmware_data = f.read()
            
        file_crc32 = zlib.crc32(firmware_data) & 0xFFFFFFFF
        
        print(f"\n[*] Firmware Size: {file_size} bytes")
        print(f"[*] Firmware CRC32: 0x{file_crc32:08X}")

        # 1. SEND METADATA
        print("[*] Sending Metadata...")
        payload = struct.pack('<II I H', file_size, file_crc32, BOOT_FLASH_IMAGE_OFFSET, 0x0001)
        if not self.send_frame(CMD_INFO, payload)[0]: return False

        # 2. ERASE FLASH
        print("[*] Erasing Flash (This may take a while)...")
        erase_payload = struct.pack('<II', BOOT_FLASH_IMAGE_OFFSET, file_size)
        sectors_to_erase = (file_size + 4095) // 4096
        self.ser.timeout = (sectors_to_erase * 0.4) + 2.0 
        
        success, _ = self.send_frame(CMD_ERASE, erase_payload, max_retries=1)
        self.ser.timeout = self.default_timeout
        
        if not success: return False

        # 3. WRITE DATA
        print("[*] Programming Flash...")
        bytes_written = 0
        chunk_size = page_size 
        
        while bytes_written < file_size:
            chunk = firmware_data[bytes_written:bytes_written + chunk_size]
            payload = struct.pack('<I', bytes_written) + chunk
            
            if not self.send_frame(CMD_WRITE, payload)[0]:
                print(f"\n[-] Failed at offset 0x{bytes_written:08X}")
                return False
                
            bytes_written += len(chunk)
            progress = (bytes_written / file_size) * 100
            
            if not self.debug:
                print(f"\r    Progress: {progress:.1f}% ({bytes_written}/{file_size} Bytes)", end="")
                
            # [LINUX BUFFER FIX]: Nghỉ 10ms giữa mỗi Block để chống ngộp Buffer Linux/Target
            time.sleep(0.01) 
        
        if not self.debug: print()
        print("[*] Programming Complete.")

        # 4. DOUBLE VALIDATION
        print("[*] Triggering Hardware CRC Verification...")
        self.ser.timeout = ((file_size / 1000000.0) * 1.5) + 2.0
        
        success, res_data = self.send_frame(CMD_VERIFY)
        self.ser.timeout = self.default_timeout 
        
        if success and len(res_data) == 4:
            target_crc = struct.unpack('<I', res_data)[0]
            print(f"[+] Target reported CRC32: 0x{target_crc:08X}")
            if target_crc == file_crc32:
                print("[+] Double Validation PASSED! Firmware Committed.")
            else:
                print("[-] CRITICAL: CRC Mismatch despite ACK!")
                return False
        else:
            return False

        # 5. EXECUTION HANDOVER
        print("[*] Sending Jump Command...")
        if self.send_frame(CMD_JUMP)[0]:
            print("[+] SoC is now booting the new application!")
            return True
            
        return False

def main():
    parser = argparse.ArgumentParser(description="PROT-BOOT-H v4.0 Host Flasher for PicoRV32")
    parser.add_argument("port", help="Serial port (e.g., COM3 or /dev/ttyUSB0)")
    parser.add_argument("file", help="Path to the binary firmware (.bin)")
    parser.add_argument("--debug", action="store_true", help="Enable verbose packet debugging")
    args = parser.parse_args()

    flasher = ProtBootHost(args.port, debug=args.debug)
    flasher.connect()
    
    # 1. Kích hoạt chế độ Hunter Mode
    page_size = flasher.sync_with_target()
    
    # 2. Nếu bắt tay thành công, tiến hành nạp
    if page_size:
        flasher.flash_firmware(args.file, page_size)
        
    flasher.disconnect()

if __name__ == "__main__":
    main()
