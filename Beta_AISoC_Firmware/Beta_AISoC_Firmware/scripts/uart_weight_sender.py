#!/usr/bin/env python3
"""Send NNoM weights with a bootloader-style framed UART protocol."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import struct
import time
import zlib

import serial


SOF = 0xA5
EOF = 0x55

CMD_INFO = 0x02
CMD_ERASE = 0x03
CMD_WRITE = 0x04
CMD_VERIFY = 0x05
CMD_GET_CAP = 0x07

ACK = 0x79
NACK = 0x1F
ERROR = 0xEE

DEFAULT_BAUD = 230400
DEFAULT_CHUNK_SIZE = 64
MAX_PAYLOAD_SIZE = 1024
MAX_WRITE_CHUNK_SIZE = MAX_PAYLOAD_SIZE - 4
SOC_FLASH_SIZE = 16 * 1024 * 1024
SAFE_MIN_FLASH_OFFSET = 0x00200000
DEFAULT_FLASH_OFFSET = 0x00200000
DEFAULT_MENU_TIMEOUT = 3.0
DEFAULT_POST_COMMAND_TIMEOUT = 0.3


class ProtocolError(RuntimeError):
    pass


@dataclass
class ResponseFrame:
    seq: int
    status: int
    payload: bytes


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Send weight payload to SPI Flash through firmware UART.")
    parser.add_argument("--port", required=True, help="Serial port, for example /dev/ttyUSB0 or COM3.")
    parser.add_argument("--input", "-i", required=True, type=Path, help="Input weight file, binary or text .mem/.hex.")
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD, help=f"UART baudrate, default {DEFAULT_BAUD}.")
    parser.add_argument("--chunk-size", type=int, default=DEFAULT_CHUNK_SIZE, help=f"WRITE data bytes per frame, default {DEFAULT_CHUNK_SIZE}, max {MAX_WRITE_CHUNK_SIZE}.")
    parser.add_argument(
        "--flash-offset",
        type=lambda x: int(x, 0),
        default=DEFAULT_FLASH_OFFSET,
        help=f"24-bit SPI Flash offset, default 0x{DEFAULT_FLASH_OFFSET:06X}.",
    )
    parser.add_argument("--timeout", type=float, default=1.0, help="UART read timeout in seconds.")
    parser.add_argument("--retries", type=int, default=10, help="Retries per command frame.")
    parser.add_argument("--write-timeout", type=float, default=2.0, help="UART response timeout for WRITE frames, default 2.0 seconds.")
    parser.add_argument("--write-delay", type=float, default=0.001, help="Delay after each successful WRITE frame, default 1ms.")
    parser.add_argument(
        "--enter-command",
        default="2.1",
        help="ASCII command sent before framed protocol. Use empty string if already in receiver mode.",
    )
    parser.add_argument(
        "--interactive-menu",
        action="store_true",
        help="Show SoC UART menu first, then prompt for the menu command before binary transfer.",
    )
    parser.add_argument(
        "--menu-timeout",
        type=float,
        default=DEFAULT_MENU_TIMEOUT,
        help=f"Seconds to mirror SoC UART before prompting in --interactive-menu, default {DEFAULT_MENU_TIMEOUT}.",
    )
    parser.add_argument(
        "--post-command-timeout",
        type=float,
        default=DEFAULT_POST_COMMAND_TIMEOUT,
        help=(
            "Seconds to drain command echo/logs after entering weight mode, "
            f"default {DEFAULT_POST_COMMAND_TIMEOUT}."
        ),
    )
    parser.add_argument("--debug", action="store_true", help="Print command/response details.")
    args = parser.parse_args()

    if not (1 <= args.chunk_size <= MAX_WRITE_CHUNK_SIZE):
        parser.error(f"--chunk-size must be in range 1..{MAX_WRITE_CHUNK_SIZE}")
    if args.retries < 1:
        parser.error("--retries must be >= 1")
    if args.write_timeout <= 0:
        parser.error("--write-timeout must be > 0")
    if args.write_delay < 0:
        parser.error("--write-delay must be >= 0")
    if not (0 <= args.flash_offset <= 0xFFFFFF):
        parser.error("--flash-offset must fit in 24 bits")
    if args.flash_offset < SAFE_MIN_FLASH_OFFSET:
        parser.error(f"--flash-offset must be >= 0x{SAFE_MIN_FLASH_OFFSET:06X} to avoid boot/app flash")
    if (args.flash_offset % 4096) != 0:
        parser.error("--flash-offset must be 4KB sector-aligned")
    if args.menu_timeout < 0:
        parser.error("--menu-timeout must be >= 0")
    if args.post_command_timeout < 0:
        parser.error("--post-command-timeout must be >= 0")

    return args


def load_payload(path: Path) -> bytes:
    if not path.exists():
        raise FileNotFoundError(path)

    if path.suffix.lower() == ".bin":
        data = path.read_bytes()
    else:
        payload = bytearray()
        for line_no, line in enumerate(path.read_text(encoding="ascii").splitlines(), start=1):
            raw = line.strip().replace(" ", "")
            if not raw or raw.startswith("//") or raw.startswith("#") or raw.startswith("@"):
                continue
            if len(raw) % 2 != 0:
                raise ValueError(f"Invalid hex length at line {line_no}: {line}")
            payload.extend(bytes.fromhex(raw))
        data = bytes(payload)

    if not data:
        raise ValueError("Input produced empty payload")

    return data


def crc16(data: bytes, init: int = 0xFFFF) -> int:
    crc = init
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


def build_request(seq: int, cmd: int, payload: bytes) -> bytes:
    header = bytes([seq & 0xFF, cmd & 0xFF]) + struct.pack("<H", len(payload))
    crc = crc16(header + payload)
    return bytes([SOF]) + header + payload + struct.pack("<H", crc) + bytes([EOF])


def read_exact(ser: serial.Serial, count: int) -> bytes:
    data = ser.read(count)
    if len(data) != count:
        raise TimeoutError(f"Expected {count} byte(s), got {len(data)}")
    return data


def drain_input(ser: serial.Serial, quiet_time_s: float = 0.05) -> bytes:
    chunks: list[bytes] = []
    deadline = time.monotonic() + quiet_time_s

    while time.monotonic() < deadline:
        waiting = ser.in_waiting
        if waiting:
            chunks.append(ser.read(waiting))
            deadline = time.monotonic() + quiet_time_s
        else:
            time.sleep(0.005)

    return b"".join(chunks)


def mirror_uart_until_idle(ser: serial.Serial, total_timeout_s: float, idle_timeout_s: float = 0.2) -> bytes:
    if total_timeout_s <= 0:
        return b""

    previous_timeout = ser.timeout
    ser.timeout = min(0.05, total_timeout_s)
    collected = bytearray()
    start = time.monotonic()
    last_rx: float | None = None

    try:
        while (time.monotonic() - start) < total_timeout_s:
            waiting = ser.in_waiting
            chunk = ser.read(waiting if waiting > 0 else 1)

            if chunk:
                collected.extend(chunk)
                print(chunk.decode("utf-8", errors="replace"), end="", flush=True)
                last_rx = time.monotonic()
                continue

            if last_rx is not None and (time.monotonic() - last_rx) >= idle_timeout_s:
                break
    finally:
        ser.timeout = previous_timeout

    return bytes(collected)


def enter_receiver_mode(ser: serial.Serial, args: argparse.Namespace) -> None:
    if not args.enter_command:
        return

    if args.interactive_menu:
        print("[menu] Listening to SoC UART. Reset the SoC now if the menu is not visible.")
        mirror_uart_until_idle(ser, args.menu_timeout)
        command = input(f"\nEnter SoC command to start weight mode [{args.enter_command}]: ").strip()
        if not command:
            command = args.enter_command
    else:
        command = args.enter_command

    ser.write((command + "\n").encode("ascii"))
    ser.flush()

    if args.interactive_menu:
        mirror_uart_until_idle(ser, args.post_command_timeout, idle_timeout_s=0.05)
    else:
        time.sleep(args.post_command_timeout)
        drain_input(ser)


def read_response(ser: serial.Serial, expected_seq: int, debug: bool = False) -> ResponseFrame:
    original_timeout = ser.timeout or 1.0
    deadline = time.monotonic() + original_timeout
    expected_seq &= 0xFF
    last_issue = "timeout"

    while time.monotonic() < deadline:
        waiting = max(0.001, deadline - time.monotonic())
        ser.timeout = waiting
        start = ser.read(1)
        if not start:
            break
        if start[0] != SOF:
            continue

        ser.timeout = max(0.001, deadline - time.monotonic())
        header = ser.read(4)
        if len(header) != 4:
            last_issue = f"incomplete response header: got {len(header)}/4 byte(s)"
            break

        seq = header[0]
        status = header[1]
        length = struct.unpack("<H", header[2:4])[0]
        if length > MAX_PAYLOAD_SIZE:
            last_issue = f"response length too large: {length}"
            if debug:
                print(f"[debug] RX stale/bad length seq={seq} len={length}; resyncing")
            continue

        ser.timeout = max(0.001, deadline - time.monotonic())
        payload = ser.read(length)
        if len(payload) != length:
            last_issue = f"incomplete response payload: got {len(payload)}/{length} byte(s)"
            break

        ser.timeout = max(0.001, deadline - time.monotonic())
        footer = ser.read(3)
        if len(footer) != 3:
            last_issue = f"incomplete response footer: got {len(footer)}/3 byte(s)"
            break

        crc_l, crc_h, eof = footer
        received_crc = crc_l | (crc_h << 8)
        calculated_crc = crc16(header + payload)

        if eof != EOF:
            last_issue = f"bad response EOF 0x{eof:02X}"
            if debug:
                print(f"[debug] RX bad EOF seq={seq}: 0x{eof:02X}; resyncing")
            continue
        if calculated_crc != received_crc:
            last_issue = f"bad response CRC: got 0x{received_crc:04X}, expected 0x{calculated_crc:04X}"
            if debug:
                print(f"[debug] RX bad CRC seq={seq}; resyncing")
            continue
        if seq != expected_seq:
            last_issue = f"stale response seq: got {seq}, expected {expected_seq}"
            if debug:
                print(f"[debug] RX stale seq={seq}, expected={expected_seq}; ignoring")
            continue

        return ResponseFrame(seq=seq, status=status, payload=payload)

    raise TimeoutError(last_issue)


def decode_error(payload: bytes) -> str:
    if len(payload) >= 6:
        category = payload[0]
        code = payload[1]
        info = struct.unpack("<I", payload[2:6])[0]
        return f"category=0x{category:02X}, code=0x{code:02X}, info=0x{info:08X}"
    return payload.hex(" ")


def send_command(
    ser: serial.Serial,
    seq: int,
    cmd: int,
    payload: bytes,
    retries: int,
    debug: bool,
    timeout_override: float | None = None,
    stats: dict[str, int] | None = None,
) -> bytes:
    frame = build_request(seq, cmd, payload)
    previous_timeout = ser.timeout

    if timeout_override is not None:
        ser.timeout = timeout_override

    try:
        for attempt in range(1, retries + 1):
            if debug:
                print(f"[debug] TX seq={seq} cmd=0x{cmd:02X} len={len(payload)} attempt={attempt}")

            ser.write(frame)
            ser.flush()

            try:
                response = read_response(ser, seq, debug)
            except TimeoutError as exc:
                if debug:
                    print(f"[debug] RX failed: {exc}")
                if stats is not None:
                    stats["timeouts"] = stats.get("timeouts", 0) + 1
                    stats["retries"] = stats.get("retries", 0) + 1
                if attempt == retries:
                    raise
                retry_delay = min(0.02 * (2 ** (attempt - 1)), 0.2)
                time.sleep(retry_delay)
                continue

            if debug:
                print(f"[debug] RX seq={response.seq} status=0x{response.status:02X} len={len(response.payload)}")

            if response.status == ACK:
                return response.payload
            if response.status == NACK:
                if stats is not None:
                    stats["nacks"] = stats.get("nacks", 0) + 1
                    stats["retries"] = stats.get("retries", 0) + 1
                retry_delay = min(0.02 * (2 ** (attempt - 1)), 0.2)
                time.sleep(retry_delay)
                if attempt == retries:
                    raise ProtocolError(f"Command 0x{cmd:02X} got NACK after {retries} attempts")
                continue
            if response.status == ERROR:
                raise ProtocolError(f"Target error for cmd 0x{cmd:02X}: {decode_error(response.payload)}")

            raise ProtocolError(f"Unexpected status 0x{response.status:02X}")
    finally:
        ser.timeout = previous_timeout

    raise ProtocolError(f"Command 0x{cmd:02X} failed")


def print_progress(sent: int, total: int, start_time: float | None = None, retries: int = 0) -> None:
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


def send_weights(args: argparse.Namespace) -> None:
    payload = load_payload(args.input)
    if len(payload) > (SOC_FLASH_SIZE - args.flash_offset):
        raise ValueError(f"Payload {len(payload)}B does not fit from flash offset 0x{args.flash_offset:06X}")

    payload_crc = zlib.crc32(payload) & 0xFFFFFFFF
    print(f"Loaded {len(payload)} bytes from {args.input}")
    print(f"Payload CRC32: 0x{payload_crc:08X}")

    with serial.Serial(args.port, args.baud, timeout=args.timeout) as ser:
        time.sleep(0.2)
        ser.reset_output_buffer()

        if not args.interactive_menu:
            ser.reset_input_buffer()

        enter_receiver_mode(ser, args)

        seq = 0

        cap = send_command(ser, seq, CMD_GET_CAP, b"", args.retries, args.debug)
        seq = (seq + 1) & 0xFF
        if len(cap) >= 18 and args.debug:
            flash_size, sector_size, min_offset, metadata_offset, max_payload = struct.unpack("<IIIIH", cap[:18])
            print(
                f"[debug] cap flash={flash_size} sector={sector_size} "
                f"min=0x{min_offset:06X} metadata=0x{metadata_offset:06X} max_payload={max_payload}"
            )

        info_payload = struct.pack("<IIIH", len(payload), payload_crc, args.flash_offset, 1)
        send_command(ser, seq, CMD_INFO, info_payload, args.retries, args.debug)
        seq = (seq + 1) & 0xFF

        sectors = (len(payload) + 4095) // 4096
        erase_timeout = max(args.timeout, 2.0 + sectors * 0.15)
        erase_payload = struct.pack("<II", args.flash_offset, len(payload))
        print(f"Erasing {sectors} sector(s) from 0x{args.flash_offset:06X}...")
        send_command(ser, seq, CMD_ERASE, erase_payload, args.retries, args.debug, timeout_override=erase_timeout)
        seq = (seq + 1) & 0xFF

        print("Writing payload...")
        sent = 0
        write_start = time.monotonic()
        write_stats: dict[str, int] = {}
        for offset in range(0, len(payload), args.chunk_size):
            chunk = payload[offset : offset + args.chunk_size]
            write_payload = struct.pack("<I", offset) + chunk
            send_command(ser,
                         seq,
                         CMD_WRITE,
                         write_payload,
                         args.retries,
                         args.debug,
                         timeout_override=args.write_timeout,
                         stats=write_stats)
            seq = (seq + 1) & 0xFF
            sent += len(chunk)
            print_progress(sent, len(payload), write_start, write_stats.get("retries", 0))
            if args.write_delay > 0:
                time.sleep(args.write_delay)

        print(
            "\nWrite stats: "
            f"{write_stats.get('retries', 0)} retries, "
            f"{write_stats.get('timeouts', 0)} timeout(s), "
            f"{write_stats.get('nacks', 0)} NACK(s)."
        )
        print("Verifying Flash CRC32...")
        verify_timeout = max(args.timeout, 2.0 + len(payload) / 50000.0)
        verify_payload = send_command(ser, seq, CMD_VERIFY, b"", args.retries, args.debug, timeout_override=verify_timeout)
        if len(verify_payload) != 4:
            raise ProtocolError(f"VERIFY returned invalid payload length {len(verify_payload)}")

        target_crc = struct.unpack("<I", verify_payload)[0]
        if target_crc != payload_crc:
            raise ProtocolError(f"Target CRC mismatch: got 0x{target_crc:08X}, expected 0x{payload_crc:08X}")

        print(f"Transfer complete. Flash CRC32 verified: 0x{target_crc:08X}")


def main() -> int:
    args = parse_args()
    send_weights(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
