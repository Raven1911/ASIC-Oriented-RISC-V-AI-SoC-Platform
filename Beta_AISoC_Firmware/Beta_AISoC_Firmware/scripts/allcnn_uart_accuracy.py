#!/usr/bin/env python3
"""Stream CIFAR-10 images to the ALL_CNN_C accelerator firmware and measure accuracy."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import struct
import time
import zlib

import serial


SOF = 0xC5
EOF = 0x5C

CMD_INFO = 0x01
CMD_DATA = 0x02
CMD_RUN = 0x03
CMD_END = 0x04

ACK = 0x79
NACK = 0x1F
ERROR = 0xEE

DEFAULT_BAUD = 230400
DEFAULT_CHUNK_SIZE = 32
IMAGE_BYTES = 32 * 32 * 3
DEFAULT_INPUT = Path(__file__).resolve().parents[2] / "datasheet" / "input_all_preprocessed_10000.h"
DEFAULT_LABELS = Path(__file__).resolve().parents[2] / "datasheet" / "label_all_preprocessed_10000.h"


class ProtocolError(RuntimeError):
    pass


@dataclass
class ResponseFrame:
    seq: int
    status: int
    payload: bytes


@dataclass
class ImageRecord:
    image_index: int
    key_index: int
    label: int
    data: bytes


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run ALL_CNN_C accuracy test by streaming CIFAR-10 images over UART. "
            "Firmware flow: run 2.2, run 4.3, then this script sends 4.5."
        )
    )
    parser.add_argument("--port", required=True, help="Serial port, for example /dev/ttyUSB0.")
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD, help=f"UART baudrate, default {DEFAULT_BAUD}.")
    parser.add_argument(
        "--input",
        type=Path,
        default=DEFAULT_INPUT,
        help="CIFAR input header generated as nnom_input_data_* arrays.",
    )
    parser.add_argument(
        "--labels",
        type=Path,
        default=DEFAULT_LABELS,
        help="Label header containing nnom_input_labels[10000]. Uses entries 0..count-1 by default.",
    )
    parser.add_argument("--count", type=int, default=10000, help="Number of images to run, default 10000.")
    parser.add_argument("--skip", type=int, default=0, help="Skip this many images from the input file.")
    parser.add_argument(
        "--input-layout",
        choices=("hwc", "chw"),
        default="hwc",
        help="Layout in the input header. Default hwc; data is converted to CHW before sending to the accelerator.",
    )
    parser.add_argument("--chunk-size", type=int, default=DEFAULT_CHUNK_SIZE, help="DATA payload bytes per frame.")
    parser.add_argument("--timeout", type=float, default=10.0, help="UART read timeout in seconds.")
    parser.add_argument("--run-timeout", type=float, default=3.0, help="RUN response timeout per image in seconds.")
    parser.add_argument("--retries", type=int, default=5, help="Retry count for firmware NACK frames, default 5.")
    parser.add_argument("--inter-frame-delay", type=float, default=0.01, help="Optional delay after each ACKed frame.")
    parser.add_argument("--tx-slice-size", type=int, default=4, help="Write frames to UART in small slices, default 4 bytes.")
    parser.add_argument("--tx-slice-delay", type=float, default=0.001, help="Delay between UART TX slices, default 1 ms.")
    parser.add_argument("--enter-command", default="4.5", help="UART menu command that enters accuracy-stream mode.")
    parser.add_argument("--no-enter-command", action="store_true", help="Do not send the menu command first.")
    parser.add_argument("--progress-every", type=int, default=10, help="Print progress every N images.")
    parser.add_argument("--debug", action="store_true", help="Print protocol details.")
    args = parser.parse_args()

    if args.count <= 0:
        parser.error("--count must be positive")
    if args.skip < 0:
        parser.error("--skip must be >= 0")
    if args.chunk_size <= 0 or args.chunk_size > 1016 or (args.chunk_size & 1):
        parser.error("--chunk-size must be an even value in range 2..1016")
    if args.timeout <= 0 or args.run_timeout <= 0:
        parser.error("--timeout and --run-timeout must be positive")
    if args.retries < 0:
        parser.error("--retries must be >= 0")
    if args.inter_frame_delay < 0:
        parser.error("--inter-frame-delay must be >= 0")
    if args.tx_slice_size < 0:
        parser.error("--tx-slice-size must be >= 0")
    if args.tx_slice_delay < 0:
        parser.error("--tx-slice-delay must be >= 0")
    return args


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


def write_frame(ser: serial.Serial, frame: bytes) -> None:
    slice_size = getattr(send_frame, "tx_slice_size", 0)
    slice_delay = getattr(send_frame, "tx_slice_delay", 0.0)

    if slice_size <= 0 or slice_size >= len(frame):
        ser.write(frame)
        ser.flush()
        return

    for offset in range(0, len(frame), slice_size):
        ser.write(frame[offset:offset + slice_size])
        ser.flush()
        if slice_delay > 0.0 and (offset + slice_size) < len(frame):
            time.sleep(slice_delay)


def read_exact(ser: serial.Serial, count: int) -> bytes:
    data = ser.read(count)
    if len(data) != count:
        raise TimeoutError(f"Expected {count} byte(s), got {len(data)}")
    return data


def read_response(ser: serial.Serial) -> ResponseFrame:
    while True:
        sof = read_exact(ser, 1)[0]
        if sof == SOF:
            break

    header = read_exact(ser, 4)
    seq = header[0]
    status = header[1]
    length = struct.unpack("<H", header[2:4])[0]
    payload = read_exact(ser, length)
    crc_lh = read_exact(ser, 2)
    eof = read_exact(ser, 1)[0]
    expected_crc = struct.unpack("<H", crc_lh)[0]
    actual_crc = crc16(header + payload)

    if eof != EOF:
        raise ProtocolError(f"Bad EOF 0x{eof:02X}")
    if actual_crc != expected_crc:
        raise ProtocolError(f"Bad CRC16 response: got 0x{expected_crc:04X}, expected 0x{actual_crc:04X}")

    return ResponseFrame(seq=seq, status=status, payload=payload)


def read_expected_response(ser: serial.Serial, expected_seq: int, timeout: float, debug: bool) -> ResponseFrame:
    deadline = time.monotonic() + timeout
    last_mismatch: str | None = None

    while time.monotonic() < deadline:
        old_timeout = ser.timeout
        ser.timeout = max(0.001, deadline - time.monotonic())
        try:
            response = read_response(ser)
        finally:
            ser.timeout = old_timeout

        if response.seq == (expected_seq & 0xFF):
            return response

        last_mismatch = f"stale response seq=0x{response.seq:02X}, expected=0x{expected_seq & 0xFF:02X}"
        if debug:
            print(f"[frame] ignore {last_mismatch} status=0x{response.status:02X} len={len(response.payload)}")

    raise TimeoutError(last_mismatch or f"Timed out waiting for seq=0x{expected_seq & 0xFF:02X}")


def send_frame(
    ser: serial.Serial,
    seq: int,
    cmd: int,
    payload: bytes = b"",
    *,
    timeout: float,
    debug: bool,
) -> ResponseFrame:
    max_retries = getattr(send_frame, "max_retries", 0)
    delay = getattr(send_frame, "inter_frame_delay", 0.0)
    image_context = getattr(send_frame, "image_context", None)
    frame = build_request(seq, cmd, payload)
    last_error: Exception | None = None

    for attempt in range(max_retries + 1):
        write_frame(ser, frame)
        try:
            response = read_expected_response(ser, seq, timeout, debug)
        except (TimeoutError, ProtocolError) as exc:
            last_error = exc
            if debug:
                ctx = f" {image_context}" if image_context else ""
                print(
                    f"[frame]{ctx} seq={seq:02x} cmd={cmd:02x} payload={len(payload)} "
                    f"rx-error='{exc}' attempt={attempt + 1}"
                )
            if attempt < max_retries:
                time.sleep(0.005)
                continue
            raise ProtocolError(
                f"No valid response for seq=0x{seq:02X} cmd=0x{cmd:02X} "
                f"payload={len(payload)} after {max_retries + 1} attempt(s): {exc}"
            ) from exc

        if debug:
            ctx = f" {image_context}" if image_context else ""
            print(
                f"[frame]{ctx} seq={seq:02x} cmd={cmd:02x} payload={len(payload)} "
                f"status={response.status:02x} len={len(response.payload)} attempt={attempt + 1}"
            )
        if response.seq != (seq & 0xFF):
            raise ProtocolError(f"Sequence mismatch: got {response.seq}, expected {seq & 0xFF}")
        if response.status == NACK:
            last_error = ProtocolError("Firmware returned NACK")
            if attempt < max_retries:
                time.sleep(0.002)
                continue
            raise ProtocolError(f"Firmware returned NACK for seq=0x{seq:02X} cmd=0x{cmd:02X} payload={len(payload)}")
        if response.status == ERROR:
            code = response.payload[0] if response.payload else 0
            info = struct.unpack("<I", response.payload[1:5])[0] if len(response.payload) >= 5 else 0
            raise ProtocolError(f"Firmware ERROR code=0x{code:02X} info=0x{info:08X} seq=0x{seq:02X} cmd=0x{cmd:02X}")
        if response.status != ACK:
            raise ProtocolError(f"Unknown status 0x{response.status:02X}")
        if delay > 0.0:
            time.sleep(delay)
        return response

    raise ProtocolError(f"Unreachable retry state for seq=0x{seq:02X} cmd=0x{cmd:02X}: {last_error}")


def wait_for_ready(ser: serial.Serial, timeout_s: float) -> None:
    deadline = time.monotonic() + timeout_s
    collected = bytearray()
    marker = b"ACC_STREAM_READY"

    while time.monotonic() < deadline:
        chunk = ser.read(1)
        if chunk:
            collected.extend(chunk)
            print(chunk.decode("utf-8", errors="replace"), end="", flush=True)
            if marker in collected:
                print("", flush=True)
                return
        else:
            time.sleep(0.005)

    raise TimeoutError("Timed out waiting for ACC_STREAM_READY")


def load_labels(path: Path) -> list[int]:
    if not path.exists():
        raise FileNotFoundError(path)

    text = path.read_text(encoding="ascii")
    start_brace = text.find("{")
    end_brace = text.rfind("}")
    if start_brace < 0 or end_brace <= start_brace:
        raise ValueError(f"Cannot parse labels from {path}")

    labels = [int(x) for x in re.findall(r"-?\d+", text[start_brace + 1:end_brace])]
    if not labels:
        raise ValueError(f"No labels parsed from {path}")
    return labels


def iter_images(path: Path, labels: list[int], skip: int, count: int):
    if not path.exists():
        raise FileNotFoundError(path)

    if is_preprocessed_2d_input(path):
        yield from iter_preprocessed_2d_images(path, labels, skip, count)
        return

    image_re = re.compile(r"key_(\d+)_label_(\d+)\.png")
    value_re = re.compile(r"-?\d+")
    pending_index: int | None = None
    pending_label: int | None = None
    yielded = 0
    seen = 0

    with path.open("r", encoding="ascii") as f:
        for line in f:
            if line.startswith("// Image:"):
                match = image_re.search(line)
                if not match:
                    pending_index = None
                    pending_label = None
                    continue
                pending_index = int(match.group(1))
                pending_label = int(match.group(2))
                continue

            if "static const int8_t nnom_input_data_" not in line:
                continue
            if pending_index is None or pending_label is None:
                continue

            if seen < skip:
                seen += 1
                continue

            if seen >= len(labels):
                raise ValueError(f"Missing label index {seen} in label file")

            start_brace = line.find("{")
            end_brace = line.rfind("}")
            if start_brace < 0 or end_brace <= start_brace:
                raise ValueError(f"Cannot parse image array for key {pending_index:08d}")
            values = [int(x) for x in value_re.findall(line[start_brace + 1:end_brace])]
            if len(values) != IMAGE_BYTES:
                raise ValueError(f"Image {pending_index:08d} has {len(values)} values, expected {IMAGE_BYTES}")
            data = bytes((v & 0xFF) for v in values)
            label = labels[seen]
            if label != pending_label:
                print(
                    f"[warn] label mismatch at dataset index {seen}: "
                    f"label file={label}, image comment={pending_label}, key={pending_index:08d}"
                )
            yield ImageRecord(image_index=seen, key_index=pending_index, label=label, data=data)
            yielded += 1
            seen += 1
            if yielded >= count:
                return


def is_preprocessed_2d_input(path: Path) -> bool:
    with path.open("r", encoding="ascii") as f:
        for _ in range(32):
            line = f.readline()
            if not line:
                return False
            if "nnom_input_data_all" in line:
                return True
    return False


def iter_preprocessed_2d_images(path: Path, labels: list[int], skip: int, count: int):
    value_re = re.compile(r"-?\d+")
    image_index = 0
    yielded = 0
    values: list[int] = []
    in_array = False

    with path.open("r", encoding="ascii") as f:
        for line in f:
            if not in_array:
                if "nnom_input_data_all" in line:
                    in_array = True
                continue

            if image_index >= skip + count:
                return

            for token in value_re.findall(line):
                values.append(int(token))
                if len(values) == IMAGE_BYTES:
                    if image_index >= len(labels):
                        raise ValueError(f"Missing label index {image_index} in label file")

                    if image_index >= skip:
                        data = bytes((v & 0xFF) for v in values)
                        yield ImageRecord(
                            image_index=image_index,
                            key_index=image_index,
                            label=labels[image_index],
                            data=data,
                        )
                        yielded += 1
                        if yielded >= count:
                            return

                    image_index += 1
                    values = []

    if values:
        raise ValueError(f"Trailing partial image has {len(values)} values, expected {IMAGE_BYTES}")
    if yielded < count:
        raise ValueError(f"Only yielded {yielded} image(s), requested {count}")


def hwc_to_chw(data: bytes) -> bytes:
    if len(data) != IMAGE_BYTES:
        raise ValueError(f"Image has {len(data)} bytes, expected {IMAGE_BYTES}")

    out = bytearray(IMAGE_BYTES)
    dst = 0
    for c in range(3):
        for y in range(32):
            row_base = y * 32 * 3
            for x in range(32):
                out[dst] = data[row_base + x * 3 + c]
                dst += 1
    return bytes(out)


def encode_image_for_accel(data: bytes, input_layout: str) -> bytes:
    if input_layout == "hwc":
        return hwc_to_chw(data)
    if input_layout == "chw":
        if len(data) != IMAGE_BYTES:
            raise ValueError(f"Image has {len(data)} bytes, expected {IMAGE_BYTES}")
        return data
    raise ValueError(f"Unsupported input layout: {input_layout}")


def send_image(ser: serial.Serial, seq: int, image: ImageRecord, args: argparse.Namespace) -> tuple[int, int, int]:
    wire_data = encode_image_for_accel(image.data, getattr(args, "input_layout", "hwc"))
    crc32 = zlib.crc32(wire_data) & 0xFFFFFFFF
    info = struct.pack("<IBII", image.image_index, image.label, len(wire_data), crc32)
    send_frame.image_context = f"img={image.image_index:04d}"
    try:
        response = send_frame(ser, seq, CMD_INFO, info, timeout=args.timeout, debug=args.debug)
        seq = (seq + 1) & 0xFF
        if response.payload:
            raise ProtocolError("INFO ACK should not contain payload")

        for offset in range(0, len(wire_data), args.chunk_size):
            chunk = wire_data[offset:offset + args.chunk_size]
            payload = struct.pack("<I", offset) + chunk
            send_frame(ser, seq, CMD_DATA, payload, timeout=args.timeout, debug=args.debug)
            seq = (seq + 1) & 0xFF

        response = send_frame(ser, seq, CMD_RUN, b"", timeout=args.run_timeout, debug=args.debug)
        seq = (seq + 1) & 0xFF
        if len(response.payload) != 28:
            raise ProtocolError(f"RUN payload length {len(response.payload)} != 28")

        idx = struct.unpack("<I", response.payload[0:4])[0]
        label = response.payload[4]
        pred = response.payload[5]
        correct = response.payload[6]
        fw_crc = struct.unpack("<I", response.payload[8:12])[0]
        conv_lo, conv_hi = struct.unpack("<II", response.payload[12:20])
        avg_lo, avg_hi = struct.unpack("<II", response.payload[20:28])
        cycles = (conv_hi << 32) + conv_lo + (avg_hi << 32) + avg_lo

        if idx != image.image_index:
            raise ProtocolError(f"RUN index mismatch: got {idx}, expected {image.image_index}")
        if label != image.label:
            raise ProtocolError(f"RUN label mismatch: got {label}, expected {image.label}")
        if fw_crc != crc32:
            raise ProtocolError(f"RUN CRC32 mismatch: got 0x{fw_crc:08X}, expected 0x{crc32:08X}")

        return seq, pred, correct, cycles
    finally:
        send_frame.image_context = None


def main() -> None:
    args = parse_args()
    with serial.Serial(args.port, args.baud, timeout=args.timeout, write_timeout=args.timeout) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        run_accuracy_stream(ser, args)


def run_accuracy_stream(ser: serial.Serial, args: argparse.Namespace) -> None:
    total = 0
    correct = 0
    total_cycles = 0
    seq = 0
    stream_started = False
    stream_closed = False
    labels = load_labels(args.labels)
    send_frame.max_retries = getattr(args, "retries", 0)
    send_frame.inter_frame_delay = getattr(args, "inter_frame_delay", 0.0)
    send_frame.tx_slice_size = getattr(args, "tx_slice_size", 0)
    send_frame.tx_slice_delay = getattr(args, "tx_slice_delay", 0.0)
    send_frame.image_context = None

    try:
        if not args.no_enter_command:
            ser.write((args.enter_command + "\n").encode("ascii"))
            ser.flush()
            wait_for_ready(ser, args.timeout)
        stream_started = True

        start = time.monotonic()
        for image in iter_images(args.input, labels, args.skip, args.count):
            if args.progress_every > 0 and (total == 0 or ((total + 1) % args.progress_every == 0)):
                print(
                    f"[send ] idx={image.image_index:04d} key={image.key_index:08d} "
                    f"label={image.label} image={total + 1}/{args.count}",
                    flush=True,
                )
            seq, pred, is_correct, cycles = send_image(ser, seq, image, args)
            total += 1
            correct += int(is_correct)
            total_cycles += cycles

            if args.progress_every > 0 and (total == 1 or total % args.progress_every == 0):
                acc = correct * 100.0 / total
                wrong = total - correct
                print(
                    f"[{total:5d}] idx={image.image_index:04d} key={image.key_index:08d} "
                    f"label={image.label} pred={pred} right={correct} wrong={wrong} total={total} acc={acc:.2f}%"
                )

        send_frame(ser, seq, CMD_END, b"", timeout=args.timeout, debug=args.debug)
        stream_closed = True
    finally:
        if stream_started and not stream_closed:
            try:
                send_frame(ser, seq, CMD_END, b"", timeout=args.timeout, debug=False)
            except Exception:
                pass

    elapsed = time.monotonic() - start
    acc = correct * 100.0 / total if total else 0.0
    avg_cycles = total_cycles // total if total else 0
    print("")
    print("ALL_CNN_C UART accuracy result")
    print(f"  Images        : {total}")
    print(f"  Correct       : {correct}")
    print(f"  Accuracy      : {acc:.2f}%")
    print(f"  Avg cycles/img: {avg_cycles}")
    print(f"  Host time     : {elapsed:.1f} s")


if __name__ == "__main__":
    main()
