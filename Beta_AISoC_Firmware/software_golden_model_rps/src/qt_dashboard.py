"""Qt dashboard for side-by-side software and SoC UART display."""
from __future__ import annotations

from typing import Callable, List, Sequence
import os

import cv2
import numpy as np
from PyQt5 import QtCore, QtGui, QtWidgets


APP_NAME = "BK-AISoC Golden Model"
APP_DESKTOP_ID = "bk-aisoc-golden-model"
APP_ICON_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "assets", "hcmut_cropped.png")
)


def make_app_icon() -> QtGui.QIcon:
    """Build the BK app icon used by the window and desktop taskbar."""
    icon = QtGui.QIcon()
    if os.path.exists(APP_ICON_PATH):
        icon.addFile(APP_ICON_PATH)
    return icon


def configure_qt_app(app: QtWidgets.QApplication) -> None:
    """Apply app metadata and icon consistently for taskbar/window managers."""
    app.setApplicationName(APP_NAME)
    app.setApplicationDisplayName(APP_NAME)
    app.setOrganizationName("HCMUT")
    if hasattr(app, "setDesktopFileName"):
        app.setDesktopFileName(APP_DESKTOP_ID)

    icon = make_app_icon()
    if not icon.isNull():
        app.setWindowIcon(icon)


class VideoLabel(QtWidgets.QLabel):
    """QLabel that keeps video aspect ratio while the window resizes."""

    def __init__(self):
        super().__init__()
        self.setAlignment(QtCore.Qt.AlignCenter)
        self.setSizePolicy(QtWidgets.QSizePolicy.Expanding, QtWidgets.QSizePolicy.Expanding)
        self.setStyleSheet("background: #eef2f5;")
        self._source_pixmap = None
        self.setText("No video")

    def set_frame(self, frame: np.ndarray) -> None:
        self.setText("")
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        height, width = rgb.shape[:2]
        image = QtGui.QImage(
            rgb.data,
            width,
            height,
            width * 3,
            QtGui.QImage.Format_RGB888,
        ).copy()
        self._source_pixmap = QtGui.QPixmap.fromImage(image)
        self._refresh_pixmap()

    def set_status(self, message: str) -> None:
        self._source_pixmap = None
        self.clear()
        self.setText(message)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._refresh_pixmap()

    def _refresh_pixmap(self) -> None:
        if self._source_pixmap is None:
            return
        self.setPixmap(
            self._source_pixmap.scaled(
                self.size(),
                QtCore.Qt.KeepAspectRatio,
                QtCore.Qt.SmoothTransformation,
            )
        )


class DashboardWindow(QtWidgets.QMainWindow):
    """Native Qt window with a video view and a real UART terminal input."""

    def __init__(self, on_command: Callable[[str], None],
                 on_model_select: Callable[[str], object],
                 on_capture_connect: Callable[[str], object],
                 on_capture_disconnect: Callable[[], object],
                 on_capture_refresh: Callable[[], Sequence[dict]],
                 on_uart_connect: Callable[[str, int], object],
                 on_uart_disconnect: Callable[[], object],
                 on_uart_refresh: Callable[[], Sequence[dict]],
                 on_terminal_clear: Callable[[], None],
                 on_firmware_build: Callable[[str, int], object],
                 on_firmware_flash: Callable[[str, str], object],
                 on_firmware_stop: Callable[[], object],
                 on_firmware_clear: Callable[[], None],
                 model_options: Sequence[dict],
                 capture_devices: Sequence[dict],
                 uart_ports: Sequence[dict],
                 initial_model: str,
                 initial_capture_device: str,
                 initial_uart_port: str,
                 initial_uart_baud: int,
                 initial_firmware_target: str,
                 initial_firmware_max_flash_kb: int,
                 initial_firmware_flash_file: str,
                 window_width: int, window_height: int,
                 fullscreen: bool = False):
        super().__init__()
        self.on_command = on_command
        self.on_model_select = on_model_select
        self.on_capture_connect = on_capture_connect
        self.on_capture_disconnect = on_capture_disconnect
        self.on_capture_refresh = on_capture_refresh
        self.on_uart_connect = on_uart_connect
        self.on_uart_disconnect = on_uart_disconnect
        self.on_uart_refresh = on_uart_refresh
        self.on_terminal_clear = on_terminal_clear
        self.on_firmware_build = on_firmware_build
        self.on_firmware_flash = on_firmware_flash
        self.on_firmware_stop = on_firmware_stop
        self.on_firmware_clear = on_firmware_clear
        self.closed = False
        self._capture_connected = False
        self._uart_connected = False
        self._build_running = False
        self._firmware_operation = ""
        self._terminal_expanded = False
        self._last_terminal_text = None
        self._last_build_log_text = None
        self.initial_firmware_target = initial_firmware_target
        self.initial_firmware_max_flash_kb = initial_firmware_max_flash_kb
        self.initial_firmware_flash_file = initial_firmware_flash_file
        self.setWindowTitle("Host Computer + BK-AISoC")
        app_icon = make_app_icon()
        if not app_icon.isNull():
            self.setWindowIcon(app_icon)
        self.resize(window_width, window_height)

        root = QtWidgets.QWidget()
        self.setCentralWidget(root)
        layout = QtWidgets.QHBoxLayout(root)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        self.video_area = QtWidgets.QWidget()
        self.video_area.setObjectName("videoArea")
        video_area_layout = QtWidgets.QVBoxLayout(self.video_area)
        video_area_layout.setContentsMargins(18, 18, 18, 18)
        video_area_layout.setSpacing(0)

        video_frame = QtWidgets.QFrame()
        video_frame.setObjectName("videoFrame")
        video_frame_layout = QtWidgets.QVBoxLayout(video_frame)
        video_frame_layout.setContentsMargins(8, 8, 8, 8)
        video_frame_layout.setSpacing(8)

        video_header = QtWidgets.QWidget()
        video_header.setObjectName("videoHeader")
        video_header.setFixedHeight(52)
        video_header_layout = QtWidgets.QHBoxLayout(video_header)
        video_header_layout.setContentsMargins(2, 0, 2, 0)
        video_header_layout.setSpacing(10)

        self.video_logo = QtWidgets.QLabel()
        self.video_logo.setObjectName("videoLogo")
        self.video_logo.setFixedSize(44, 44)
        logo_pixmap = QtGui.QPixmap(APP_ICON_PATH)
        if not logo_pixmap.isNull():
            self.video_logo.setPixmap(
                logo_pixmap.scaled(
                    self.video_logo.size(),
                    QtCore.Qt.KeepAspectRatio,
                    QtCore.Qt.SmoothTransformation,
                )
            )
        else:
            self.video_logo.hide()
        video_header_layout.addWidget(self.video_logo)

        self.video_info = QtWidgets.QLabel("Stream -- x --")
        self.video_info.setObjectName("videoInfo")
        video_header_layout.addWidget(self.video_info)
        video_header_layout.addStretch(1)
        video_frame_layout.addWidget(video_header, 0)

        self.video = VideoLabel()
        video_frame_layout.addWidget(self.video, 1)
        video_frame_layout.setStretch(0, 0)
        video_frame_layout.setStretch(1, 1)
        video_area_layout.addWidget(video_frame)
        layout.addWidget(self.video_area, 3)

        panel = QtWidgets.QWidget()
        panel.setObjectName("panel")
        panel_layout = QtWidgets.QVBoxLayout(panel)
        panel_layout.setContentsMargins(22, 18, 22, 18)
        panel_layout.setSpacing(12)
        layout.addWidget(panel, 2)

        self.setup_container = QtWidgets.QWidget()
        setup_layout = QtWidgets.QVBoxLayout(self.setup_container)
        setup_layout.setContentsMargins(0, 0, 0, 0)
        setup_layout.setSpacing(12)
        self._build_connection_controls(setup_layout)
        panel_layout.addWidget(self.setup_container)
        self.set_model_options(model_options, initial_model)
        self.set_model_status("loading model", False)
        self.set_capture_devices(capture_devices, initial_capture_device)
        self.set_uart_ports(uart_ports, initial_uart_port)
        self.set_uart_baudrates(initial_uart_baud)
        self.set_capture_status("not connected", False)
        self.set_uart_status("not connected", False)

        self.result_container = QtWidgets.QWidget()
        result_row = QtWidgets.QHBoxLayout(self.result_container)
        result_row.setContentsMargins(0, 0, 0, 0)
        result_row.setSpacing(14)
        panel_layout.addWidget(self.result_container)

        software_box, self.software_title, self.software_value, self.software_detail, self.software_extra = self._make_result_block(
            "Host Computer", "#0b4dbb", "#315f8f"
        )
        soc_box, self.soc_title, self.soc_value, self.soc_detail, self.soc_extra = self._make_result_block(
            "BK-AISoC", "#0f84ad", "#2c6f7d"
        )
        result_row.addWidget(software_box, 1)
        result_row.addWidget(soc_box, 1)

        self.terminal_tabs = QtWidgets.QTabWidget()
        self.terminal_tabs.setObjectName("terminalTabs")

        self.uart_tab = QtWidgets.QWidget()
        uart_tab_layout = QtWidgets.QVBoxLayout(self.uart_tab)
        uart_tab_layout.setContentsMargins(0, 10, 0, 0)
        uart_tab_layout.setSpacing(8)

        self.terminal_header_widget = QtWidgets.QWidget()
        terminal_header = QtWidgets.QHBoxLayout(self.terminal_header_widget)
        terminal_header.setContentsMargins(0, 0, 0, 0)
        terminal_header.setSpacing(8)
        terminal_title = QtWidgets.QLabel("UART Terminal")
        terminal_title.setObjectName("sectionTitle")
        self.terminal_clear_button = self._make_button("Clear")
        self.terminal_zoom_button = self._make_button("Maximize")
        self.terminal_clear_button.clicked.connect(self._clear_terminal)
        self.terminal_zoom_button.clicked.connect(self._toggle_terminal_expanded)
        terminal_header.addWidget(terminal_title)
        terminal_header.addStretch(1)
        terminal_header.addWidget(self.terminal_clear_button)
        terminal_header.addWidget(self.terminal_zoom_button)
        uart_tab_layout.addWidget(self.terminal_header_widget)

        self.terminal = QtWidgets.QPlainTextEdit()
        self.terminal.setReadOnly(True)
        self.terminal.setLineWrapMode(QtWidgets.QPlainTextEdit.NoWrap)
        self.terminal.setVerticalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOn)
        self.terminal.setObjectName("terminal")
        terminal_font = QtGui.QFontDatabase.systemFont(QtGui.QFontDatabase.FixedFont)
        terminal_font.setPointSize(13)
        self.terminal.setFont(terminal_font)
        uart_tab_layout.addWidget(self.terminal, 1)

        self.command_input = QtWidgets.QLineEdit()
        self.command_input.setObjectName("commandInput")
        self.command_input.setPlaceholderText("Type SoC command and press Enter")
        self.command_input.setEnabled(False)
        self.command_input.returnPressed.connect(self._send_command)
        uart_tab_layout.addWidget(self.command_input)
        self.terminal_tabs.addTab(self.uart_tab, "UART")

        self.build_tab = QtWidgets.QWidget()
        build_tab_layout = QtWidgets.QVBoxLayout(self.build_tab)
        build_tab_layout.setContentsMargins(0, 10, 0, 0)
        build_tab_layout.setSpacing(8)
        self._build_firmware_tab(build_tab_layout)
        self.terminal_tabs.addTab(self.build_tab, "Firmware")
        panel_layout.addWidget(self.terminal_tabs, 1)

        QtWidgets.QShortcut(QtGui.QKeySequence(QtCore.Qt.Key_F11), self, activated=self._toggle_fullscreen)
        QtWidgets.QShortcut(QtGui.QKeySequence(QtCore.Qt.Key_Escape), self, activated=self._leave_fullscreen)

        self.setStyleSheet(
            """
            QWidget {
                background: #eef2f5;
                color: #203040;
                font-family: "DejaVu Sans";
                font-size: 16px;
            }
            QWidget#panel {
                background: #ffffff;
                border-left: 1px solid #d6e0e8;
            }
            QWidget#videoArea {
                background: #eef2f5;
            }
            QFrame#videoFrame {
                background: #ffffff;
                border: 1px solid #d6e0e8;
                border-radius: 8px;
            }
            QWidget#videoHeader {
                background: transparent;
            }
            QLabel#videoLogo {
                background: transparent;
            }
            QLabel#videoInfo {
                color: #536575;
                font-size: 17px;
                font-weight: 600;
                padding-left: 4px;
            }
            QLabel#resultTitle {
                font-size: 23px;
                font-weight: 600;
            }
            QLabel#resultValue {
                font-size: 36px;
                font-weight: 600;
            }
            QLabel#resultDetail {
                color: #536575;
                font-size: 18px;
                font-weight: 500;
            }
            QLabel#sectionTitle {
                font-size: 20px;
                font-weight: 600;
                margin-top: 8px;
            }
            QLabel#connectionTitle {
                color: #203040;
                font-size: 18px;
                font-weight: 600;
            }
            QLabel#fieldLabel {
                color: #536575;
                font-size: 14px;
                font-weight: 600;
            }
            QLabel#inlineFieldLabel {
                color: #536575;
                font-size: 14px;
                font-weight: 600;
                background: transparent;
            }
            QLabel#statusLabel {
                color: #536575;
                font-size: 14px;
                font-weight: 500;
            }
            QComboBox#deviceCombo {
                background: #ffffff;
                border: 1px solid #d6e0e8;
                color: #203040;
                min-height: 34px;
                padding: 4px 8px;
            }
            QComboBox#deviceCombo:focus {
                border: 2px solid #0b4dbb;
                padding: 3px 7px;
            }
            QSpinBox#flashSpin {
                background: #ffffff;
                border: 1px solid #d6e0e8;
                color: #203040;
                min-height: 34px;
                padding: 4px 6px;
            }
            QSpinBox#flashSpin:focus {
                border: 2px solid #0b4dbb;
                padding: 3px 5px;
            }
            QPushButton#smallButton {
                background: #eef2f5;
                border: 1px solid #c7d3dd;
                color: #203040;
                min-height: 34px;
                padding: 4px 10px;
            }
            QPushButton#smallButton:hover {
                background: #e2eaf1;
            }
            QPushButton#connectButton {
                background: #0b4dbb;
                border: 1px solid #0b4dbb;
                color: #ffffff;
                font-weight: 600;
                min-height: 34px;
                padding: 4px 12px;
            }
            QPushButton#connectButton:hover {
                background: #0f5bd6;
            }
            QTabWidget#terminalTabs::pane {
                background: transparent;
                border: 0;
            }
            QTabBar::tab {
                background: #eef2f5;
                border: 1px solid #d6e0e8;
                color: #536575;
                font-weight: 600;
                min-height: 32px;
                min-width: 88px;
                padding: 4px 12px;
            }
            QTabBar::tab:selected {
                background: #ffffff;
                color: #203040;
                border-bottom-color: #ffffff;
            }
            QPlainTextEdit#terminal,
            QPlainTextEdit#buildLog {
                background: #f8fafc;
                border: 1px solid #d6e0e8;
                color: #203040;
                selection-background-color: #0f84ad;
                selection-color: #ffffff;
                padding: 10px;
            }
            QLineEdit#commandInput,
            QLineEdit#flashImageInput {
                background: #ffffff;
                border: 1px solid #d6e0e8;
                color: #203040;
                font-family: "DejaVu Sans Mono";
                font-size: 17px;
                padding: 10px;
            }
            QLineEdit#commandInput:focus,
            QLineEdit#flashImageInput:focus {
                border: 2px solid #0b4dbb;
                padding: 9px;
            }
            QScrollBar:vertical {
                background: #e7edf2;
                width: 14px;
                margin: 0;
            }
            QScrollBar::handle:vertical {
                background: #0f84ad;
                min-height: 28px;
                border-radius: 4px;
            }
            QScrollBar::handle:vertical:hover {
                background: #0b4dbb;
            }
            QScrollBar::add-line:vertical,
            QScrollBar::sub-line:vertical {
                height: 0;
            }
            """
        )

        if fullscreen:
            self.showFullScreen()
        else:
            self.show()
        self.command_input.setFocus()

    def update_view(self, frame: np.ndarray, results: List[dict],
                    processing_time_ms: float, host_fps: float,
                    uart_state) -> None:
        self.video.set_frame(frame)
        frame_height, frame_width = frame.shape[:2]
        self.video_info.setText(f"Stream {frame_width} x {frame_height}")
        if results:
            self.software_value.setText(results[0]["label"])
            self._set_elided_text(
                self.software_detail,
                f"{results[0]['percentage']:.2f}% | {processing_time_ms:.1f} ms",
            )
            self._set_elided_text(self.software_extra, f"{host_fps:.1f} FPS")
        else:
            self.software_value.setText("-")
            self._set_elided_text(
                self.software_detail,
                f"{processing_time_ms:.1f} ms",
            )
            self._set_elided_text(self.software_extra, f"{host_fps:.1f} FPS")

        self.soc_value.setText(uart_state.latest_result or "-")
        self._set_elided_text(self.soc_detail, self._soc_primary_detail_text(uart_state))
        self._set_elided_text(self.soc_extra, self._soc_extra_detail_text(uart_state))
        if uart_state.connected:
            self.set_uart_status(f"{uart_state.port} @ {uart_state.baudrate}", True)
        else:
            self.set_uart_status(uart_state.status, False)

        self._update_terminal(uart_state)

    def set_idle_view(self, message: str, uart_state) -> None:
        self.video.set_status(message)
        self.video_info.setText("Stream -- x --")
        self.software_value.setText("-")
        self._set_elided_text(self.software_detail, "waiting for capture")
        self._set_elided_text(self.software_extra, "FPS --")
        self.soc_value.setText(uart_state.latest_result or "-")
        self._set_elided_text(self.soc_detail, self._soc_primary_detail_text(uart_state))
        self._set_elided_text(self.soc_extra, self._soc_extra_detail_text(uart_state))
        if uart_state.connected:
            self.set_uart_status(f"{uart_state.port} @ {uart_state.baudrate}", True)
        else:
            self.set_uart_status(uart_state.status, False)
        self._update_terminal(uart_state)

    def closeEvent(self, event):
        self.closed = True
        super().closeEvent(event)

    def keyPressEvent(self, event):
        if event.key() == QtCore.Qt.Key_Escape:
            self._leave_fullscreen()
            return
        if event.key() == QtCore.Qt.Key_F11:
            self._toggle_fullscreen()
            return
        super().keyPressEvent(event)

    def _make_result_block(self, title: str, color: str, detail_color: str):
        box = QtWidgets.QWidget()
        box.setMinimumWidth(0)
        box.setSizePolicy(QtWidgets.QSizePolicy.Expanding, QtWidgets.QSizePolicy.Fixed)
        layout = QtWidgets.QVBoxLayout(box)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(4)

        title_label = QtWidgets.QLabel(title)
        title_label.setObjectName("resultTitle")
        title_label.setStyleSheet(f"color: {color};")
        value_label = QtWidgets.QLabel("-")
        value_label.setObjectName("resultValue")
        detail_label = QtWidgets.QLabel("-")
        detail_label.setObjectName("resultDetail")
        extra_label = QtWidgets.QLabel("-")
        extra_label.setObjectName("resultDetail")
        extra_label.setStyleSheet(f"color: {detail_color}; font-weight: 600;")
        for label in (title_label, value_label, detail_label, extra_label):
            label.setMinimumWidth(0)
            label.setWordWrap(False)
            label.setSizePolicy(QtWidgets.QSizePolicy.Ignored, QtWidgets.QSizePolicy.Fixed)
        layout.addWidget(title_label)
        layout.addWidget(value_label)
        layout.addWidget(detail_label)
        layout.addWidget(extra_label)
        return box, title_label, value_label, detail_label, extra_label

    def _set_elided_text(self, label: QtWidgets.QLabel, text: str) -> None:
        label.setToolTip(text)
        available_width = max(label.width() - 2, 40)
        label.setText(label.fontMetrics().elidedText(text, QtCore.Qt.ElideRight, available_width))

    def _soc_primary_detail_text(self, uart_state) -> str:
        if not getattr(uart_state, "latest_result", ""):
            return uart_state.status

        confidence = getattr(uart_state, "latest_confidence", 0.0)
        time_ms = getattr(uart_state, "latest_time_ms", 0.0)
        confidence_text = f"{confidence:.2f}%" if confidence > 0.0 else "score --"
        time_text = f"{time_ms:.1f} ms" if time_ms > 0.0 else "time --"
        return f"{confidence_text} | {time_text}"

    def _soc_extra_detail_text(self, uart_state) -> str:
        return f"{uart_state.result_fps:.1f} FPS" if uart_state.result_fps > 0 else "FPS --"

    def _update_terminal(self, uart_state) -> None:
        lines = list(uart_state.lines)
        if uart_state.current_line:
            lines.append(uart_state.current_line)
        terminal_text = "\n".join(lines)
        if terminal_text == self._last_terminal_text:
            return

        scroll_bar = self.terminal.verticalScrollBar()
        was_at_bottom = scroll_bar.value() >= max(scroll_bar.maximum() - 2, 0)
        old_value = scroll_bar.value()
        self.terminal.setPlainText(terminal_text)
        if was_at_bottom:
            cursor = self.terminal.textCursor()
            cursor.movePosition(QtGui.QTextCursor.End)
            self.terminal.setTextCursor(cursor)
            self.terminal.ensureCursorVisible()
        else:
            scroll_bar.setValue(old_value)
        self._last_terminal_text = terminal_text

    def update_build_log(self, lines: Sequence[str]) -> None:
        build_text = "\n".join(lines)
        if build_text == self._last_build_log_text:
            return

        scroll_bar = self.build_log.verticalScrollBar()
        was_at_bottom = scroll_bar.value() >= max(scroll_bar.maximum() - 2, 0)
        old_value = scroll_bar.value()
        self.build_log.setPlainText(build_text)
        if was_at_bottom:
            cursor = self.build_log.textCursor()
            cursor.movePosition(QtGui.QTextCursor.End)
            self.build_log.setTextCursor(cursor)
            self.build_log.ensureCursorVisible()
        else:
            scroll_bar.setValue(old_value)
        self._last_build_log_text = build_text

    def _build_connection_controls(self, parent_layout) -> None:
        title = QtWidgets.QLabel("Setup")
        title.setObjectName("connectionTitle")
        parent_layout.addWidget(title)

        self.model_combo = self._make_combo()
        self.model_combo.setEditable(False)
        self.model_combo.setMinimumContentsLength(28)
        self.model_combo.setMaxVisibleItems(8)
        self.model_load_button = self._make_button("Load", primary=True)
        self.model_status = self._make_status_label()
        self.model_load_button.clicked.connect(self._load_model)
        self._add_model_row(parent_layout)

        self.capture_combo = self._make_combo()
        self.capture_refresh_button = self._make_button("Refresh")
        self.capture_connect_button = self._make_button("Connect", primary=True)
        self.capture_status = self._make_status_label()
        self.capture_refresh_button.clicked.connect(self._refresh_capture_devices)
        self.capture_connect_button.clicked.connect(self._connect_capture)
        self._add_connection_row(
            parent_layout,
            "Video Capture",
            self.capture_combo,
            self.capture_refresh_button,
            self.capture_connect_button,
            self.capture_status,
        )

        self.uart_combo = self._make_combo()
        self.uart_baud_combo = self._make_combo()
        self.uart_baud_combo.setMinimumContentsLength(6)
        self.uart_baud_combo.setFixedWidth(112)
        self.uart_baud_combo.setToolTip("UART baudrate")
        self.uart_baud_label = QtWidgets.QLabel("Baud")
        self.uart_baud_label.setObjectName("inlineFieldLabel")
        self.uart_refresh_button = self._make_button("Refresh")
        self.uart_connect_button = self._make_button("Connect", primary=True)
        self.uart_status = self._make_status_label()
        self.uart_refresh_button.clicked.connect(self._refresh_uart_ports)
        self.uart_connect_button.clicked.connect(self._connect_uart)
        self._add_uart_row(parent_layout)

    def _build_firmware_tab(self, parent_layout) -> None:
        header = QtWidgets.QWidget()
        header_layout = QtWidgets.QHBoxLayout(header)
        header_layout.setContentsMargins(0, 0, 0, 0)
        header_layout.setSpacing(8)

        title = QtWidgets.QLabel("Firmware Build")
        title.setObjectName("sectionTitle")
        self.build_clear_button = self._make_button("Clear")
        self.build_zoom_button = self._make_button("Maximize")
        self.build_clear_button.clicked.connect(self._clear_build_log)
        self.build_zoom_button.clicked.connect(self._toggle_terminal_expanded)
        header_layout.addWidget(title)
        header_layout.addStretch(1)
        header_layout.addWidget(self.build_clear_button)
        header_layout.addWidget(self.build_zoom_button)
        parent_layout.addWidget(header)

        self.build_target_combo = self._make_combo()
        self.build_target_combo.setEditable(False)
        self.build_target_combo.setMinimumContentsLength(10)
        self.build_flash_spin = QtWidgets.QSpinBox()
        self.build_flash_spin.setObjectName("flashSpin")
        self.build_flash_spin.setRange(1, 4096)
        self.build_flash_spin.setValue(max(int(self.initial_firmware_max_flash_kb), 1))
        self.build_flash_spin.setSuffix(" KB")
        self.build_flash_spin.setFixedWidth(116)
        self.build_button = self._make_button("Build", primary=True)
        self.build_status = self._make_status_label()
        self.build_button.clicked.connect(self._build_firmware)
        self._add_firmware_build_row(parent_layout)

        self.flash_image_edit = QtWidgets.QLineEdit()
        self.flash_image_edit.setObjectName("flashImageInput")
        self.flash_image_edit.setText(self.initial_firmware_flash_file)
        self.flash_button = self._make_button("Flash", primary=True)
        self.flash_button.clicked.connect(self._flash_firmware)
        self._add_firmware_flash_row(parent_layout)

        self.build_log = QtWidgets.QPlainTextEdit()
        self.build_log.setReadOnly(True)
        self.build_log.setLineWrapMode(QtWidgets.QPlainTextEdit.NoWrap)
        self.build_log.setVerticalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOn)
        self.build_log.setObjectName("buildLog")
        build_font = QtGui.QFontDatabase.systemFont(QtGui.QFontDatabase.FixedFont)
        build_font.setPointSize(13)
        self.build_log.setFont(build_font)
        parent_layout.addWidget(self.build_log, 1)
        self.set_build_status("ready", False, False)

    def _add_model_row(self, parent_layout) -> None:
        label = QtWidgets.QLabel("Golden Model")
        label.setObjectName("fieldLabel")
        parent_layout.addWidget(label)

        row = QtWidgets.QHBoxLayout()
        row.setSpacing(8)
        row.addWidget(self.model_combo, 1)
        row.addWidget(self.model_load_button)
        parent_layout.addLayout(row)
        parent_layout.addWidget(self.model_status)

    def _add_connection_row(self, parent_layout, label_text: str, combo,
                            refresh_button, connect_button, status_label) -> None:
        label = QtWidgets.QLabel(label_text)
        label.setObjectName("fieldLabel")
        parent_layout.addWidget(label)

        row = QtWidgets.QHBoxLayout()
        row.setSpacing(8)
        row.addWidget(combo, 1)
        row.addWidget(refresh_button)
        row.addWidget(connect_button)
        parent_layout.addLayout(row)
        parent_layout.addWidget(status_label)

    def _add_uart_row(self, parent_layout) -> None:
        label = QtWidgets.QLabel("UART")
        label.setObjectName("fieldLabel")
        parent_layout.addWidget(label)

        row = QtWidgets.QHBoxLayout()
        row.setSpacing(8)
        row.addWidget(self.uart_combo, 1)
        row.addWidget(self.uart_baud_label)
        row.addWidget(self.uart_baud_combo)
        row.addWidget(self.uart_refresh_button)
        row.addWidget(self.uart_connect_button)
        parent_layout.addLayout(row)
        parent_layout.addWidget(self.uart_status)

    def _add_firmware_build_row(self, parent_layout) -> None:
        label = QtWidgets.QLabel("Build Target")
        label.setObjectName("fieldLabel")
        parent_layout.addWidget(label)

        for target, title in (
            ("app", "App"),
            ("bootloader", "Bootloader"),
            ("both", "App + Bootloader"),
            ("test_unit", "Unit Test"),
        ):
            self.build_target_combo.addItem(title, target)

        index = self.build_target_combo.findData(self.initial_firmware_target)
        if index >= 0:
            self.build_target_combo.setCurrentIndex(index)

        row = QtWidgets.QHBoxLayout()
        row.setSpacing(8)
        row.addWidget(self.build_target_combo, 1)
        row.addWidget(self.build_flash_spin)
        row.addWidget(self.build_button)
        parent_layout.addLayout(row)
        parent_layout.addWidget(self.build_status)

    def _add_firmware_flash_row(self, parent_layout) -> None:
        label = QtWidgets.QLabel("Flash Image")
        label.setObjectName("fieldLabel")
        parent_layout.addWidget(label)

        row = QtWidgets.QHBoxLayout()
        row.setSpacing(8)
        row.addWidget(self.flash_image_edit, 1)
        row.addWidget(self.flash_button)
        parent_layout.addLayout(row)

    def _make_combo(self) -> QtWidgets.QComboBox:
        combo = QtWidgets.QComboBox()
        combo.setObjectName("deviceCombo")
        combo.setEditable(True)
        combo.setInsertPolicy(QtWidgets.QComboBox.NoInsert)
        combo.setSizeAdjustPolicy(QtWidgets.QComboBox.AdjustToMinimumContentsLengthWithIcon)
        return combo

    def _make_button(self, text: str, primary: bool = False) -> QtWidgets.QPushButton:
        button = QtWidgets.QPushButton(text)
        button.setObjectName("connectButton" if primary else "smallButton")
        return button

    def _make_status_label(self) -> QtWidgets.QLabel:
        label = QtWidgets.QLabel()
        label.setObjectName("statusLabel")
        return label

    def set_capture_devices(self, devices: Sequence[dict], selected_device: str = "") -> None:
        self._set_combo_items(self.capture_combo, devices, "id", "label", selected_device)

    def set_model_options(self, models: Sequence[dict], selected_model: str = "") -> None:
        self._set_combo_items(self.model_combo, models, "id", "label", selected_model)
        self._set_combo_popup_height(self.model_combo, min_rows=4)

    def set_uart_ports(self, ports: Sequence[dict], selected_port: str = "") -> None:
        self._set_combo_items(self.uart_combo, ports, "port", "label", selected_port)

    def set_uart_baudrates(self, selected_baudrate: int) -> None:
        options = [9600, 57600, 115200, 230400, 460800, 921600]
        if selected_baudrate not in options:
            options.insert(0, selected_baudrate)

        self.uart_baud_combo.blockSignals(True)
        self.uart_baud_combo.clear()
        for baudrate in options:
            self.uart_baud_combo.addItem(str(baudrate), str(baudrate))
        index = self.uart_baud_combo.findData(str(selected_baudrate))
        if index >= 0:
            self.uart_baud_combo.setCurrentIndex(index)
        self.uart_baud_combo.blockSignals(False)

    def set_capture_status(self, message: str, connected: bool) -> None:
        self._capture_connected = connected
        self.capture_status.setText(message)
        self.capture_status.setStyleSheet(
            "color: #0f7a3b;" if connected else "color: #9a5b00;"
        )
        self.capture_connect_button.setText("Disconnect" if connected else "Connect")

    def set_model_status(self, message: str, loaded: bool) -> None:
        self.model_status.setText(message)
        self.model_status.setStyleSheet(
            "color: #0f7a3b;" if loaded else "color: #9a5b00;"
        )
        self.model_load_button.setText("Reload" if loaded else "Load")

    def set_uart_status(self, message: str, connected: bool) -> None:
        self._uart_connected = connected
        self.uart_status.setText(message)
        self.uart_status.setStyleSheet(
            "color: #0f7a3b;" if connected else "color: #9a5b00;"
        )
        self.uart_connect_button.setText("Disconnect" if connected else "Connect")
        if hasattr(self, "command_input"):
            self.command_input.setEnabled(connected)

    def set_build_status(self, message: str, success: bool = False,
                         running: bool = False, operation: str = "") -> None:
        self._build_running = running
        self._firmware_operation = operation if running else ""
        self.build_status.setText(message)
        if running:
            color = "#0b4dbb"
        elif success:
            color = "#0f7a3b"
        else:
            color = "#9a5b00"
        self.build_status.setStyleSheet(f"color: {color};")
        build_running = running and operation == "build"
        flash_running = running and operation == "flash"
        self.build_button.setText("Stop" if build_running else "Build")
        self.flash_button.setText("Stop" if flash_running else "Flash")
        self.build_button.setEnabled(not running or build_running)
        self.flash_button.setEnabled(not running or flash_running)
        self.build_target_combo.setEnabled(not running)
        self.build_flash_spin.setEnabled(not running)
        self.flash_image_edit.setEnabled(not running)

    def _set_combo_items(self, combo: QtWidgets.QComboBox, items: Sequence[dict],
                         value_key: str, label_key: str, selected_value: str) -> None:
        selected_value = str(selected_value or "")
        if not selected_value:
            selected_value = self._combo_value(combo)

        combo.blockSignals(True)
        combo.clear()
        seen = set()
        for item in items:
            value = str(item.get(value_key, "")).strip()
            if not value or value in seen:
                continue
            combo.addItem(str(item.get(label_key, value)), value)
            seen.add(value)

        if selected_value and selected_value not in seen:
            combo.insertItem(0, selected_value, selected_value)
            seen.add(selected_value)

        index = combo.findData(selected_value)
        if index >= 0:
            combo.setCurrentIndex(index)
        elif combo.count() > 0:
            combo.setCurrentIndex(0)
        combo.blockSignals(False)

    def _combo_value(self, combo: QtWidgets.QComboBox) -> str:
        data = combo.currentData()
        if data is not None and str(data).strip():
            return str(data).strip()
        return combo.currentText().split("|", 1)[0].strip()

    def _set_combo_popup_height(self, combo: QtWidgets.QComboBox,
                                min_rows: int = 4) -> None:
        """Keep short combo popups usable on Linux/Qt style themes."""
        row_height = max(combo.fontMetrics().height() + 14, 36)
        visible_rows = max(min_rows, min(combo.count(), combo.maxVisibleItems()))
        view = combo.view()
        view.setMinimumHeight(row_height * visible_rows)
        view.setMinimumWidth(max(combo.width(), combo.sizeHint().width()))
        view.setVerticalScrollBarPolicy(QtCore.Qt.ScrollBarAsNeeded)

    def _load_model(self) -> None:
        model = self._combo_value(self.model_combo)
        if not model:
            self.set_model_status("select a model", False)
            return

        self.model_load_button.setEnabled(False)
        QtWidgets.QApplication.setOverrideCursor(QtCore.Qt.WaitCursor)
        try:
            ok, message = self.on_model_select(model)
            self.set_model_status(message, ok)
        except Exception as exc:
            self.set_model_status(f"load failed: {exc}", False)
        finally:
            QtWidgets.QApplication.restoreOverrideCursor()
            self.model_load_button.setEnabled(True)

    def _refresh_capture_devices(self) -> None:
        self.capture_refresh_button.setEnabled(False)
        QtWidgets.QApplication.setOverrideCursor(QtCore.Qt.WaitCursor)
        try:
            selected = self._combo_value(self.capture_combo)
            devices = self.on_capture_refresh()
            self.set_capture_devices(devices, selected)
            self.set_capture_status(f"found {len(devices)} capture device(s)", self._capture_connected)
        except Exception as exc:
            self.set_capture_status(f"refresh failed: {exc}", False)
        finally:
            QtWidgets.QApplication.restoreOverrideCursor()
            self.capture_refresh_button.setEnabled(True)

    def _refresh_uart_ports(self) -> None:
        selected = self._combo_value(self.uart_combo)
        try:
            ports = self.on_uart_refresh()
            self.set_uart_ports(ports, selected)
            self.set_uart_status(f"found {len(ports)} UART port(s)", self._uart_connected)
        except Exception as exc:
            self.set_uart_status(f"refresh failed: {exc}", False)

    def _connect_capture(self) -> None:
        if self._capture_connected:
            try:
                ok, message = self.on_capture_disconnect()
                self.set_capture_status(message, ok)
            except Exception as exc:
                self.set_capture_status(f"disconnect failed: {exc}", True)
            return

        device = self._combo_value(self.capture_combo)
        if not device:
            self.set_capture_status("enter a capture device", False)
            return

        try:
            ok, message = self.on_capture_connect(device)
            self.set_capture_status(message, ok)
        except Exception as exc:
            self.set_capture_status(f"connect failed: {exc}", False)

    def _connect_uart(self) -> None:
        if self._uart_connected:
            try:
                ok, message = self.on_uart_disconnect()
                self.set_uart_status(message, ok)
            except Exception as exc:
                self.set_uart_status(f"disconnect failed: {exc}", True)
            return

        port = self._combo_value(self.uart_combo)
        if not port:
            self.set_uart_status("enter a UART port", False)
            return

        try:
            baudrate = int(self._combo_value(self.uart_baud_combo))
        except ValueError:
            self.set_uart_status("invalid baudrate", False)
            return

        try:
            ok, message = self.on_uart_connect(port, baudrate)
            self.set_uart_status(message, ok)
        except Exception as exc:
            self.set_uart_status(f"connect failed: {exc}", False)

    def _build_firmware(self) -> None:
        if self._build_running:
            if self._firmware_operation != "build":
                return
            try:
                ok, message = self.on_firmware_stop()
                self.set_build_status(message, False, ok, "build" if ok else "")
            except Exception as exc:
                self.set_build_status(f"stop failed: {exc}", False, True, "build")
            return

        target = self._combo_value(self.build_target_combo)
        if not target:
            self.set_build_status("select a target", False, False)
            return

        self.build_button.setEnabled(False)
        try:
            ok, message = self.on_firmware_build(target, self.build_flash_spin.value())
            self.set_build_status(message, False, ok, "build" if ok else "")
        except Exception as exc:
            self.set_build_status(f"build failed: {exc}", False, False)
        finally:
            self.build_button.setEnabled(not self._build_running or self._firmware_operation == "build")

    def _flash_firmware(self) -> None:
        if self._build_running:
            if self._firmware_operation != "flash":
                return
            try:
                ok, message = self.on_firmware_stop()
                self.set_build_status(message, False, ok, "flash" if ok else "")
            except Exception as exc:
                self.set_build_status(f"stop failed: {exc}", False, True, "flash")
            return

        port = self._combo_value(self.uart_combo)
        if not port:
            self.set_build_status("select a UART port first", False, False)
            return

        image_path = self.flash_image_edit.text().strip()
        self.flash_button.setEnabled(False)
        try:
            ok, message = self.on_firmware_flash(port, image_path)
            self.set_build_status(message, False, ok, "flash" if ok else "")
        except Exception as exc:
            self.set_build_status(f"flash failed: {exc}", False, False)
        finally:
            self.flash_button.setEnabled(not self._build_running or self._firmware_operation == "flash")

    def _send_command(self) -> None:
        text = self.command_input.text()
        if not text:
            return
        self.on_command(text)
        self.command_input.clear()

    def _clear_terminal(self) -> None:
        try:
            self.on_terminal_clear()
        except Exception as exc:
            self.set_uart_status(f"clear failed: {exc}", False)
            return
        self._last_terminal_text = ""
        self.terminal.clear()

    def _clear_build_log(self) -> None:
        try:
            self.on_firmware_clear()
        except Exception as exc:
            self.set_build_status(f"clear failed: {exc}", False, self._build_running)
            return
        self._last_build_log_text = ""
        self.build_log.clear()

    def _toggle_terminal_expanded(self) -> None:
        self._terminal_expanded = not self._terminal_expanded
        self.video_area.setVisible(not self._terminal_expanded)
        self.setup_container.setVisible(not self._terminal_expanded)
        self.result_container.setVisible(not self._terminal_expanded)
        zoom_text = "Shrink" if self._terminal_expanded else "Maximize"
        self.terminal_zoom_button.setText(zoom_text)
        self.build_zoom_button.setText(zoom_text)
        if self.terminal_tabs.currentWidget() is self.build_tab:
            self.build_log.setFocus()
        else:
            self.terminal.setFocus()

    def _toggle_fullscreen(self) -> None:
        if self.isFullScreen():
            self.showNormal()
        else:
            self.showFullScreen()

    def _leave_fullscreen(self) -> None:
        if self.isFullScreen():
            self.showNormal()


def create_qt_app() -> QtWidgets.QApplication:
    """Return an existing QApplication or create a new one."""
    app = QtWidgets.QApplication.instance()
    if app is not None:
        configure_qt_app(app)
        return app

    # Importing cv2 sets this variable to OpenCV's bundled Qt plugins.  The
    # dashboard is a PyQt5 app, so force Qt back to the matching PyQt5 plugins.
    plugin_path = QtCore.QLibraryInfo.location(QtCore.QLibraryInfo.PluginsPath)
    os.environ["QT_QPA_PLATFORM_PLUGIN_PATH"] = plugin_path
    os.environ["QT_PLUGIN_PATH"] = plugin_path

    QtWidgets.QApplication.setAttribute(QtCore.Qt.AA_EnableHighDpiScaling, True)
    QtWidgets.QApplication.setAttribute(QtCore.Qt.AA_UseHighDpiPixmaps, True)
    app = QtWidgets.QApplication([APP_DESKTOP_ID, "-name", APP_DESKTOP_ID])
    configure_qt_app(app)
    return app
