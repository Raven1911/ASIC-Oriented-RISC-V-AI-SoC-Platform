"""Small UART terminal helper used by the live golden-model dashboard."""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass
import math
import re
import threading
import time
from typing import Deque, Dict, List


RPS_LABELS = ("paper", "rock", "scissors")
RPS_PATTERN = re.compile(r"\b(paper|rock|scissors)\b", re.IGNORECASE)
SOC_RESULT_PATTERN = re.compile(
    r"\bSOC_RESULT\b.*?\blabel=(paper|rock|scissors)\b"
    r".*?\blogits=(-?\d+),(-?\d+),(-?\d+)"
    r".*?\bconv_ms=(\d+)"
    r".*?\bcpu_ms=(\d+)"
    r".*?\btotal_ms=(\d+)"
    r".*?\bwall_ms=(\d+)",
    re.IGNORECASE,
)


def list_uart_ports() -> List[Dict[str, str]]:
    """Return available serial ports for GUI selection."""
    try:
        from serial.tools import list_ports
    except Exception:
        return []

    ports = []
    for port in list_ports.comports():
        description = port.description or ""
        if description and description != "n/a":
            label = f"{port.device} | {description}"
        else:
            label = port.device
        ports.append({"port": port.device, "label": label})
    return ports


@dataclass
class UartSnapshot:
    connected: bool
    port: str
    baudrate: int
    status: str
    lines: List[str]
    current_line: str
    latest_result: str
    latest_confidence: float
    latest_time_ms: float
    latest_conv_ms: float
    latest_cpu_ms: float
    latest_wall_ms: float
    latest_logits: List[int]
    result_fps: float
    result_sequence: int


class UartConsole:
    """Line-mode UART console with a background reader thread."""

    def __init__(self, port: str, baudrate: int = 230400,
                 newline_mode: str = "lf", max_lines: int = 1000):
        self.port = port
        self.baudrate = baudrate
        self.newline_mode = newline_mode
        self.max_lines = max_lines
        self.ser = None
        self.connected = False
        self.status = "disconnected"
        self.lines: Deque[str] = deque(maxlen=max_lines)
        self.current_line = ""
        self.latest_result = ""
        self.latest_confidence = 0.0
        self.latest_time_ms = 0.0
        self.latest_conv_ms = 0.0
        self.latest_cpu_ms = 0.0
        self.latest_wall_ms = 0.0
        self.latest_logits = [0, 0, 0]
        self.result_sequence = 0
        self.result_times: Deque[float] = deque()
        self.compute_intervals: Deque[tuple[float, float]] = deque()
        self._last_result_boundary = None
        self._rx_bytes_since_result = 0
        self._tail = ""
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._reader = None

    def open(self) -> None:
        import serial

        self.ser = serial.Serial(self.port, self.baudrate, timeout=0.05, write_timeout=1.0)
        self.connected = True
        self.status = "connected"
        self._append_line(f"[connected {self.port} @ {self.baudrate}]")
        self._reader = threading.Thread(target=self._read_loop, name="uart-console", daemon=True)
        self._reader.start()

    def close(self) -> None:
        self._stop.set()
        if self._reader is not None:
            self._reader.join(timeout=0.5)
        if self.ser is not None and self.ser.is_open:
            self.ser.close()
        with self._lock:
            self.connected = False
            self.status = "disconnected"

    def send_line(self, text: str) -> None:
        if not self.connected or self.ser is None:
            self._append_line("[not connected]")
            return

        encoded = (text + self._newline()).encode()
        self.ser.write(encoded)
        self.ser.flush()
        self._append_line(f"> {text}")

    def clear(self) -> None:
        with self._lock:
            self.lines.clear()
            self.current_line = ""
            self._tail = ""

    def snapshot(self) -> UartSnapshot:
        with self._lock:
            return UartSnapshot(
                connected=self.connected,
                port=self.port,
                baudrate=self.baudrate,
                status=self.status,
                lines=list(self.lines),
                current_line=self.current_line,
                latest_result=self.latest_result,
                latest_confidence=self.latest_confidence,
                latest_time_ms=self.latest_time_ms,
                latest_conv_ms=self.latest_conv_ms,
                latest_cpu_ms=self.latest_cpu_ms,
                latest_wall_ms=self.latest_wall_ms,
                latest_logits=list(self.latest_logits),
                result_fps=self._result_fps_locked(),
                result_sequence=self.result_sequence,
            )

    def _newline(self) -> str:
        return {
            "none": "",
            "lf": "\n",
            "cr": "\r",
            "crlf": "\r\n",
        }[self.newline_mode]

    def _read_loop(self) -> None:
        while not self._stop.is_set():
            try:
                data = self.ser.read(self.ser.in_waiting or 1)
            except Exception as exc:
                with self._lock:
                    self.connected = False
                    self.status = f"read error: {exc}"
                return

            if data:
                self._consume_rx(data.decode(errors="replace"))

    def _consume_rx(self, text: str) -> None:
        with self._lock:
            self._tail = (self._tail + text)[-256:]
            for match in RPS_PATTERN.finditer(self._tail):
                self.latest_result = match.group(1).lower()

            for char in text:
                self._rx_bytes_since_result += len(char.encode(errors="replace"))
                if char == "\r":
                    self._finish_current_line()
                    continue
                if char == "\n":
                    self._finish_current_line()
                    continue
                if char == "\b":
                    self.current_line = self.current_line[:-1]
                    continue
                if char.isprintable():
                    self.current_line += char

    def _finish_current_line(self) -> None:
        line = self.current_line.strip()
        if line and self._parse_result_line_locked(line):
            self._record_result_locked()
        elif line:
            self.lines.append(line)
        self.current_line = ""

    def _append_line(self, line: str) -> None:
        with self._lock:
            self.lines.append(line)

    def _parse_result_line_locked(self, line: str) -> bool:
        structured = SOC_RESULT_PATTERN.search(line)
        if structured:
            label = structured.group(1).lower()
            logits = [int(structured.group(i)) for i in range(2, 5)]
            probs = self._softmax_percent(logits)
            self.latest_result = label
            self.latest_logits = logits
            self.latest_confidence = probs[RPS_LABELS.index(label)]
            self.latest_conv_ms = float(structured.group(5))
            self.latest_cpu_ms = float(structured.group(6))
            self.latest_time_ms = float(structured.group(7))
            self.latest_wall_ms = float(structured.group(8))
            return True

        token = line.split(maxsplit=1)[0].lower()
        if token in RPS_LABELS:
            self.latest_result = token
            self.latest_confidence = 0.0
            self.latest_time_ms = 0.0
            self.latest_conv_ms = 0.0
            self.latest_cpu_ms = 0.0
            self.latest_wall_ms = 0.0
            self.latest_logits = [0, 0, 0]
            return True

        return False

    @staticmethod
    def _softmax_percent(logits: List[int]) -> List[float]:
        max_logit = max(logits)
        exps = [math.exp(max(float(value - max_logit), -80.0)) for value in logits]
        total = sum(exps)
        if total <= 0.0:
            return [0.0 for _ in logits]
        return [(value / total) * 100.0 for value in exps]

    def _record_result_locked(self) -> None:
        now = time.monotonic()
        if self._last_result_boundary is not None:
            observed_interval = now - self._last_result_boundary
            uart_bytes = self._rx_bytes_since_result
            uart_seconds = (uart_bytes * 10) / self.baudrate  # UART 8N1.
            compute_interval = max(observed_interval - uart_seconds, 1e-6)
            self.compute_intervals.append((now, compute_interval))
        self.result_times.append(now)
        self.result_sequence += 1
        self._last_result_boundary = now
        self._rx_bytes_since_result = 0
        self._prune_result_times_locked(now)

    def _result_fps_locked(self) -> float:
        now = time.monotonic()
        self._prune_result_times_locked(now)
        if not self.compute_intervals:
            return 0.0
        total_compute_time = sum(interval for _, interval in self.compute_intervals)
        return len(self.compute_intervals) / total_compute_time if total_compute_time > 0 else 0.0

    def _prune_result_times_locked(self, now: float) -> None:
        cutoff = now - 5.0
        while self.result_times and self.result_times[0] < cutoff:
            self.result_times.popleft()
        while self.compute_intervals and self.compute_intervals[0][0] < cutoff:
            self.compute_intervals.popleft()
