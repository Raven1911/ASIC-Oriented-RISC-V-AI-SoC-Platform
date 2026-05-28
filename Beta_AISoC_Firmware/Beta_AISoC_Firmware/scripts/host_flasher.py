#!/usr/bin/env python3

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
import select
import sys
from pathlib import Path

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
WRITE_OFFSET_FIELD_SIZE = 4
MAX_WRITE_DATA = MAX_PAYLOAD - WRITE_OFFSET_FIELD_SIZE
DEFAULT_WRITE_CHUNK = 64
DEFAULT_WRITE_DELAY = 0.0
DEFAULT_BOOT_TIMEOUT = 2.0
DEFAULT_WRITE_TIMEOUT = 2.0
DEFAULT_BOOT_BAUD = 230400
DEFAULT_APP_BAUD = 230400
DEFAULT_FIRMWARE_FILE = Path(__file__).resolve().parents[1] / "Build" / "main.bin"
DEFAULT_CIFAR_INPUT = Path(__file__).resolve().parents[2] / "datasheet" / "input_all_preprocessed_10000.h"
DEFAULT_CIFAR_LABELS = Path(__file__).resolve().parents[2] / "datasheet" / "label_all_preprocessed_10000.h"

# Dictionaries for Debug Printing
CMD_NAMES = {CMD_INFO: "INFO", CMD_ERASE: "ERASE", CMD_WRITE: "WRITE", 
             CMD_VERIFY: "VERIFY", CMD_JUMP: "JUMP", CMD_GET_CAP: "GET_CAP"}
STATUS_NAMES = {STATUS_ACK: "ACK", STATUS_NACK: "NACK", STATUS_ERROR: "ERROR"}

class ProtBootHost:
    def __init__(self, port: str, baudrate: int = DEFAULT_BOOT_BAUD, default_timeout: float = DEFAULT_BOOT_TIMEOUT, debug: bool = False):
        self.port = port
        self.baudrate = baudrate
        self.default_timeout = default_timeout
        self.debug = debug
        self.ser = None
        self.seq = 0
        self.last_response_error = None

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

    def send_frame(self, cmd: int, payload: bytes = b'', max_retries: int = 10, stats: dict = None) -> tuple:
        """Packs data, calculates CRC, transmits to Target, and handles ARQ retries."""
        payload_len = len(payload)
        if payload_len > MAX_PAYLOAD:
            raise ValueError("Payload exceeds maximum allowed size.")
        self.last_response_error = None

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
                if stats is not None:
                    stats["nacks"] = stats.get("nacks", 0) + 1
                    stats["retries"] = stats.get("retries", 0) + 1
                detail = self.last_response_error or "Target/host NACK"
                self.last_response_error = f"{detail} (attempt {attempt + 1}/{max_retries})"
                if self.debug: print(f"[!] NACK received. Retrying {attempt + 1}/{max_retries}...")
                continue
            elif status == STATUS_ERROR:
                self._parse_error(res_data)
                return False, b''
            elif status is None:
                if stats is not None:
                    stats["timeouts"] = stats.get("timeouts", 0) + 1
                    stats["retries"] = stats.get("retries", 0) + 1
                detail = self.last_response_error or "Timeout waiting for response"
                self.last_response_error = f"{detail} (attempt {attempt + 1}/{max_retries})"
                # Nếu đang ở chế độ chờ Sync (Hunter Mode) thì không in lỗi ồn ào
                if self.debug and cmd != CMD_GET_CAP: 
                    print(f"\n[!] Timeout waiting for response. Retrying {attempt + 1}/{max_retries}...")
                retry_delay = min(0.02 * (2 ** attempt), 0.2)
                time.sleep(retry_delay)
                continue
                
        if cmd != CMD_GET_CAP:
            cmd_str = CMD_NAMES.get(cmd, f"0x{cmd:02X}")
            print(f"\n[-] Max retries reached for {cmd_str}. Communication failed.")
            if self.last_response_error:
                print(f"[-] Last response issue: {self.last_response_error}")
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
                    self.last_response_error = f"Incomplete response header: got {len(header)}/4 byte(s)"
                    return None, b''

                seq_m, status, res_len = struct.unpack('<BBH', header)
                if res_len > MAX_PAYLOAD:
                    self.last_response_error = f"Response length too large: {res_len}"
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
                    self.last_response_error = f"Incomplete response payload: got {len(res_data)}/{res_len} byte(s)"
                    return None, b''

                # 4. READ FOOTER
                footer = self.ser.read(3)
                if len(footer) < 3:
                    self.last_response_error = f"Incomplete response footer: got {len(footer)}/3 byte(s)"
                    return None, b''

                crc_recv, eof = struct.unpack('<HB', footer)

                if self.debug:
                    st_str = STATUS_NAMES.get(status, f"0x{status:02X}")
                    hex_data = res_data.hex().upper()
                    if len(hex_data) > 32: hex_data = hex_data[:32] + "..."
                    print(f"[DEBUG-RX] SEQ: {seq_m:03d} | ST : {st_str:8s} | LEN: {res_len:4d} | DATA: {hex_data:32s} | CRC: 0x{crc_recv:04X} | EOF: 0x{eof:02X}")

                # 5. INTEGRITY VALIDATION
                if eof != FRAME_EOF:
                    self.last_response_error = f"Missing EOF marker: got 0x{eof:02X}"
                    if self.debug: print("  -> [RX-FAIL] Missing EOF Marker!")
                    return STATUS_NACK, b''

                crc_check_data = struct.pack('<BBH', seq_m, status, res_len) + res_data
                if self.calc_crc16(crc_check_data) != crc_recv:
                    self.last_response_error = "Response CRC16 mismatch"
                    if self.debug: print("  -> [RX-FAIL] CRC16 Mismatch!")
                    return STATUS_NACK, b''

                if expected_seq is not None and seq_m != expected_seq:
                    self.last_response_error = f"Stale response seq: expected {expected_seq:03d}, got {seq_m:03d}"
                    if self.debug:
                        print(f"  -> [RX-STALE] Expected SEQ {expected_seq:03d}, got {seq_m:03d}. Ignoring stale response.")
                    continue

                return status, res_data
        finally:
            self.ser.timeout = original_timeout

        self.last_response_error = "Timeout while waiting for response SOF"
        return None, b''

    def _parse_error(self, err_data: bytes):
        """Decodes the 6-byte Error Diagnostic Payload."""
        if len(err_data) != 6:
            print(f"\n[-] Unknown error format: {err_data.hex()}")
            return
            
        err_cat, err_code, info = struct.unpack('<BBI', err_data)
        cat_str = {1: "COMM", 2: "LOGIC", 3: "FLASH"}.get(err_cat, "UNKNOWN")
        print(f"\n[-] TARGET ERROR -> Category: {cat_str}, Code: 0x{err_code:02X}, Info: 0x{info:08X}")

    def _print_progress(self, sent: int, total: int, start_time: float = None, retries: int = 0):
        """Prints a compact single-line transfer progress bar."""
        width = 28
        ratio = sent / total if total else 1.0
        filled = int(width * ratio)
        bar = "#" * filled + "-" * (width - filled)
        suffix = ""
        if start_time is not None:
            elapsed = max(time.monotonic() - start_time, 0.001)
            rate = sent / elapsed
            suffix = f" | {rate:7.1f} B/s | retries {retries}"
        print(f"\r[{bar}] {ratio * 100:6.2f}% {sent}/{total} bytes{suffix}", end="", flush=True)

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

    def flash_firmware(
        self,
        filepath: str,
        page_size: int,
        chunk_size: int = None,
        write_delay: float = DEFAULT_WRITE_DELAY,
        write_timeout: float = DEFAULT_WRITE_TIMEOUT,
    ):
        file_size = os.path.getsize(filepath)
        
        with open(filepath, 'rb') as f:
            firmware_data = f.read()
            
        file_crc32 = zlib.crc32(firmware_data) & 0xFFFFFFFF
        
        print(f"\n[*] Firmware Size: {file_size} bytes")
        print(f"[*] Firmware CRC32: 0x{file_crc32:08X}")

        if chunk_size is None:
            chunk_size = DEFAULT_WRITE_CHUNK
        elif chunk_size > MAX_WRITE_DATA:
            print(f"[-] --chunk-size must be <= {MAX_WRITE_DATA} bytes")
            return False

        print(f"[*] Write Chunk: {chunk_size} data bytes ({chunk_size + WRITE_OFFSET_FIELD_SIZE}B CMD_WRITE payload)")

        # 1. SEND METADATA
        print("[*] Sending Metadata...")
        payload = struct.pack('<II I H', file_size, file_crc32, BOOT_FLASH_IMAGE_OFFSET, 0x0001)
        if not self.send_frame(CMD_INFO, payload)[0]: return False

        # 2. ERASE FLASH
        print("[*] Erasing Flash (This may take a while)...")
        erase_payload = struct.pack('<II', BOOT_FLASH_IMAGE_OFFSET, file_size)
        sectors_to_erase = (file_size + 4095) // 4096
        old_timeout = self.ser.timeout
        self.ser.timeout = max((sectors_to_erase * 1.0) + 10.0, self.default_timeout)

        success, _ = self.send_frame(CMD_ERASE, erase_payload, max_retries=3)
        self.ser.timeout = old_timeout
        
        if not success: return False

        # 3. WRITE DATA
        print("[*] Programming Flash...")
        bytes_written = 0
        write_start = time.monotonic()
        write_stats = {}
        old_timeout = self.ser.timeout
        if write_timeout is not None:
            self.ser.timeout = write_timeout
        
        try:
            while bytes_written < file_size:
                chunk = firmware_data[bytes_written:bytes_written + chunk_size]
                payload = struct.pack('<I', bytes_written) + chunk
                
                if not self.send_frame(CMD_WRITE, payload, stats=write_stats)[0]:
                    print(f"\n[-] Failed at offset 0x{bytes_written:08X}")
                    return False
                    
                bytes_written += len(chunk)
                
                if not self.debug:
                    self._print_progress(bytes_written, file_size, write_start, write_stats.get("retries", 0))
                    
                if write_delay > 0:
                    time.sleep(write_delay)
        finally:
            self.ser.timeout = old_timeout
        
        if not self.debug: print()
        print(
            "[*] Write stats: "
            f"{write_stats.get('retries', 0)} retries, "
            f"{write_stats.get('timeouts', 0)} timeout(s), "
            f"{write_stats.get('nacks', 0)} NACK(s)."
        )
        print("[*] Programming Complete.")

        # 4. DOUBLE VALIDATION
        print("[*] Triggering Hardware CRC Verification...")
        old_timeout = self.ser.timeout
        self.ser.timeout = max(((file_size / 1000000.0) * 3.0) + 10.0, self.default_timeout)

        success, res_data = self.send_frame(CMD_VERIFY, max_retries=3)
        self.ser.timeout = old_timeout
        
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

    def _print_monitor_rx(self, data: bytes, display_format: str):
        if display_format == "hex":
            print(" ".join(f"{byte:02X}" for byte in data), flush=True)
            return

        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()

    def _encode_monitor_line(self, line: str, newline_mode: str) -> bytes:
        text = line.rstrip("\r\n")
        newline = {
            "none": "",
            "lf": "\n",
            "cr": "\r",
            "crlf": "\r\n",
        }[newline_mode]
        return (text + newline).encode()

    def monitor_uart(
        self,
        timeout_s: float = 0.0,
        display_format: str = "ascii",
        input_mode: str = "char",
        newline_mode: str = "lf",
        baudrate: int = None,
        accuracy_args: argparse.Namespace = None,
    ):
        """Use the current shell as a simple UART terminal."""
        if not self.ser or not self.ser.is_open:
            print("[-] Serial port is not open.")
            return

        if baudrate is not None and self.ser.baudrate != baudrate:
            self.ser.baudrate = baudrate
            self.baudrate = baudrate
            self.ser.reset_input_buffer()
            self.ser.reset_output_buffer()
            print(f"[*] UART monitor switched to {baudrate} bps")

        print("\n[*] UART monitor started. Press Ctrl-] to exit.")
        print(f"[*] Monitor display format: {display_format}")
        print(f"[*] Monitor input mode: {input_mode}")
        if input_mode == "line":
            print(f"[*] Monitor newline mode: {newline_mode}")
            if accuracy_args is not None:
                print(f"[*] Type {accuracy_args.enter_command} to run integrated ALL_CNN_C accuracy stream.")
        if timeout_s > 0:
            print(f"[*] Monitor timeout: {timeout_s:.1f}s")

        old_timeout = self.ser.timeout
        self.ser.timeout = 0
        deadline = time.monotonic() + timeout_s if timeout_s > 0 else None

        stdin_fd = sys.stdin.fileno()
        serial_fd = self.ser.fileno()
        old_term = None
        stdin_is_tty = sys.stdin.isatty()
        raw_stdin = (input_mode == "char" and os.name == "posix" and stdin_is_tty)

        try:
            if raw_stdin:
                import termios
                import tty

                old_term = termios.tcgetattr(stdin_fd)
                tty.setraw(stdin_fd)

            while True:
                if deadline is not None and time.monotonic() >= deadline:
                    print("\n[*] Monitor timeout reached.")
                    break

                read_fds = [serial_fd]
                if stdin_is_tty:
                    read_fds.append(stdin_fd)

                readable, _, _ = select.select(read_fds, [], [], 0.05)

                if serial_fd in readable:
                    data = self.ser.read(self.ser.in_waiting or 1)
                    if data:
                        self._print_monitor_rx(data, display_format)

                if raw_stdin and stdin_fd in readable:
                    data = os.read(stdin_fd, 1024)
                    if b"\x1d" in data:  # Ctrl-]
                        data = data.split(b"\x1d", 1)[0]
                        if data:
                            self.ser.write(data)
                            self.ser.flush()
                        print("\n[*] UART monitor stopped.")
                        break

                    if data:
                        self.ser.write(data)
                        self.ser.flush()

                if input_mode == "line" and stdin_fd in readable:
                    line = sys.stdin.readline()
                    if line == "":
                        print("\n[*] Stdin closed, leaving monitor.")
                        break

                    if "\x1d" in line:  # Ctrl-]
                        line = line.split("\x1d", 1)[0]
                        data = self._encode_monitor_line(line, newline_mode)
                        if data:
                            self.ser.write(data)
                            self.ser.flush()
                        print("\n[*] UART monitor stopped.")
                        break

                    if accuracy_args is not None and line.strip() == accuracy_args.enter_command:
                        self._run_monitor_accuracy(accuracy_args)
                        continue

                    data = self._encode_monitor_line(line, newline_mode)
                    if data:
                        self.ser.write(data)
                        self.ser.flush()

        except KeyboardInterrupt:
            print("\n[*] UART monitor interrupted.")
        finally:
            if old_term is not None:
                import termios

                termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_term)
            self.ser.timeout = old_timeout

    def _run_monitor_accuracy(self, accuracy_args: argparse.Namespace):
        """Run ALL_CNN_C UART accuracy streaming on the already-open monitor port."""
        print("\n[*] Starting integrated ALL_CNN_C accuracy stream...")
        old_timeout = self.ser.timeout
        try:
            import allcnn_uart_accuracy

            allcnn_uart_accuracy.run_accuracy_stream(self.ser, accuracy_args)
        except Exception as exc:
            print(f"\n[-] ALL_CNN_C accuracy stream failed: {exc}")
        finally:
            self.ser.timeout = old_timeout
            self.ser.reset_input_buffer()
            self.ser.reset_output_buffer()
            print("[*] Returned to UART monitor.")

def main():
    parser = argparse.ArgumentParser(description="PROT-BOOT-H v4.0 Host Flasher for PicoRV32")
    parser.add_argument("port", help="Serial port (e.g., COM3 or /dev/ttyUSB0)")
    parser.add_argument(
        "file",
        nargs="?",
        default=str(DEFAULT_FIRMWARE_FILE),
        help=f"Path to the binary firmware (.bin), default: {DEFAULT_FIRMWARE_FILE}",
    )
    parser.add_argument("--debug", action="store_true", help="Enable verbose packet debugging")
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=None,
        help=f"Data bytes per CMD_WRITE frame, default: {DEFAULT_WRITE_CHUNK}, max: {MAX_WRITE_DATA}",
    )
    parser.add_argument(
        "--write-timeout",
        type=float,
        default=DEFAULT_WRITE_TIMEOUT,
        help=f"UART response timeout for CMD_WRITE frames, default: {DEFAULT_WRITE_TIMEOUT:g}s",
    )
    parser.add_argument(
        "--boot-timeout",
        type=float,
        default=DEFAULT_BOOT_TIMEOUT,
        help=f"Base UART response timeout for bootloader commands, default: {DEFAULT_BOOT_TIMEOUT:g}s",
    )
    parser.add_argument(
        "--write-delay",
        type=float,
        default=DEFAULT_WRITE_DELAY,
        help=f"Delay after each successful CMD_WRITE frame, default: {DEFAULT_WRITE_DELAY:g}s",
    )
    parser.add_argument(
        "--monitor",
        action="store_true",
        help="Keep UART open as a simple terminal after successful flash/jump",
    )
    parser.add_argument(
        "--terminal-only",
        "--monitor-only",
        action="store_true",
        dest="terminal_only",
        help="Open UART terminal only; do not sync bootloader or flash firmware",
    )
    parser.add_argument(
        "--monitor-timeout",
        type=float,
        default=0.0,
        help="Seconds to stay in monitor mode, 0 means forever",
    )
    parser.add_argument(
        "--monitor-format",
        choices=("ascii", "hex"),
        default="ascii",
        help="UART monitor RX display format, default: ascii",
    )
    parser.add_argument(
        "--monitor-input",
        choices=("char", "line"),
        default="char",
        help="UART monitor TX input mode, default: char",
    )
    parser.add_argument(
        "--monitor-newline",
        choices=("none", "lf", "cr", "crlf"),
        default="lf",
        help="Newline appended in --monitor-input line mode, default: lf",
    )
    parser.add_argument(
        "--monitor-baud",
        type=int,
        default=DEFAULT_APP_BAUD,
        help=f"UART baudrate used by --monitor after flashing/jump, default: {DEFAULT_APP_BAUD}",
    )
    parser.add_argument(
        "--monitor-accuracy",
        action="store_true",
        help="In line monitor mode, intercept 4.5 and run the ALL_CNN_C UART accuracy stream on this serial port",
    )
    parser.add_argument(
        "--accuracy-input",
        type=Path,
        default=DEFAULT_CIFAR_INPUT,
        help="CIFAR input header used by --monitor-accuracy",
    )
    parser.add_argument(
        "--accuracy-labels",
        type=Path,
        default=DEFAULT_CIFAR_LABELS,
        help="CIFAR label header used by --monitor-accuracy",
    )
    parser.add_argument("--accuracy-count", type=int, default=10000, help="Number of images for --monitor-accuracy")
    parser.add_argument("--accuracy-skip", type=int, default=0, help="Number of images to skip for --monitor-accuracy")
    parser.add_argument(
        "--accuracy-input-layout",
        choices=("hwc", "chw"),
        default="hwc",
        help="Layout in the CIFAR input header. Default hwc; host sends CHW to the accelerator",
    )
    parser.add_argument("--accuracy-chunk-size", type=int, default=32, help="DATA payload bytes per frame")
    parser.add_argument("--accuracy-timeout", type=float, default=10.0, help="UART protocol timeout for accuracy stream")
    parser.add_argument("--accuracy-run-timeout", type=float, default=3.0, help="Per-image RUN timeout for accuracy stream")
    parser.add_argument("--accuracy-retries", type=int, default=5, help="Retry count for firmware NACK frames")
    parser.add_argument("--accuracy-inter-frame-delay", type=float, default=0.01, help="Optional delay after each ACKed accuracy frame")
    parser.add_argument("--accuracy-tx-slice-size", type=int, default=4, help="Write accuracy frames to UART in small slices")
    parser.add_argument("--accuracy-tx-slice-delay", type=float, default=0.001, help="Delay between UART TX slices")
    parser.add_argument("--accuracy-progress-every", type=int, default=10, help="Print accuracy progress every N images")
    parser.add_argument("--accuracy-command", default="4.5", help="Monitor command intercepted by --monitor-accuracy")
    args = parser.parse_args()

    if args.chunk_size is not None and args.chunk_size <= 0:
        parser.error("--chunk-size must be a positive integer")
    if args.write_timeout is not None and args.write_timeout <= 0:
        parser.error("--write-timeout must be > 0")
    if args.boot_timeout <= 0:
        parser.error("--boot-timeout must be > 0")
    if args.write_delay < 0:
        parser.error("--write-delay must be >= 0")
    if args.monitor_timeout < 0:
        parser.error("--monitor-timeout must be >= 0")
    if args.monitor_baud <= 0:
        parser.error("--monitor-baud must be positive")
    if args.monitor_accuracy and args.monitor_input != "line":
        parser.error("--monitor-accuracy requires --monitor-input line")
    if args.accuracy_count <= 0:
        parser.error("--accuracy-count must be positive")
    if args.accuracy_skip < 0:
        parser.error("--accuracy-skip must be >= 0")
    if args.accuracy_chunk_size <= 0 or args.accuracy_chunk_size > 1016 or (args.accuracy_chunk_size & 1):
        parser.error("--accuracy-chunk-size must be an even value in range 2..1016")
    if args.accuracy_timeout <= 0 or args.accuracy_run_timeout <= 0:
        parser.error("--accuracy-timeout and --accuracy-run-timeout must be positive")
    if args.accuracy_retries < 0:
        parser.error("--accuracy-retries must be >= 0")
    if args.accuracy_inter_frame_delay < 0:
        parser.error("--accuracy-inter-frame-delay must be >= 0")
    if args.accuracy_tx_slice_size < 0:
        parser.error("--accuracy-tx-slice-size must be >= 0")
    if args.accuracy_tx_slice_delay < 0:
        parser.error("--accuracy-tx-slice-delay must be >= 0")

    accuracy_args = None
    if args.monitor_accuracy:
        accuracy_args = argparse.Namespace(
            input=args.accuracy_input,
            labels=args.accuracy_labels,
            count=args.accuracy_count,
            skip=args.accuracy_skip,
            input_layout=args.accuracy_input_layout,
            chunk_size=args.accuracy_chunk_size,
            timeout=args.accuracy_timeout,
            run_timeout=args.accuracy_run_timeout,
            retries=args.accuracy_retries,
            inter_frame_delay=args.accuracy_inter_frame_delay,
            tx_slice_size=args.accuracy_tx_slice_size,
            tx_slice_delay=args.accuracy_tx_slice_delay,
            enter_command=args.accuracy_command,
            no_enter_command=False,
            progress_every=args.accuracy_progress_every,
            debug=args.debug,
        )

    flasher = ProtBootHost(args.port, default_timeout=args.boot_timeout, debug=args.debug)
    flasher.connect()

    try:
        if args.terminal_only:
            flasher.monitor_uart(
                args.monitor_timeout,
                args.monitor_format,
                args.monitor_input,
                args.monitor_newline,
                args.monitor_baud,
                accuracy_args,
            )
            return

        # 1. Kích hoạt chế độ Hunter Mode
        page_size = flasher.sync_with_target()

        # 2. Nếu bắt tay thành công, tiến hành nạp
        flash_ok = False
        if page_size:
            chunk_size = args.chunk_size if args.chunk_size is not None else DEFAULT_WRITE_CHUNK
            flash_ok = flasher.flash_firmware(
                args.file,
                page_size,
                chunk_size,
                args.write_delay,
                args.write_timeout,
            )

        if args.monitor and flash_ok:
            flasher.monitor_uart(
                args.monitor_timeout,
                args.monitor_format,
                args.monitor_input,
                args.monitor_newline,
                args.monitor_baud,
                accuracy_args,
            )
    finally:
        flasher.disconnect()

if __name__ == "__main__":
    main()
