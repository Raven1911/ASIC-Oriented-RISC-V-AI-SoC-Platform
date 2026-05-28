#!/usr/bin/env python3

import os
import subprocess
import glob
import argparse
import struct
import tempfile

"""Firmware build helper for app, bootloader, and unit-test images.

Main responsibilities:
- Select sources/linker per target.
- Build ELF/BIN/HEX artifacts with RISC-V toolchain.
- Generate .mem and disassembly files used by simulation/debug flows.
"""

TOOLCHAIN_PREFIX = "riscv32-unknown-elf-"
CC = f"{TOOLCHAIN_PREFIX}gcc"
OBJCOPY = f"{TOOLCHAIN_PREFIX}objcopy"
OBJDUMP = f"{TOOLCHAIN_PREFIX}objdump"
NM = f"{TOOLCHAIN_PREFIX}nm"
DEFAULT_MAX_FLASH_KB = 64

BOOT_IMAGE_MAGIC = 0x31494142  # "BAI1" in little-endian byte order.
BOOT_IMAGE_VERSION = 1
BOOT_SEG_LOAD_IMEM = 1
BOOT_SEG_LOAD_DMEM = 2
BOOT_SEG_ZERO_DMEM = 3
BOOT_IMAGE_HEADER_SIZE = 24
BOOT_IMAGE_SEGMENT_SIZE = 20


def parse_args():
    # Keep CLI minimal and explicit to reduce mistakes in CI/manual builds.
    parser = argparse.ArgumentParser(description="Build firmware images for app/bootloader/test_unit.")
    parser.add_argument(
        "--target",
        choices=["app", "bootloader", "test_unit", "both"],
        default="app",
        help="Build target selection: app, bootloader, test_unit, or both for app and bootloader (default: app).",
    )
    parser.add_argument(
        "--max-flash-kb",
        type=int,
        default=DEFAULT_MAX_FLASH_KB,
        help="Maximum flash size in KB for generated .mem file (default: 64).",
    )
    args = parser.parse_args()

    if args.max_flash_kb <= 0:
        parser.error("--max-flash-kb must be a positive integer.")

    return args


def reverse_bin_words(bin_path):
    # Hardware image format expects byte order reversed per 32-bit word.
    with open(bin_path, "rb") as f:
        data = f.read()

    reversed_data = bytearray()
    for i in range(0, len(data), 4):
        word = data[i:i + 4]
        if len(word) == 4:
            reversed_data.extend(word[::-1])
        else:
            reversed_data.extend(word)

    with open(bin_path, "wb") as f:
        f.write(reversed_data)


def write_mem_file(bin_path, mem_path, max_flash_size_bytes):
    # Export fixed-size memory image (16B/line) padded with 0xFF.
    with open(bin_path, "rb") as f:
        bin_data = f.read()

    with open(mem_path, "w") as f:
        f.write("/* Contents of Memory Array starting from address 0.  This is a standard Verilog readmemh format. */\n")
        for i in range(0, max_flash_size_bytes, 16):
            chunk = bin_data[i:i + 16]
            hex_bytes = [f"{b:02x}" for b in chunk]
            hex_bytes += ["ff"] * (16 - len(hex_bytes))
            f.write(" ".join(hex_bytes) + "\n")


def align_up(value, alignment):
    return (value + alignment - 1) & ~(alignment - 1)


def read_symbols(elf_path):
    output = subprocess.check_output([NM, "-n", elf_path], text=True)
    symbols = {}
    for line in output.splitlines():
        parts = line.split()
        if len(parts) >= 3:
            symbols[parts[2]] = int(parts[0], 16)
    return symbols


def objcopy_section(elf_path, section_name, output_dir):
    fd, output_path = tempfile.mkstemp(prefix="section_", suffix=".bin", dir=output_dir)
    os.close(fd)

    try:
        subprocess.run([OBJCOPY, "-O", "binary", "-j", section_name, elf_path, output_path], check=True)
        with open(output_path, "rb") as f:
            return f.read()
    finally:
        if os.path.exists(output_path):
            os.remove(output_path)


def append_padded(payload, data):
    payload.extend(data)
    while len(payload) % 4 != 0:
        payload.append(0)


def build_boot_image(output_elf, output_bin, output_base):
    symbols = read_symbols(output_elf)
    output_dir = os.path.dirname(output_base) or "."

    text_data = objcopy_section(output_elf, ".text", output_dir)
    data_data = objcopy_section(output_elf, ".data", output_dir)

    entry_addr = symbols.get("_vectors", 0x01100000)
    text_addr = symbols.get("_vectors", entry_addr)
    data_addr = symbols.get("_sdata", 0)
    bss_addr = symbols.get("_sbss", 0)
    bss_size = symbols.get("_ebss", bss_addr) - bss_addr

    segments = []
    if text_data:
        segments.append({
            "kind": BOOT_SEG_LOAD_IMEM,
            "dst": text_addr,
            "data": text_data,
            "size": len(text_data),
        })
    if data_data:
        segments.append({
            "kind": BOOT_SEG_LOAD_DMEM,
            "dst": data_addr,
            "data": data_data,
            "size": len(data_data),
        })
    if bss_size > 0:
        segments.append({
            "kind": BOOT_SEG_ZERO_DMEM,
            "dst": bss_addr,
            "data": b"",
            "size": bss_size,
        })

    descriptor_end = BOOT_IMAGE_HEADER_SIZE + (len(segments) * BOOT_IMAGE_SEGMENT_SIZE)
    payload_offset = align_up(descriptor_end, 4)
    next_payload_offset = payload_offset
    payload = bytearray()

    for segment in segments:
        if segment["kind"] == BOOT_SEG_ZERO_DMEM:
            segment["flash_offset"] = 0
            continue

        segment["flash_offset"] = next_payload_offset
        before = len(payload)
        append_padded(payload, segment["data"])
        next_payload_offset += len(payload) - before

    image = bytearray()
    image.extend(struct.pack(
        "<IIIIII",
        BOOT_IMAGE_MAGIC,
        BOOT_IMAGE_VERSION,
        payload_offset,
        len(segments),
        entry_addr,
        0,
    ))

    for segment in segments:
        image.extend(struct.pack(
            "<IIIII",
            segment["kind"],
            0,
            segment["flash_offset"],
            segment["dst"],
            segment["size"],
        ))

    while len(image) < payload_offset:
        image.append(0)
    image.extend(payload)

    with open(output_bin, "wb") as f:
        f.write(image)

    print(
        "Boot image generated (app): "
        f"{len(image)} bytes, {len(segments)} segment(s), entry=0x{entry_addr:08X}"
    )


def build_target(target, max_flash_size_bytes):
    # Common HAL includes/drivers reused across non-boot targets.
    common_include_dirs = ["-IDrivers/SoC_HAL/Inc", "-IDrivers/CMSIS/Include"]
    all_driver_sources = glob.glob("Drivers/SoC_HAL/Src/**/*.c", recursive=True) + glob.glob("Drivers/SoC_HAL/Src/**/*.cpp", recursive=True)
    extra_flags = []

    if target == "app":
        # Application build uses full app sources + shared drivers.
        include_dirs = ["-IApp/Inc"] + common_include_dirs
        app_sources = glob.glob("App/Src/**/*.c", recursive=True) + glob.glob("App/Src/**/*.cpp", recursive=True)
        app_excluded_sources = {
            "App/Src/conv1_test.c",
            "App/Src/conv1_test_vectors.c",
            "App/Src/tinyalexnet_mnist.c",
        }
        app_sources = [src for src in app_sources if src not in app_excluded_sources]
        sources = app_sources + all_driver_sources + ["Core/Startup/startup.s"]
        linker_script = "Core/Linker/linker.ld"
        output_base = "Build/main"
        output_mem = "Build/W25Q128JVxIM.mem"
        output_disasm = "Build/main_disasm.s"
        extra_flags = [
            "-O3",
            "-ffreestanding",
            "-fno-builtin",
            "-ffunction-sections",
            "-fdata-sections",
            "-Wl,--gc-sections",
        ]
    elif target == "bootloader":
        # Bootloader build uses dedicated startup/linker and minimal required drivers.
        include_dirs = ["-IDrivers/Bootloader"] + common_include_dirs
        boot_sources = glob.glob("Drivers/Bootloader/**/*.c", recursive=True) + glob.glob("Drivers/Bootloader/**/*.cpp", recursive=True)
        boot_required_driver_sources = [
            "Drivers/SoC_HAL/Src/SPI_Driver.c",
            "Drivers/SoC_HAL/Src/mem.c",
            "Drivers/SoC_HAL/Src/timer.c",
            "Drivers/SoC_HAL/Src/UART_Driver.c",
        ]
        # Use startup and linker dedicated for bootloader build.
        sources = boot_sources + boot_required_driver_sources + ["Drivers/Bootloader/startup.S"]
        linker_script = "Drivers/Bootloader/linker.ld"
        output_base = "Build/bootloader"
        output_mem = "Build/bootloader.mem"
        output_disasm = "Build/bootloader_disasm.s"
        # Keep bootloader as small as possible.
        # extra_flags = ["-Os", "-ffunction-sections", "-fdata-sections", "-Wl,--gc-sections"]
    elif target == "test_unit":
        # Unit test image reuses app linker/startup with test entry sources.
        include_dirs = ["-Itesting/unit", "-IApp/Inc"] + common_include_dirs
        unit_sources = glob.glob("testing/unit/**/*.c", recursive=True) + glob.glob("testing/unit/**/*.cpp", recursive=True)
        sources = unit_sources + all_driver_sources + ["Core/Startup/startup.s"]
        linker_script = "Core/Linker/linker.ld"
        output_base = "Build/unit/unit_tester"
        output_mem = "Build/unit/unit_tester.mem"
        output_disasm = "Build/unit/unit_tester_disasm.s"
    else:
        raise ValueError(f"Unsupported target: {target}")

    output_elf = f"{output_base}.elf"
    output_bin = f"{output_base}.bin"
    output_hex = f"{output_base}.hex"

    os.makedirs("Build", exist_ok=True)
    output_dir = os.path.dirname(output_base)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    flags = ["-march=rv32im", "-mabi=ilp32", "-nostdlib", "-nostartfiles", f"-T{linker_script}"] + extra_flags
    cmd_cc = [CC] + flags + include_dirs + sources + ["-o", output_elf]

    print(f"Running ({target}): {' '.join(cmd_cc)}")
    subprocess.run(cmd_cc, check=True)

    subprocess.run([OBJCOPY, "-O", "binary", output_elf, output_bin], check=True)

    if target == "app":
        build_boot_image(output_elf, output_bin, output_base)
    else:
        reverse_bin_words(output_bin)
        print(f"Bytes reversed successfully ({target}).")

    # App boot images are stored as raw bytes. Legacy memory-init images keep
    # the old word-swapped textual format.
    with open(output_hex, "w") as hex_file:
        xxd_cmd = ["xxd", "-c", "4", "-g", "4", "-p", output_bin]
        if target != "app":
            xxd_cmd = ["xxd", "-e", "-c", "4", "-g", "4", "-p", output_bin]
        subprocess.run(xxd_cmd, stdout=hex_file, check=True)

    write_mem_file(output_bin, output_mem, max_flash_size_bytes)

    with open(output_disasm, "w") as disasm_file:
        subprocess.run([OBJDUMP, "-d", output_elf], stdout=disasm_file, check=True)

    print(f"Build completed ({target}). HEX: {output_hex}")


def build():
    # Dispatch requested target(s) while sharing flash-size limit setting.
    args = parse_args()
    max_flash_size_bytes = args.max_flash_kb * 1024

    if args.target in ("app", "both"):
        build_target("app", max_flash_size_bytes)

    if args.target in ("bootloader", "both"):
        build_target("bootloader", max_flash_size_bytes)

    if args.target == "test_unit":
        build_target("test_unit", max_flash_size_bytes)

    print("All requested targets built successfully.")

if __name__ == "__main__":
    build()
