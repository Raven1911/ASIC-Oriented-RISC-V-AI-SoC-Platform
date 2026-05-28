"""
Module for GUI display of results
"""
import cv2
import numpy as np
from typing import List, Dict


class ResultDisplay:
    """Handle display of model results on frame"""
    
    def __init__(self, font=cv2.FONT_HERSHEY_SIMPLEX, font_scale: float = 0.7, 
                 thickness: int = 2, color: tuple = (0, 255, 0)):
        """
        Initialize display settings
        
        Args:
            font: OpenCV font type
            font_scale: Font scale
            thickness: Text thickness
            color: Text color (BGR)
        """
        self.font = font
        self.font_scale = font_scale
        self.thickness = thickness
        self.color = color
        self.background_color = (0, 0, 0)
        self.text_color = (255, 255, 255)
        self.window_name = "Golden Model + SoC UART"
        self.window_ready = False
    
    def draw_results(self, frame: np.ndarray, results: List[Dict], 
                    display_area: str = 'top_left') -> np.ndarray:
        """
        Draw model results on frame
        
        Args:
            frame: Input frame
            results: List of formatted result dictionaries
            display_area: Where to display ('top_left', 'top_right', 'bottom_left', 'bottom_right')
            
        Returns:
            Frame with drawn results
        """
        frame_copy = frame.copy()
        
        # Calculate position based on display_area
        start_x, start_y = self._get_display_position(frame_copy.shape, display_area)
        
        # Draw semi-transparent background
        background_height = len(results) * 30 + 20
        overlay = frame_copy.copy()
        cv2.rectangle(overlay, 
                     (start_x - 10, start_y - 10),
                     (start_x + 300, start_y + background_height),
                     self.background_color, -1)
        frame_copy = cv2.addWeighted(overlay, 0.7, frame_copy, 0.3, 0)
        
        # Draw results
        y_offset = start_y
        for result in results:
            text = f"{result['rank']}. {result['label']}: {result['percentage']:.2f}%"
            cv2.putText(frame_copy, text, (start_x, y_offset), 
                       self.font, self.font_scale, self.text_color, self.thickness)
            y_offset += 30
        
        return frame_copy
    
    def _get_display_position(self, frame_shape: tuple, display_area: str) -> tuple:
        """
        Get display position based on area
        
        Args:
            frame_shape: Shape of frame (height, width, channels)
            display_area: Display area name
            
        Returns:
            (x, y) position tuple
        """
        height, width = frame_shape[:2]
        margin = 20
        
        positions = {
            'top_left': (margin, margin + 20),
            'top_right': (width - 350, margin + 20),
            'bottom_left': (margin, height - 180),
            'bottom_right': (width - 350, height - 180),
            'center': (width // 2 - 150, height // 2 - 75)
        }
        
        return positions.get(display_area, positions['top_left'])
    
    def draw_processing_info(self, frame: np.ndarray, fps: float = None,
                            processing_time: float = None) -> np.ndarray:
        """
        Draw processing information on frame
        
        Args:
            frame: Input frame
            fps: Frames per second
            processing_time: Processing time in milliseconds
            
        Returns:
            Frame with info drawn
        """
        frame_copy = frame.copy()
        
        info_texts = []
        if fps is not None:
            info_texts.append(f"FPS: {fps:.1f}")
        if processing_time is not None:
            info_texts.append(f"Time: {processing_time:.1f}ms")
        
        y_offset = 30
        for text in info_texts:
            cv2.putText(frame_copy, text, (10, y_offset),
                       self.font, self.font_scale, self.color, self.thickness)
            y_offset += 30
        
        return frame_copy

    def compose_dashboard(self, frame: np.ndarray, results: List[Dict],
                          processing_time: float, uart_state,
                          command_text: str, canvas_width: int = 1920,
                          canvas_height: int = 1080) -> np.ndarray:
        """Build a side-by-side software/UART dashboard."""
        panel_width = max(520, canvas_width // 3)
        left_width = canvas_width - panel_width
        canvas = np.full((canvas_height, left_width + panel_width, 3), (18, 21, 24), dtype=np.uint8)

        annotated = self.draw_processing_info(frame, processing_time=processing_time)
        fitted = self._fit_frame(annotated, left_width, canvas_height)
        y = (canvas_height - fitted.shape[0]) // 2
        x = (left_width - fitted.shape[1]) // 2
        canvas[y:y + fitted.shape[0], x:x + fitted.shape[1]] = fitted

        panel_x = left_width
        cv2.rectangle(canvas, (panel_x, 0), (left_width + panel_width, canvas_height), (28, 33, 38), -1)
        cv2.line(canvas, (panel_x, 0), (panel_x, canvas_height), (78, 87, 96), 1)

        software_label = results[0]["label"] if results else "-"
        software_pct = f"{results[0]['percentage']:.2f}%" if results else "-"
        soc_label = uart_state.latest_result if uart_state and uart_state.latest_result else "-"
        uart_status = uart_state.status if uart_state else "disabled"

        margin = 28
        header_y = 58
        value_y = 108
        detail_y = 144
        split_x = panel_x + panel_width // 2
        terminal_top = 188
        terminal_bottom = canvas_height - 88
        input_top = canvas_height - 68
        input_bottom = canvas_height - 20

        self._put_text(canvas, "Software", panel_x + margin, header_y, 0.95, (107, 214, 255), 2)
        self._put_text(canvas, software_label, panel_x + margin, value_y, 1.4, (255, 255, 255), 2)
        self._put_text(canvas, software_pct, panel_x + margin, detail_y, 0.82, (180, 190, 198), 1)

        self._put_text(canvas, "SoC UART", split_x + margin, header_y, 0.95, (136, 232, 156), 2)
        self._put_text(canvas, soc_label, split_x + margin, value_y, 1.4, (255, 255, 255), 2)
        self._put_text(canvas, uart_status, split_x + margin, detail_y, 0.72, (180, 190, 198), 1)

        cv2.rectangle(canvas, (panel_x + 20, terminal_top),
                      (left_width + panel_width - 20, terminal_bottom), (12, 15, 18), -1)
        self._put_text(canvas, "Terminal", panel_x + 36, terminal_top + 38, 0.82, (255, 255, 255), 2)

        terminal_lines = []
        if uart_state:
            terminal_lines.extend(uart_state.lines)
            if uart_state.current_line:
                terminal_lines.append(uart_state.current_line)
        else:
            terminal_lines.append("UART disabled. Pass --uart-port to connect.")

        wrapped_lines = []
        for line in terminal_lines:
            wrapped_lines.extend(self._wrap_line(line, 54))
        line_height = 29
        max_lines = max((terminal_bottom - terminal_top - 70) // line_height, 1)
        visible_lines = wrapped_lines[-max_lines:]

        line_y = terminal_top + 78
        for line in visible_lines:
            self._put_text(canvas, line, panel_x + 36, line_y, 0.66, (220, 224, 228), 1)
            line_y += line_height

        cv2.rectangle(canvas, (panel_x + 20, input_top),
                      (left_width + panel_width - 20, input_bottom), (8, 10, 12), -1)
        self._put_text(canvas, "> " + command_text + "_", panel_x + 36,
                       input_top + 32, 0.72, (255, 255, 255), 1)
        return canvas

    def show_frame(self, frame: np.ndarray, initial_width: int = 1440,
                   initial_height: int = 900, fullscreen: bool = False) -> int:
        """Display one frame in a resizable window and return the pressed key."""
        if not self.window_ready:
            cv2.namedWindow(self.window_name, cv2.WINDOW_NORMAL)
            cv2.resizeWindow(self.window_name, initial_width, initial_height)
            if fullscreen:
                cv2.setWindowProperty(self.window_name, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)
            self.window_ready = True

        cv2.imshow(self.window_name, frame)
        return cv2.waitKeyEx(1)

    @staticmethod
    def _fit_frame(frame: np.ndarray, max_width: int, max_height: int) -> np.ndarray:
        height, width = frame.shape[:2]
        scale = min(max_width / width, max_height / height)
        if scale == 1.0:
            return frame
        return cv2.resize(frame, (int(width * scale), int(height * scale)))

    @staticmethod
    def _wrap_line(text: str, width: int) -> List[str]:
        if not text:
            return [""]
        return [text[i:i + width] for i in range(0, len(text), width)]

    @staticmethod
    def _put_text(frame: np.ndarray, text: str, x: int, y: int,
                  scale: float, color: tuple, thickness: int):
        cv2.putText(frame, text, (x, y), cv2.FONT_HERSHEY_SIMPLEX,
                    scale, color, thickness, cv2.LINE_AA)
    
    @staticmethod
    def display_frame(frame: np.ndarray, window_name: str = 'Golden Model',
                     resize: bool = False, max_width: int = 1280,
                     max_height: int = 720) -> bool:
        """
        Display frame in window
        
        Args:
            frame: Frame to display
            window_name: Window title
            resize: Whether to resize frame for display
            max_width: Maximum display width
            max_height: Maximum display height
            
        Returns:
            False if user pressed 'q' to quit
        """
        display_frame = frame.copy()
        
        # Resize if needed
        if resize:
            height, width = frame.shape[:2]
            if width > max_width or height > max_height:
                scale = min(max_width / width, max_height / height)
                new_width = int(width * scale)
                new_height = int(height * scale)
                display_frame = cv2.resize(frame, (new_width, new_height))
        
        cv2.imshow(window_name, display_frame)
        
        # Wait for key press (1ms timeout)
        key = cv2.waitKey(1) & 0xFF
        
        # Return False if 'q' pressed to quit
        if key == ord('q'):
            return False
        
        return True


class PerformanceMonitor:
    """Monitor and track performance metrics"""
    
    def __init__(self, window_size: int = 30):
        """
        Initialize performance monitor
        
        Args:
            window_size: Number of frames to average
        """
        self.window_size = window_size
        self.fps_history = []
        self.processing_time_history = []
    
    def update(self, fps: float, processing_time: float):
        """Update metrics"""
        self.fps_history.append(fps)
        self.processing_time_history.append(processing_time)
        
        if len(self.fps_history) > self.window_size:
            self.fps_history.pop(0)
        if len(self.processing_time_history) > self.window_size:
            self.processing_time_history.pop(0)
    
    def get_average_fps(self) -> float:
        """Get average FPS"""
        return np.mean(self.fps_history) if self.fps_history else 0
    
    def get_average_processing_time(self) -> float:
        """Get average processing time"""
        return np.mean(self.processing_time_history) if self.processing_time_history else 0
