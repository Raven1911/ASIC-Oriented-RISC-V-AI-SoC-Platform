"""Background firmware build/flash runner used by the Qt dashboard."""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from pathlib import Path
import os
import signal
import subprocess
import sys
import threading
import time
from typing import Deque, List, Optional


BUILD_TARGETS = ("app", "bootloader", "both", "test_unit")


@dataclass
class FirmwareBuildSnapshot:
    running: bool
    status: str
    operation: str
    returncode: Optional[int]
    lines: List[str]


class FirmwareBuildRunner:
    """Run Beta_AISoC firmware build/flash tools without blocking the GUI."""

    def __init__(self, firmware_dir: str = "", builder_script: str = "",
                 flasher_script: str = "", default_flash_file: str = "",
                 max_lines: int = 500):
        repo_root = Path(__file__).resolve().parents[2]
        self.firmware_dir = self._resolve_dir(firmware_dir, repo_root)
        self.builder_script = self._resolve_builder(builder_script)
        self.flasher_script = self._resolve_flasher(flasher_script)
        self.default_flash_file = self._resolve_file(default_flash_file, "Build/main.bin")
        self.max_lines = max_lines
        self.lines: Deque[str] = deque(maxlen=max_lines)
        self.running = False
        self.status = "ready"
        self.operation = ""
        self.returncode = None
        self._process = None
        self._reader = None
        self._started_at = 0.0
        self._lock = threading.Lock()

    def start(self, target: str = "app", max_flash_kb: int = 64):
        """Start a firmware build subprocess."""
        target = str(target).strip()
        if target not in BUILD_TARGETS:
            return False, f"unknown target: {target}"

        try:
            max_flash_kb = int(max_flash_kb)
        except (TypeError, ValueError):
            return False, "invalid max flash size"
        if max_flash_kb <= 0:
            return False, "max flash size must be positive"

        command = [
            sys.executable,
            "-u",
            str(self.builder_script),
            "--target",
            target,
            "--max-flash-kb",
            str(max_flash_kb),
        ]
        return self._start_process(command, "build", f"building {target}...")

    def start_flash(self, port: str, image_path: str = ""):
        """Start host_flasher.py for the selected UART port."""
        port = str(port).strip()
        if not port:
            return False, "select a UART port first"

        image = self._resolve_file(image_path, str(self.default_flash_file))
        if not image.exists():
            return False, f"firmware image not found: {image}"

        command = [
            sys.executable,
            "-u",
            str(self.flasher_script),
            port,
            str(image),
        ]
        return self._start_process(command, "flash", f"flashing {image.name} on {port}...")

    def stop(self):
        """Ask the running firmware subprocess to stop."""
        with self._lock:
            process = self._process
            if not self.running or process is None or process.poll() is not None:
                return False, "no firmware task running"
            operation = self.operation or "task"
            self.status = f"stopping {operation}..."
            self.lines.append(f"[{operation}] stop requested")

        try:
            self._terminate_process(process)
        except Exception as exc:
            with self._lock:
                self.status = f"stop failed: {exc}"
                self.lines.append(f"[{operation}] stop failed: {exc}")
            return False, self.status

        return True, f"stopping {operation}..."

    def clear(self) -> None:
        with self._lock:
            self.lines.clear()

    def close(self) -> None:
        process = None
        with self._lock:
            if self._process is not None and self._process.poll() is None:
                process = self._process
                operation = self.operation or "task"
                self.status = f"stopping {operation}..."

        if process is not None:
            self._terminate_process(process)
            try:
                process.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                self._kill_process(process)
                process.wait(timeout=1.0)

        reader = self._reader
        if reader is not None:
            reader.join(timeout=0.5)

    def snapshot(self) -> FirmwareBuildSnapshot:
        with self._lock:
            return FirmwareBuildSnapshot(
                running=self.running,
                status=self.status,
                operation=self.operation,
                returncode=self.returncode,
                lines=list(self.lines),
            )

    @staticmethod
    def _resolve_dir(firmware_dir: str, repo_root: Path) -> Path:
        if firmware_dir:
            path = Path(firmware_dir).expanduser()
            if not path.is_absolute():
                path = repo_root / path
            return path.resolve()
        return (repo_root / "Beta_AISoC_Firmware").resolve()

    def _resolve_builder(self, builder_script: str) -> Path:
        if builder_script:
            path = Path(builder_script).expanduser()
            if not path.is_absolute():
                path = self.firmware_dir / path
            return path.resolve()
        return (self.firmware_dir / "scripts" / "builder.py").resolve()

    def _resolve_flasher(self, flasher_script: str) -> Path:
        if flasher_script:
            path = Path(flasher_script).expanduser()
            if not path.is_absolute():
                path = self.firmware_dir / path
            return path.resolve()
        return (self.firmware_dir / "scripts" / "host_flasher.py").resolve()

    def _resolve_file(self, file_path: str, default_path: str) -> Path:
        value = str(file_path or "").strip() or default_path
        path = Path(value).expanduser()
        if not path.is_absolute():
            path = self.firmware_dir / path
        return path.resolve()

    def _start_process(self, command: List[str], operation: str, status: str):
        with self._lock:
            if self.running:
                return False, f"{self.operation or 'firmware task'} already running"

            if not self.firmware_dir.exists():
                return False, f"firmware dir not found: {self.firmware_dir}"
            if operation == "build" and not self.builder_script.exists():
                return False, f"builder.py not found: {self.builder_script}"
            if operation == "flash" and not self.flasher_script.exists():
                return False, f"host_flasher.py not found: {self.flasher_script}"

            self.lines.clear()
            self.lines.append(f"[{operation}] cwd: {self.firmware_dir}")
            self.lines.append(f"[{operation}] command: {' '.join(command)}")
            self.status = status
            self.operation = operation
            self.returncode = None
            self._started_at = time.monotonic()

            try:
                self._process = subprocess.Popen(
                    command,
                    cwd=str(self.firmware_dir),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=0,
                    start_new_session=True,
                )
            except Exception as exc:
                self._process = None
                self.status = f"{operation} failed to start: {exc}"
                self.lines.append(f"[{operation}] failed to start: {exc}")
                return False, self.status

            self.running = True
            self._reader = threading.Thread(
                target=self._read_loop,
                args=(self._process, operation),
                name=f"firmware-{operation}",
                daemon=True,
            )
            self._reader.start()

        return True, status

    @staticmethod
    def _terminate_process(process: subprocess.Popen) -> None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except Exception:
            process.terminate()

    @staticmethod
    def _kill_process(process: subprocess.Popen) -> None:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except Exception:
            process.kill()

    def _read_loop(self, process: subprocess.Popen, operation: str) -> None:
        try:
            if process.stdout is not None:
                self._consume_stream(process.stdout)
            returncode = process.wait()
        except Exception as exc:
            self._append_line(f"[{operation}] reader error: {exc}")
            returncode = process.poll()

        elapsed = time.monotonic() - self._started_at
        with self._lock:
            if self._process is process:
                self.running = False
                self.returncode = returncode
                self._process = None
                if returncode == 0:
                    self.status = f"{operation} completed in {elapsed:.1f}s"
                elif returncode is not None and returncode < 0:
                    self.status = f"{operation} stopped after {elapsed:.1f}s"
                else:
                    self.status = f"{operation} failed ({returncode}) after {elapsed:.1f}s"
                self.lines.append(f"[{operation}] {self.status}")

    def _consume_stream(self, stream) -> None:
        buffer = ""
        while True:
            char = stream.read(1)
            if char == "":
                break
            if char == "\r":
                if buffer:
                    self._replace_last_line(buffer)
                    buffer = ""
                continue
            if char == "\n":
                if buffer:
                    self._append_line(buffer)
                    buffer = ""
                continue
            buffer += char

        if buffer:
            self._append_line(buffer)

    def _append_line(self, line: str) -> None:
        with self._lock:
            self.lines.append(line)

    def _replace_last_line(self, line: str) -> None:
        with self._lock:
            if self.lines and "%" in self.lines[-1] and "%" in line:
                self.lines[-1] = line
            else:
                self.lines.append(line)
