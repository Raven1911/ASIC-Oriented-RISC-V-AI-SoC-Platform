"""
Module for capturing images from capture card/camera
"""
import cv2
import numpy as np
import threading
import time
from typing import Dict, List, Optional, Union


def parse_device(value: Union[int, str]) -> Union[int, str]:
    """Convert numeric device strings to OpenCV device indices."""
    if isinstance(value, int):
        return value

    value = str(value)
    if value.isdigit():
        return int(value)

    return value


def list_capture_devices(max_index: int = 10, width: int = 640,
                         height: int = 480) -> List[Dict[str, str]]:
    """Return readable OpenCV capture devices for GUI selection."""
    devices = []

    for device_id in range(max_index + 1):
        cap = cv2.VideoCapture(device_id)
        try:
            if not cap.isOpened():
                continue

            cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
            ret, frame = cap.read()
            if not ret or frame is None:
                continue

            actual_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            actual_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            fps = float(cap.get(cv2.CAP_PROP_FPS))
            devices.append({
                "id": str(device_id),
                "label": f"{device_id} | {actual_width}x{actual_height} | {fps:.2f} FPS",
            })
        finally:
            cap.release()

    return devices


class CaptureCardReader:
    """Handle image capture from capture card or camera"""
    
    def __init__(self, device_id: Union[int, str] = 0, width: int = 640,
                 height: int = 480, warmup_seconds: float = 0.0,
                 low_latency: bool = True):
        """
        Initialize capture card reader
        
        Args:
            device_id: Camera/capture card device ID or path
            width: Frame width
            height: Frame height
            warmup_seconds: Seconds to drain initial frames after opening
            low_latency: Continuously read in the background and keep only the newest frame
        """
        self.device_id = device_id
        self.width = width
        self.height = height
        self.warmup_seconds = warmup_seconds
        self.low_latency = low_latency
        self.cap = None
        self.is_opened = False
        self.actual_width = 0
        self.actual_height = 0
        self.actual_fps = 0.0
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._reader = None
        self._latest_frame = None
        self._latest_frame_time = 0.0
        self._read_error_reported = False
        
    def open(self) -> bool:
        """
        Open capture device
        
        Returns:
            True if successful, False otherwise
        """
        try:
            self.cap = cv2.VideoCapture(parse_device(self.device_id))
            
            if not self.cap.isOpened():
                print(f"Error: Cannot open capture device {self.device_id}")
                return False
            
            self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
            self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
            self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)

            self.actual_width = int(self.cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            self.actual_height = int(self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            self.actual_fps = float(self.cap.get(cv2.CAP_PROP_FPS))
            
            self.is_opened = True
            print(
                f"Capture device {self.device_id} opened: "
                f"{self.actual_width}x{self.actual_height}, fps={self.actual_fps:.2f}"
            )

            self._warmup()
            if self.low_latency:
                self._start_reader()
            return True
        except Exception as e:
            print(f"Error opening capture device: {e}")
            return False
    
    def read_frame(self) -> Optional[np.ndarray]:
        """
        Read a single frame from capture device
        
        Returns:
            Frame as numpy array or None if failed
        """
        if not self.is_opened or self.cap is None:
            return None

        if self.low_latency:
            return self._read_latest_frame()
        
        ret, frame = self.cap.read()
        
        if not ret:
            print("Error: Failed to read frame")
            return None
        
        return frame

    def _warmup(self):
        """Drain startup frames so capture-card auto settings can settle."""
        if self.warmup_seconds <= 0 or self.cap is None:
            return

        deadline = time.monotonic() + self.warmup_seconds
        while time.monotonic() < deadline:
            self.cap.read()
            time.sleep(0.005)

    def _start_reader(self):
        """Start a background reader that drops stale frames."""
        self._stop.clear()
        self._reader = threading.Thread(
            target=self._read_loop,
            name=f"capture-reader-{self.device_id}",
            daemon=True,
        )
        self._reader.start()

    def _read_loop(self):
        while not self._stop.is_set():
            if self.cap is None:
                break

            ret, frame = self.cap.read()
            if ret and frame is not None:
                with self._lock:
                    self._latest_frame = frame
                    self._latest_frame_time = time.monotonic()
                    self._read_error_reported = False
                continue

            if not self._read_error_reported:
                print("Error: Failed to read frame")
                self._read_error_reported = True
            time.sleep(0.005)

    def _read_latest_frame(self) -> Optional[np.ndarray]:
        """Return the newest frame captured by the background reader."""
        deadline = time.monotonic() + 0.25
        while time.monotonic() < deadline:
            with self._lock:
                frame_is_fresh = time.monotonic() - self._latest_frame_time < 1.0
                if self._latest_frame is not None and frame_is_fresh:
                    return self._latest_frame.copy()
            time.sleep(0.002)

        return None
    
    def close(self):
        """Close capture device"""
        was_opened = self.is_opened or self.cap is not None
        self._stop.set()
        if self._reader is not None:
            self._reader.join(timeout=0.5)
            self._reader = None
        if self.cap is not None:
            self.cap.release()
        self.cap = None
        self.is_opened = False
        with self._lock:
            self._latest_frame = None
            self._latest_frame_time = 0.0
        if was_opened:
            print("Capture device closed")
    
    def __enter__(self):
        """Context manager entry"""
        self.open()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.close()
