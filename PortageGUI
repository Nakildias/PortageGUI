import sys
import os
import subprocess
import re
import math
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QTabWidget, QListWidget, QPushButton, QLineEdit, QLabel,
    QStatusBar, QProgressBar, QMessageBox, QTextEdit, QSplitter,
    QListWidgetItem, QTreeWidget, QTreeWidgetItem, QHeaderView
)
from PyQt6.QtCore import (
    Qt, QThread, pyqtSignal, QObject, QTimer, QRegularExpression
)
from PyQt6.QtGui import QPalette, QColor, QIcon, QTextCursor

# --- Configuration ---
COMMAND_TIMEOUT = 300  # Seconds for command timeout
REFRESH_INTERVAL = 300000  # Milliseconds for disk space refresh (5 minutes)
APP_ICON_PATH = "/usr/share/icons/hicolor/48x48/apps/system-software-install.png" # Example path

# --- ANSI Color Conversion ---
try:
    from ansi2html import Ansi2HTMLConverter
    conv = Ansi2HTMLConverter(dark_bg=True, scheme='solarized')
    ANSI_ENABLED = True
except ImportError:
    ANSI_ENABLED = False
    print("Warning: 'ansi2html' library not found. Output console will not display colors.")
    print("Install it using: pip install ansi2html")
    # Basic ANSI escape sequence removal as fallback
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')

# --- Worker Signals ---
class WorkerSignals(QObject):
    finished = pyqtSignal(object)  # Pass callback arg through
    error = pyqtSignal(str, object)  # Pass callback arg through
    result = pyqtSignal(object)
    progress = pyqtSignal(str)
    progress_val = pyqtSignal(int, int) # For determinate progress (not used here yet)

# --- Worker Base Class (For Commands potentially needing pkexec) ---
class CommandWorker(QThread):
    # Keep track of the callback argument to pass through signals
    def __init__(self, command_list, use_pkexec=False, callback_arg=None):
        super().__init__()
        self.command_list = command_list
        self.signals = WorkerSignals()
        self.use_pkexec = use_pkexec
        self.process = None
        self._running = True
        self.callback_arg = callback_arg  # Store callback arg

    def run(self):
        try:
            full_command = self.command_list
            if self.use_pkexec:
                # Check if pkexec exists first
                if subprocess.run(['which', 'pkexec'], capture_output=True, text=True).returncode != 0:
                    self.signals.error.emit("Error: 'pkexec' command not found. Is PolicyKit installed?", self.callback_arg)
                    return
                full_command = ['pkexec', '--disable-internal-agent'] + self.command_list

            self.process = subprocess.Popen(
                full_command,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, bufsize=1, errors='replace' # line buffered, replace encoding errors
            )

            # Read stdout line by line
            if self.process.stdout:
                for line in iter(self.process.stdout.readline, ''):
                    if not self._running: break
                    self.signals.progress.emit(line.strip()) # Emit stripped line
                self.process.stdout.close()

            if not self._running:
                 # If stopped during stdout reading
                self.signals.error.emit("Operation Cancelled", self.callback_arg)
                return

            # Read stderr after stdout is closed
            stderr_output = ""
            if self.process.stderr:
                stderr_output = self.process.stderr.read()
                self.process.stderr.close()

            # Wait for process termination
            self.process.wait(timeout=COMMAND_TIMEOUT)

            # Check return code AFTER process finishes
            if self.process.returncode != 0:
                error_message = f"Command failed with exit code {self.process.returncode}.\n"
                error_message += f"Command: {' '.join(full_command)}\n"
                if stderr_output: error_message += f"Stderr:\n{stderr_output.strip()}"
                else: error_message += "No stderr output captured." # More informative
                self.signals.error.emit(error_message, self.callback_arg)
            else:
                self.signals.result.emit("Command finished successfully.") # Emit generic success
                # Pass callback arg with finished signal
                self.signals.finished.emit(self.callback_arg)

        except FileNotFoundError:
            self.signals.error.emit(f"Error: Command '{self.command_list[0]}' not found.", self.callback_arg)
        except subprocess.TimeoutExpired:
            if self.process: self.process.kill()
            self.signals.error.emit(f"Command timed out after {COMMAND_TIMEOUT} seconds.", self.callback_arg)
        except Exception as e:
            self.signals.error.emit(f"An unexpected error occurred in CommandWorker: {e}", self.callback_arg)
        finally:
             self._running = False # Ensure running flag is cleared

    def stop(self):
        self._running = False
        if self.process and self.process.poll() is None: # Check if process is still running
            try:
                self.signals.progress.emit("Attempting to terminate process...")
                # Try terminate first (graceful)
                self.process.terminate()
                try: self.process.wait(timeout=2) # Wait briefly for terminate
                except subprocess.TimeoutExpired:
                    # Force kill if terminate didn't work
                    self.signals.progress.emit("Forcing process kill...")
                    self.process.kill()
                self.signals.progress.emit("Termination signal sent.")
            except Exception as e:
                 self.signals.progress.emit(f"Could not stop process cleanly: {e}")


# --- Generic Worker for Data Fetching (No pkexec needed) ---
class GenericWorker(QThread):
    def __init__(self, command_list, parser_func=None, callback_arg=None): # Add callback_arg
        super().__init__()
        self.command_list = command_list
        self.parser_func = parser_func
        self.signals = WorkerSignals()
        self.process = None
        self._running = True
        self.callback_arg = callback_arg # Store callback arg

    def run(self):
        try:
            self.process = subprocess.Popen(
                self.command_list,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, bufsize=1, errors='replace'
            )

            stdout_lines = []
            if self.process.stdout:
                 for line in iter(self.process.stdout.readline, ''):
                    if not self._running: break
                    stdout_lines.append(line.strip()) # Collect lines
                 self.process.stdout.close()

            if not self._running:
                self.signals.error.emit("Operation Cancelled", self.callback_arg)
                return

            stderr_output = ""
            if self.process.stderr:
                stderr_output = self.process.stderr.read()
                self.process.stderr.close()

            self.process.wait(timeout=COMMAND_TIMEOUT)

            if self.process.returncode != 0:
                error_message = f"Command failed with exit code {self.process.returncode}.\n"
                error_message += f"Command: {' '.join(self.command_list)}\n"
                if stderr_output: error_message += f"Stderr:\n{stderr_output.strip()}"
                else: error_message += "No stderr output captured."
                # Pass callback arg with error signal
                self.signals.error.emit(error_message, self.callback_arg)
            else:
                # Process results *if* the command succeeded
                result_data = stdout_lines # Default to raw lines if no parser
                if self.parser_func:
                    try:
                        parsed_result = self.parser_func(stdout_lines)
                        result_data = parsed_result
                    except Exception as e:
                         # Error during parsing is also an error condition for the task
                        self.signals.error.emit(f"Error parsing command output: {e}\nOutput:\n{' '.join(stdout_lines[:10])}...", self.callback_arg)
                        return # Don't proceed to finished if parsing failed
                self.signals.result.emit(result_data)
                # Pass callback arg with finished signal
                self.signals.finished.emit(self.callback_arg)

        except FileNotFoundError:
            # Handle if the command (e.g., eix or equery) isn't installed
            self.signals.error.emit(f"Error: Command '{self.command_list[0]}' not found. Is it installed and in PATH?", self.callback_arg)
        except subprocess.TimeoutExpired:
            if self.process: self.process.kill()
            self.signals.error.emit(f"Command timed out after {COMMAND_TIMEOUT} seconds.", self.callback_arg)
        except Exception as e:
            self.signals.error.emit(f"An unexpected error occurred in GenericWorker: {e}", self.callback_arg)
        finally:
            self._running = False

    def stop(self):
        self._running = False
        if self.process and self.process.poll() is None:
            try:
                # GenericWorker might not output to console, so maybe don't emit progress here?
                # Or maybe it's okay for debugging. Let's leave it for now.
                self.signals.progress.emit("Attempting to terminate process...")
                self.process.terminate()
                try: self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.signals.progress.emit("Forcing process kill...")
                    self.process.kill()
                self.signals.progress.emit("Termination signal sent.")
            except Exception as e:
                self.signals.progress.emit(f"Could not stop process cleanly: {e}")


# --- Main Application Window ---
class GentooPackageManagerGUI(QMainWindow):
    # Define constants for load steps
    LOAD_STEP_INSTALLED = 0
    LOAD_STEP_AVAILABLE = 1 # Changed order slightly if needed, but keep names
    LOAD_STEP_UPDATES = 2
    LOAD_STEP_COMPLETE = 3

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Gentoo GUI Package Manager")
        self.setGeometry(100, 100, 1000, 700)

        if os.path.exists(APP_ICON_PATH):
            self.setWindowIcon(QIcon(APP_ICON_PATH))

        self.installed_packages = []
        self.all_available_package_atoms = [] # Renamed for clarity
        self.update_list_atoms = []
        self.update_list_display = []
        self.current_worker = None # Tracks the currently active worker (only one allowed at a time now)

        self.tab_base_texts = {
            "browse": "Browse Packages", "installed": "Installed Packages",
            "updates": "Updates", "output": "Output Console"
        }

        self.setup_ui()
        self.apply_dark_mode()

        # --- Initial Load (Start the sequential loading process) ---
        self.refresh_disk_space() # Synchronous, do it first
        self._start_next_load_step(self.LOAD_STEP_INSTALLED) # Start first step

        self.disk_space_timer = QTimer(self)
        self.disk_space_timer.timeout.connect(self.refresh_disk_space)
        self.disk_space_timer.start(REFRESH_INTERVAL)

    def setup_ui(self):
        self.central_widget = QWidget()
        self.setCentralWidget(self.central_widget)
        self.layout = QVBoxLayout(self.central_widget)
        self.layout.setContentsMargins(5, 5, 5, 5) # Consistent margins
        self.layout.setSpacing(5) # Consistent spacing

        self.tabs = QTabWidget()
        self.layout.addWidget(self.tabs)

        # Create Tab Widgets
        self.browse_tab = QWidget()
        self.installed_tab = QWidget()
        self.update_tab = QWidget()
        self.output_tab = QWidget()

        # Add Tabs
        self.browse_tab_index = self.tabs.addTab(self.browse_tab, self.tab_base_texts["browse"])
        self.installed_tab_index = self.tabs.addTab(self.installed_tab, self.tab_base_texts["installed"])
        self.update_tab_index = self.tabs.addTab(self.update_tab, self.tab_base_texts["updates"])
        self.output_tab_index = self.tabs.addTab(self.output_tab, self.tab_base_texts["output"])

        # Setup individual tabs
        self._setup_browse_tab()
        self._setup_installed_tab()
        self._setup_update_tab()
        self._setup_output_tab()

        # --- Bottom Button Bar ---
        self.bottom_bar_layout = QHBoxLayout()
        self.refresh_button = QPushButton(QIcon.fromTheme("view-refresh"), " Refresh Lists") # Add icon
        self.refresh_button.setToolTip("Reload installed, available, and update package lists sequentially")
        self.refresh_button.clicked.connect(self.refresh_all) # Connect to start sequence
        self.bottom_bar_layout.addWidget(self.refresh_button)

        self.sync_button = QPushButton(QIcon.fromTheme("network-transmit-receive"), " Sync Repositories") # Add icon
        self.sync_button.setToolTip("Run 'emerge --sync' (requires privileges)")
        self.sync_button.clicked.connect(self.run_sync)
        self.bottom_bar_layout.addWidget(self.sync_button)

        self.bottom_bar_layout.addStretch(1) # Push cancel button to the right

        self.cancel_button = QPushButton(QIcon.fromTheme("process-stop"), " Cancel Operation") # Add icon
        self.cancel_button.setToolTip("Attempt to stop the current background operation")
        self.cancel_button.clicked.connect(self.cancel_operation)
        self.cancel_button.setEnabled(False) # Initially disabled
        self.bottom_bar_layout.addWidget(self.cancel_button)
        self.layout.addLayout(self.bottom_bar_layout)

        # --- Status Bar ---
        self.status_bar = QStatusBar()
        self.setStatusBar(self.status_bar)
        self.progress_bar = QProgressBar()
        self.progress_bar.setTextVisible(False)
        self.progress_bar.setRange(0, 0) # Indeterminate initially
        self.progress_bar.setVisible(False)
        self.status_bar.addPermanentWidget(self.progress_bar, 1) # Give it stretch factor 1
        self.disk_space_label = QLabel("Disk: ?/? GB")
        self.status_bar.addPermanentWidget(self.disk_space_label) # Add disk space label

    def _setup_browse_tab(self):
        layout = QVBoxLayout(self.browse_tab)
        layout.setContentsMargins(5, 5, 5, 5)
        layout.setSpacing(5)
        self.browse_search_input = QLineEdit()
        self.browse_search_input.setPlaceholderText("Filter available packages (e.g., category/name or just name)...")
        self.browse_search_input.textChanged.connect(self.filter_browse_packages)
        layout.addWidget(self.browse_search_input)
        self.browse_package_list = QListWidget()
        self.browse_package_list.setSelectionMode(QListWidget.SelectionMode.ExtendedSelection)
        layout.addWidget(self.browse_package_list)
        self.browse_install_button = QPushButton(QIcon.fromTheme("list-add"), " Install Selected") # Add icon
        self.browse_install_button.clicked.connect(self.install_selected_browse)
        layout.addWidget(self.browse_install_button)
        # Initial state message
        self.browse_package_list.addItem("Loading...")
        self.update_tab_text(self.browse_tab_index, "browse", None) # Show (?) initially

    def _setup_installed_tab(self):
        layout = QVBoxLayout(self.installed_tab)
        layout.setContentsMargins(5, 5, 5, 5)
        layout.setSpacing(5)
        self.installed_search_input = QLineEdit()
        self.installed_search_input.setPlaceholderText("Filter installed packages...")
        self.installed_search_input.textChanged.connect(self.filter_installed_packages)
        layout.addWidget(self.installed_search_input)
        self.installed_package_list = QListWidget()
        self.installed_package_list.setSelectionMode(QListWidget.SelectionMode.ExtendedSelection)
        layout.addWidget(self.installed_package_list)
        self.uninstall_button = QPushButton(QIcon.fromTheme("list-remove"), " Uninstall Selected") # Add icon
        self.uninstall_button.clicked.connect(self.uninstall_selected)
        layout.addWidget(self.uninstall_button)
        # Initial state message
        self.installed_package_list.addItem("Loading...")
        self.update_tab_text(self.installed_tab_index, "installed", None) # Show (?) initially

    def _setup_update_tab(self):
        layout = QVBoxLayout(self.update_tab)
        layout.setContentsMargins(5, 5, 5, 5)
        layout.setSpacing(5)
        self.update_package_list = QListWidget()
        self.update_package_list.setSelectionMode(QListWidget.SelectionMode.ExtendedSelection)
        layout.addWidget(self.update_package_list)
        button_layout = QHBoxLayout()
        self.update_selected_button = QPushButton(QIcon.fromTheme("system-software-update"), " Update Selected") # Add icon
        self.update_selected_button.clicked.connect(self.update_selected)
        button_layout.addWidget(self.update_selected_button)
        self.update_all_button = QPushButton(QIcon.fromTheme("emblem-system"), " Update All (@world)") # Add icon
        self.update_all_button.clicked.connect(self.update_all)
        button_layout.addWidget(self.update_all_button)
        layout.addLayout(button_layout)
        # Initial state message
        self.update_package_list.addItem("Loading...")
        self.update_tab_text(self.update_tab_index, "updates", None) # Show (?) initially

    def _setup_output_tab(self):
        layout = QVBoxLayout(self.output_tab)
        layout.setContentsMargins(0, 0, 0, 0) # No margins for console
        self.output_console = QTextEdit()
        self.output_console.setReadOnly(True)
        self.output_console.setLineWrapMode(QTextEdit.LineWrapMode.NoWrap) # Keep long lines intact
        # Apply dark theme specific colors to console
        console_palette = self.output_console.palette()
        console_palette.setColor(QPalette.ColorRole.Base, QColor(30, 30, 30)) # Dark background
        console_palette.setColor(QPalette.ColorRole.Text, Qt.GlobalColor.lightGray) # Light text
        self.output_console.setPalette(console_palette)
        layout.addWidget(self.output_console)

    def filter_browse_packages(self):
        filter_text = self.browse_search_input.text().strip().lower()
        self.browse_package_list.clear()
        # Check if the list has been populated
        if hasattr(self, 'all_available_package_atoms') and self.all_available_package_atoms:
            if not filter_text:
                # Display all if no filter
                self.browse_package_list.addItems(self.all_available_package_atoms)
            else:
                # Apply filter
                matching_items = [pkg for pkg in self.all_available_package_atoms if filter_text in pkg.lower()]
                self.browse_package_list.addItems(matching_items)
        elif not filter_text: # Show loading/empty message only if list not populated and no filter
             # Avoid showing "Loading..." if list is truly empty after loading
            if not self.all_available_package_atoms and self.current_worker and self.current_worker.isRunning():
                 self.browse_package_list.addItem("Loading...")
            elif not self.all_available_package_atoms:
                 self.browse_package_list.addItem("No available packages found or list failed to load.")


    def filter_installed_packages(self):
        filter_text = self.installed_search_input.text().strip().lower()
        self.installed_package_list.clear()
        if hasattr(self, 'installed_packages') and self.installed_packages:
            if not filter_text:
                self.installed_package_list.addItems(self.installed_packages)
            else:
                matching_items = [pkg for pkg in self.installed_packages if filter_text in pkg.lower()]
                self.installed_package_list.addItems(matching_items)
        elif not filter_text: # Show loading/empty message only if list not populated and no filter
            if not self.installed_packages and self.current_worker and self.current_worker.isRunning():
                self.installed_package_list.addItem("Loading...")
            elif not self.installed_packages:
                self.installed_package_list.addItem("No installed packages found or list failed to load.")


    def apply_dark_mode(self):
        dark_palette = QPalette()
        # Base Colors
        dark_palette.setColor(QPalette.ColorRole.Window, QColor(53, 53, 53)) # Main window background
        dark_palette.setColor(QPalette.ColorRole.WindowText, Qt.GlobalColor.white) # Text on window
        dark_palette.setColor(QPalette.ColorRole.Base, QColor(42, 42, 42)) # Input fields, list backgrounds
        dark_palette.setColor(QPalette.ColorRole.AlternateBase, QColor(66, 66, 66)) # Alternate row color (if used)
        dark_palette.setColor(QPalette.ColorRole.ToolTipBase, Qt.GlobalColor.black)
        dark_palette.setColor(QPalette.ColorRole.ToolTipText, Qt.GlobalColor.white)
        dark_palette.setColor(QPalette.ColorRole.Text, Qt.GlobalColor.white) # General text in widgets
        dark_palette.setColor(QPalette.ColorRole.Button, QColor(53, 53, 53)) # Button background
        dark_palette.setColor(QPalette.ColorRole.ButtonText, Qt.GlobalColor.white) # Button text
        dark_palette.setColor(QPalette.ColorRole.BrightText, Qt.GlobalColor.red) # e.g., text in critical message boxes

        # Highlight Colors
        dark_palette.setColor(QPalette.ColorRole.Highlight, QColor(42, 130, 218)) # Blue highlight for selected items
        dark_palette.setColor(QPalette.ColorRole.HighlightedText, Qt.GlobalColor.white) # Text in highlighted items

        # Disabled Colors
        dark_palette.setColor(QPalette.ColorRole.PlaceholderText, QColor(127, 127, 127)) # Placeholder text in line edits
        dark_palette.setColor(QPalette.ColorGroup.Disabled, QPalette.ColorRole.Text, QColor(127, 127, 127))
        dark_palette.setColor(QPalette.ColorGroup.Disabled, QPalette.ColorRole.ButtonText, QColor(127, 127, 127))
        dark_palette.setColor(QPalette.ColorGroup.Disabled, QPalette.ColorRole.WindowText, QColor(127, 127, 127))
        dark_palette.setColor(QPalette.ColorGroup.Disabled, QPalette.ColorRole.Highlight, QColor(80, 80, 80)) # Disabled selection color
        dark_palette.setColor(QPalette.ColorGroup.Disabled, QPalette.ColorRole.HighlightedText, QColor(127, 127, 127))

        app = QApplication.instance()
        if app: # Ensure app exists
            app.setPalette(dark_palette)
            app.setStyleSheet("""
                QToolTip {
                    color: #ffffff; /* White text */
                    background-color: #2a82da; /* Blue background */
                    border: 1px solid white; /* White border */
                    padding: 2px;
                }
                QStatusBar {
                    color: #ffffff; /* White text in status bar */
                }
                QProgressBar {
                    border: 1px solid #666666; /* Gray border */
                    border-radius: 5px;
                    text-align: center; /* Center text if shown */
                    color: #ffffff; /* White text */
                    background-color: #424242; /* Dark gray background */
                }
                QProgressBar::chunk {
                    background-color: #4287f5; /* Blue progress chunk */
                    border-radius: 4px; /* Slightly rounded chunk */
                    margin: 1px; /* Small margin around chunk */
                }
                QListWidget, QTreeWidget { /* Apply to both list and tree widgets */
                    background-color: QColor(42, 42, 42); /* Match Base color */
                    /* Consider adding alternate row colors if desired */
                    /* alternate-background-color: QColor(66, 66, 66); */
                }
                 QTreeView::item:hover, QListWidget::item:hover {
                     background-color: QColor(60, 60, 60); /* Slightly lighter on hover */
                 }
                QTreeView::item:selected, QListWidget::item:selected {
                     background-color: #2a82da; /* Match Highlight color */
                     color: white; /* Ensure text is white when selected */
                 }
                QTabWidget::pane { /* The area where tab content is shown */
                    border: none; /* No border around the content pane */
                 }
                QTabWidget::tab-bar {
                    alignment: left; /* Align tabs to the left */
                }
                QTabBar::tab {
                    background: QColor(66, 66, 66); /* Darker gray for inactive tabs */
                    border: 1px solid #444; /* Slightly darker border */
                    border-bottom: none; /* No border at bottom for inactive */
                    border-top-left-radius: 4px;
                    border-top-right-radius: 4px;
                    min-width: 10ex; /* Minimum width */
                    padding: 5px; /* Padding around text */
                    margin-right: 1px; /* Small space between tabs */
                    color: #dddddd; /* Lighter gray text for inactive/hover */
                }
                QTabBar::tab:hover {
                    background: QColor(80, 80, 80); /* Slightly lighter on hover */
                }
                QTabBar::tab:selected {
                    background: QColor(53, 53, 53); /* Match window background for selected */
                    border-color: #444;
                    border-bottom: none; /* Selected tab 'connects' to pane */
                    color: #ffffff; /* White text for selected */
                }
                QTabBar::tab:!selected {
                     margin-top: 2px; /* Make inactive tabs slightly lower */
                     background: QColor(70, 70, 70); /* Slightly different shade */
                     color: #aaaaaa; /* More subdued text */
                 }
                QLineEdit {
                    background-color: QColor(42, 42, 42); /* Match Base */
                    padding: 2px;
                    border: 1px solid #666666; /* Gray border */
                    border-radius: 3px;
                }
                 QTextEdit { /* Style for the output console */
                     background-color: QColor(30, 30, 30); /* Very dark background */
                     color: #f0f0f0; /* Off-white text */
                     border: 1px solid #444; /* Dark border */
                 }
            """)

    def update_tab_text(self, tab_index, base_text_key, count):
        """Updates the text of a tab, adding the item count."""
        base_text = self.tab_base_texts.get(base_text_key, "Tab")
        if count is None:
            display_text = f"{base_text} (?)" # Indicate loading/unknown
        else:
            display_text = f"{base_text} ({count})"
        try:
            self.tabs.setTabText(tab_index, display_text)
        except Exception as e:
            print(f"Error updating tab text for index {tab_index}: {e}") # Debug potential issues


    # --- Sequential Loading Logic ---
    def _start_next_load_step(self, step):
        """Starts the next step in the initial data loading sequence."""
        if step == self.LOAD_STEP_INSTALLED:
            self.refresh_installed_packages(callback_arg=self.LOAD_STEP_AVAILABLE) # Pass next step
        elif step == self.LOAD_STEP_AVAILABLE:
            self.load_all_available_packages(callback_arg=self.LOAD_STEP_UPDATES) # Pass next step
        elif step == self.LOAD_STEP_UPDATES:
            self.refresh_updates(callback_arg=self.LOAD_STEP_COMPLETE) # Pass next step
        elif step == self.LOAD_STEP_COMPLETE:
            self.status_bar.showMessage("Initial loading complete.", 5000)
            # Ensure progress bar is hidden and cancel button disabled
            self.progress_bar.setVisible(False)
            self.cancel_button.setEnabled(False)
            self.current_worker = None # Ensure worker is cleared

    # --- Backend Interaction (Generic Task Runner for Sequential Load) ---
    def run_generic_task(self, command_list, parser_func, on_result, on_finished_callback, on_error_callback, status_message, callback_arg=None):
        """Runs a generic command, managing the single self.current_worker."""
        # *** Check if a worker is ALREADY running ***
        if self.current_worker and self.current_worker.isRunning():
            # This case should ideally not happen with strict sequential loading,
            # but handle it defensively. Log it, maybe show error.
            print(f"Warning: Tried to start task '{' '.join(command_list)}' while another was running.")
            # Optionally show error to user:
            # self.show_error("Error: Tried to start a data loading task while another was running.\nPlease wait.")
            # Decide how to proceed: either skip this step or wait?
            # For sequential load, skipping might be better than getting stuck.
            # We'll call the error handler which should then call the next step.
            on_error_callback("Internal Error: Task conflict during sequential load.", callback_arg)
            return

        self.status_bar.showMessage(status_message)
        self.progress_bar.setRange(0, 0) # Indeterminate for loading
        self.progress_bar.setVisible(True)
        self.cancel_button.setEnabled(True) # Enable cancel for loading tasks too

        # Create and store the worker instance
        self.current_worker = GenericWorker(command_list, parser_func, callback_arg) # Pass callback_arg

        # Connect signals
        self.current_worker.signals.finished.connect(on_finished_callback) # Will call _generic_finished
        self.current_worker.signals.error.connect(on_error_callback)     # Will call _generic_error
        self.current_worker.signals.result.connect(on_result)
        # self.current_worker.signals.progress.connect(self._command_progress) # Generic worker doesn't usually emit line-by-line progress

        self.current_worker.start()

    def _generic_finished(self, callback_arg):
        """Called when a GenericWorker finishes successfully."""
        # Don't hide progress bar or disable cancel immediately, wait for sequence end
        # The sequence end (LOAD_STEP_COMPLETE) handles UI cleanup.
        print(f"Generic task finished, proceeding to step: {callback_arg}") # Debug log
        worker_ref = self.current_worker # Keep ref temporarily if needed
        self.current_worker = None # Clear worker *before* starting next step
        # Trigger the next loading step
        self._start_next_load_step(callback_arg)

    def _generic_error(self, error_msg, callback_arg):
        """Called when a GenericWorker fails."""
        print(f"Generic task error: {error_msg}, proceeding to step: {callback_arg}") # Debug log
        # Don't hide progress bar/cancel yet if part of sequence.
        # The error message should be shown in the respective list or console.

        # Check if it was a cancellation
        if "Operation Cancelled" in error_msg:
            self.status_bar.showMessage("Load operation Cancelled.", 5000)
            self.output_console.append(f"\n{'-'*20}\nLoad Operation Cancelled by User.")
            self.output_console.ensureCursorVisible()
            # Stop the sequence on cancel
            self.progress_bar.setVisible(False)
            self.cancel_button.setEnabled(False)
            self.current_worker = None
            return # Don't proceed to next step if cancelled

        # Log the specific error to the console
        self.output_console.append(f"\n{'-'*20}\nERROR during data load:\n{error_msg}")
        self.output_console.ensureCursorVisible()

        # Show a brief status bar message
        self.status_bar.showMessage(f"Load failed: {error_msg.splitlines()[0]}...", 6000)

        # Maybe show a dialog for critical errors like command not found?
        if "Command not found" in error_msg:
             self.show_error(f"Data Loading Failed:\n{error_msg}\n\nPlease ensure the necessary tools (like eix, equery) are installed and in your PATH.")
             # Stop sequence if essential command missing
             self.progress_bar.setVisible(False)
             self.cancel_button.setEnabled(False)
             self.current_worker = None
             return


        # Clear the worker reference *before* potentially starting the next step
        worker_ref = self.current_worker # Keep ref temporarily if needed
        self.current_worker = None

        # Trigger the next loading step *even on error* so the sequence continues
        # and subsequent lists might still load.
        self._start_next_load_step(callback_arg)


    # --- Backend Interaction (Emerge Commands - User Actions) ---
    def run_emerge_command(self, command_list, on_finished_callback, on_error_callback, status_message, use_pkexec=True):
        """Runs an emerge command, managing the single self.current_worker."""
        if self.current_worker and self.current_worker.isRunning():
            self.show_error("Another operation is already in progress. Please wait or cancel.")
            return

        self.status_bar.showMessage(status_message)
        self.progress_bar.setRange(0, 0) # Emerge output is complex, use indeterminate
        self.progress_bar.setVisible(True)
        self.cancel_button.setEnabled(True)
        self.tabs.setCurrentWidget(self.output_tab) # Switch to output tab

        # Append command start to console
        self.output_console.append(f"\n{'-'*30}\nExecuting: {'pkexec ' if use_pkexec else ''}{' '.join(command_list)}\n{'-'*30}\n")
        self.output_console.ensureCursorVisible()

        # Create and store the worker instance
        self.current_worker = CommandWorker(command_list, use_pkexec) # No callback arg needed for simple actions

        # Connect signals to specific handlers for user actions
        # Use lambda to pass the specific callback to the generic handler
        self.current_worker.signals.finished.connect(lambda cb_arg: self._command_action_finished(on_finished_callback))
        self.current_worker.signals.error.connect(lambda error_msg, cb_arg: self._command_action_error(error_msg, on_error_callback))
        self.current_worker.signals.progress.connect(self._command_progress)

        self.current_worker.start()

    def _command_action_finished(self, callback):
        """Handler for successful user action command completion."""
        self.status_bar.showMessage("Operation completed successfully.", 5000)
        self.progress_bar.setVisible(False)
        self.cancel_button.setEnabled(False)
        # Append success message to console
        self.output_console.append(f"\n{'-'*20}\nOperation finished successfully.")
        self.output_console.ensureCursorVisible()

        self.current_worker = None # Clear worker reference
        if callback:
            try:
                callback() # Execute the post-action callback (e.g., refresh lists)
            except Exception as e:
                print(f"Error during post-action callback: {e}")
                self.show_error(f"Operation succeeded, but an error occurred during the post-action callback:\n{e}")


    def _command_action_error(self, error_msg, callback):
        """Handler for failed user action command completion."""
        self.progress_bar.setVisible(False)
        self.cancel_button.setEnabled(False)

        # Append error details to console
        if "Operation Cancelled" in error_msg:
            self.status_bar.showMessage("Operation Cancelled.", 5000)
            self.output_console.append(f"\n{'-'*20}\nOperation Cancelled by User.")
        else:
            # Log full error to console first
            self.output_console.append(f"\n{'-'*20}\nERROR:\n{error_msg}")
            # Show user-friendly dialog
            self.show_error(f"Operation Failed:\n{error_msg.splitlines()[0]}...\n\nSee Output Console for details.")
            # Update status bar
            self.status_bar.showMessage(f"Operation failed: {error_msg.splitlines()[0]}", 6000)

        self.output_console.ensureCursorVisible()
        self.current_worker = None # Clear worker reference

        # Optional: Execute an error callback if provided (e.g., to re-enable buttons)
        # Only call if it wasn't a user cancellation.
        if callback and "Operation Cancelled" not in error_msg:
             try:
                 callback(error_msg) # Pass error message to callback
             except Exception as e:
                 print(f"Error during action error callback: {e}")


    def _command_progress(self, progress_text):
        """Handles progress updates (stdout lines) from workers (both types)."""
        cursor = self.output_console.textCursor()
        cursor.movePosition(QTextCursor.MoveOperation.End)
        self.output_console.setTextCursor(cursor)

        if ANSI_ENABLED:
            # Convert ANSI codes to HTML for rich text display
            html_output = conv.convert(progress_text, full=False)
            self.output_console.insertHtml(html_output + "<br>") # Add line break
        elif ansi_escape:
            # Simple removal of ANSI codes if ansi2html is not available
            cleaned_text = ansi_escape.sub('', progress_text)
            self.output_console.insertPlainText(cleaned_text + "\n") # Append plain text + newline
        else:
            # Fallback if even basic regex fails
             self.output_console.insertPlainText(progress_text + "\n")

        self.output_console.ensureCursorVisible() # Scroll to the bottom


    def cancel_operation(self):
        """Attempts to stop the currently running worker."""
        if self.current_worker and self.current_worker.isRunning():
            self.status_bar.showMessage("Attempting to cancel operation...")
            self.current_worker.stop()
            self.cancel_button.setEnabled(False) # Disable button immediately
            # Let the worker's error/finished signal handlers manage the rest of the UI cleanup (like hiding progress bar)
        else:
            self.status_bar.showMessage("No operation running to cancel.", 3000)


    def get_selected_package_atoms(self, list_widget):
        """Extracts package atoms (category/name) from selected list items."""
        items = list_widget.selectedItems()
        results = set() # Use a set to avoid duplicates easily
        # Regex to capture category/package, ignoring version or flags
        # Handles formats like: cat/pkg, cat/pkg-1.2.3, cat/pkg -> 1.2.4 [Update]
        atom_pattern = re.compile(r'^([\w.+-]+/[\w.+-]+)')
        for item in items:
            text = item.text()
            match = atom_pattern.match(text)
            if match:
                results.add(match.group(1))
            else:
                # Fallback: if no version/flags, assume the whole text is the atom
                # if it looks like one (contains '/')
                if '/' in text and ' ' not in text:
                     results.add(text)
                else:
                    print(f"Warning: Could not parse package atom from selected item: {text}")
        return sorted(list(results))


    # --- Specific Actions ---

    def run_sync(self):
        """Runs 'emerge --sync' after confirmation."""
        msg_box = QMessageBox(self)
        msg_box.setWindowTitle("Confirm Sync")
        msg_box.setIcon(QMessageBox.Icon.Question)
        msg_box.setText("This will synchronize the package repositories using 'emerge --sync'.\nThis can take some time and requires root privileges (via pkexec).\n\nContinue?")
        msg_box.setStandardButtons(QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        msg_box.setDefaultButton(QMessageBox.StandardButton.No)
        if msg_box.exec() == QMessageBox.StandardButton.Yes:
            # Use run_emerge_command for user action
            self.run_emerge_command(
                ['emerge', '--sync'],
                on_finished_callback=self._sync_finished, # Callback after sync finishes
                on_error_callback=None, # Default error message handling is fine
                status_message="Running emerge --sync...",
                use_pkexec=True
            )

    def _sync_finished(self):
        """Callback after emerge --sync completes successfully."""
        # Sync finished, now REFRESH the updates list is the most logical next step
        self.status_bar.showMessage("Sync finished. Refreshing updates list...", 3000)
        # Directly call refresh_updates. It will handle the self.current_worker check.
        # Pass LOAD_STEP_COMPLETE so it doesn't try to chain further loads automatically.
        # This assumes refresh_updates doesn't *require* prior steps to have run in this specific call context.
        self.refresh_updates(callback_arg=self.LOAD_STEP_COMPLETE)


    def refresh_all(self):
        """Starts the sequential refresh process from the beginning."""
        if self.current_worker and self.current_worker.isRunning():
            self.show_error("Cannot refresh: An operation is already in progress.\nPlease wait or cancel the current operation.")
            return

        self.status_bar.showMessage("Starting full refresh sequence...", 0)
        # Clear lists and show loading indicators immediately
        self.installed_package_list.clear(); self.installed_package_list.addItem("Loading...")
        self.browse_package_list.clear(); self.browse_package_list.addItem("Loading...")
        self.update_package_list.clear(); self.update_package_list.addItem("Loading...")
        self.update_tab_text(self.installed_tab_index, "installed", None)
        self.update_tab_text(self.browse_tab_index, "browse", None)
        self.update_tab_text(self.update_tab_index, "updates", None)

        # Start the first step of the loading sequence
        self._start_next_load_step(self.LOAD_STEP_INSTALLED)


    # --- Data Loading Functions ---

    def load_all_available_packages(self, callback_arg=None):
        """
        Loads all available package atoms using 'eix -c --only-names */*'.
        Requires eix to be installed.
        """
        self.update_tab_text(self.browse_tab_index, "browse", None)
        self.browse_package_list.clear() # Clear previous content/loading message
        self.browse_package_list.addItem("Loading available packages (using eix)...")

        def parse_eix_output(lines):
            """Parses the simple 'category/package' output of eix."""
            packages = set()
            for line in lines:
                # Basic validation: must contain '/' and not be empty/whitespace
                if line and '/' in line:
                    packages.add(line.strip())
            return sorted(list(packages))

        def on_load_available_result(packages):
            """Callback when available package list is loaded successfully."""
            self.all_available_package_atoms = packages # Store the loaded atoms
            self.browse_package_list.clear()
            count = len(self.all_available_package_atoms)
            if count > 0:
                self.browse_package_list.addItems(self.all_available_package_atoms)
                self.status_bar.showMessage(f"Loaded {count} available packages.", 3000)
            else:
                self.browse_package_list.addItem("No available packages found (check eix?).")
                self.status_bar.showMessage("No available packages found.", 3000)

            self.update_tab_text(self.browse_tab_index, "browse", count)
            # Apply filter in case user typed while loading
            self.filter_browse_packages()

        # Custom error handler for this step
        def on_load_available_error(error_msg, cb_arg):
            self.browse_package_list.clear()
            self.browse_package_list.addItem(f"Error loading available packages.")
            # Let the generic error handler manage console logging, status bar, and proceeding
            self._generic_error(error_msg, cb_arg) # Call generic handler

        # Use the generic task runner
        self.run_generic_task(
            command_list=['eix', '-c', '--only-names', '*/*'], # Use eix
            parser_func=parse_eix_output,                     # Use eix parser
            on_result=on_load_available_result,
            on_finished_callback=self._generic_finished,      # Generic handler to continue sequence
            on_error_callback=on_load_available_error,        # Use custom error handler
            status_message="Loading available packages (eix)...",
            callback_arg=callback_arg # Pass the next step info
        )


    def refresh_installed_packages(self, callback_arg=None):
        """Loads installed packages using 'equery list --installed */*'."""
        self.update_tab_text(self.installed_tab_index, "installed", None)
        self.installed_package_list.clear()
        self.installed_package_list.addItem("Loading installed packages...")

        def parse_equery_installed(lines):
            """Parses 'equery list --installed' output (cat/pkg-ver)."""
            # Filter out equery's status lines and empty lines
            installed = sorted([line.strip() for line in lines if line and not line.startswith('[') and '/' in line])
            return installed

        def on_installed_result(packages):
            """Callback when installed packages are loaded."""
            self.installed_packages = packages
            self.installed_package_list.clear()
            count = len(self.installed_packages)
            if count > 0:
                self.installed_package_list.addItems(self.installed_packages)
                self.status_bar.showMessage(f"{count} installed packages loaded.", 3000)
            else:
                 self.installed_package_list.addItem("No installed packages found (check equery?).")
                 self.status_bar.showMessage("No installed packages found.", 3000)

            self.update_tab_text(self.installed_tab_index, "installed", count)
            # Apply filter in case user typed while loading
            self.filter_installed_packages()

        # Custom error handler for this step
        def on_installed_error(error_msg, cb_arg):
             self.installed_package_list.clear()
             self.installed_package_list.addItem(f"Error loading installed packages.")
             # Let the generic error handler manage console/status/proceeding
             self._generic_error(error_msg, cb_arg)

        # Use the generic task runner
        self.run_generic_task(
            command_list=['equery', 'list', '--installed', '*/*'], # Command for installed
            parser_func=parse_equery_installed,
            on_result=on_installed_result,
            on_finished_callback=self._generic_finished, # Generic handler
            on_error_callback=on_installed_error,      # Custom handler for this step
            status_message="Loading installed packages...",
            callback_arg=callback_arg # Pass next step
        )


    def refresh_updates(self, callback_arg=None):
        """Checks for updates using emerge -upvND @world."""
        self.update_tab_text(self.update_tab_index, "updates", None)
        self.update_package_list.clear()
        self.update_package_list.addItem("Checking for updates (emerge pretend)...")

        # Regex to capture package atom and new version/flags from emerge output
        update_pattern = re.compile(
            r"\[ebuild\s+"          # Start of line
            r"([NURD ]{1,2})"      # Flags (New, Update, Rebuild, Downgrade, Slot conflict?) - allow space too
            r"[^\]]*?\]\s+"        # Rest of bracketed info and space
            r"([\w.+-]+/[\w.+-]+)" # Package Atom (cat/pkg) - more robust chars allowed
            r"-([\d.].*?)"          # Version (starts with digit, non-greedy)
            r"(?:\s+USE=.*?)?"      # Optional USE flags part
            r"(?:\s+CFLAGS=.*?)?"   # Optional CFLAGS part
            r"(?:\s+LDFLAGS=.*?)?"  # Optional LDFLAGS part
            r"(?:\s+REPO=.*?)?"     # Optional REPO part
            r"(?:\s+SLOT=.*?)?"     # Optional SLOT part
            r"(?:\s*->\s*([\w.+-/]+-[\d.]+.*?))?" # Optional new version/slot (-> target)
            r"\s*$", re.IGNORECASE # Ignore case for flags, match end of line
        )
        # Simplified Flag mapping
        flag_map = {'U': 'Update', 'N': 'New', 'R': 'Rebuild', 'D': 'Downgrade', ' ': ' '}

        def parse_updates(lines):
            """Parses 'emerge -upvND @world' output."""
            updates_atoms = set()
            updates_display_dict = {} # Use dict to handle potential duplicate atoms with different flags/versions

            for line in lines:
                if line.startswith('[ebuild'):
                    match = update_pattern.search(line)
                    if match:
                        flags, pkg_cat_name, old_ver, new_ver_info = match.groups()

                        # Determine primary flag character
                        primary_flag = ' '
                        if 'U' in flags: primary_flag = 'U'
                        elif 'N' in flags: primary_flag = 'N'
                        elif 'R' in flags: primary_flag = 'R'
                        elif 'D' in flags: primary_flag = 'D'

                        flag_text = flag_map.get(primary_flag, '?')

                        # Construct display text
                        version_display = old_ver.strip()
                        if new_ver_info:
                             version_display += f" -> {new_ver_info.strip()}"

                        display_text = f"{pkg_cat_name} ({version_display}) [{flag_text}]"

                        updates_atoms.add(pkg_cat_name)
                        # Store the display text, potentially overwriting if atom seen again (rare)
                        updates_display_dict[pkg_cat_name] = display_text

            # Sort display text based on the sorted atoms
            sorted_atoms = sorted(list(updates_atoms))
            sorted_display = [updates_display_dict[atom] for atom in sorted_atoms]

            return {"atoms": sorted_atoms, "display": sorted_display}


        def on_updates_result(update_data):
            """Callback when update check finishes."""
            self.update_list_atoms = update_data["atoms"]
            self.update_list_display = update_data["display"]
            self.update_package_list.clear()
            count = len(self.update_list_atoms)
            if count == 0:
                self.update_package_list.addItem("No updates available.")
                self.status_bar.showMessage("System is up to date.", 3000)
            else:
                self.update_package_list.addItems(self.update_list_display)
                self.status_bar.showMessage(f"{count} updates available.", 3000)
            self.update_tab_text(self.update_tab_index, "updates", count)


        def on_updates_error(error_msg, cb_arg):
            """Custom error handler for emerge pretend, handles 'no updates' case."""
            # Check if it's the expected output for no updates (emerge often exits non-zero here)
            # Look for specific phrases in stderr or stdout
            no_updates_phrases = [
                "There are no packages to update",
                "Nothing to merge",
                "emerge: there are no ebuilds to satisfy", # Can happen if @world is empty/broken
                "Exiting." # Often follows the above messages
            ]
            is_no_updates = any(phrase in error_msg for phrase in no_updates_phrases)

            if is_no_updates:
                print("Detected 'no updates' condition from emerge output.")
                # Treat as success with zero updates
                on_updates_result({"atoms": [], "display": []})
                # Manually call the *finish* handler for the sequence because it wasn't a real error
                self._generic_finished(cb_arg)
            # Handle permission error specifically (emerge pretend doesn't need root, but might access restricted dirs)
            elif "Permission denied" in error_msg or "are you root?" in error_msg:
                 self.update_package_list.clear()
                 self.update_package_list.addItem(f"Permission error checking updates.")
                 self.update_tab_text(self.update_tab_index, "updates", 0) # Set count to 0 on error
                 # Call generic error handler to log, show status, and continue sequence
                 self._generic_error(error_msg, cb_arg)
            else:
                # Actual error, let generic handler deal with it
                self.update_package_list.clear()
                self.update_package_list.addItem(f"Error checking for updates.")
                self.update_tab_text(self.update_tab_index, "updates", 0) # Set count to 0
                self._generic_error(error_msg, cb_arg)


        # Use the generic task runner (emerge pretend doesn't need pkexec)
        self.run_generic_task(
            command_list=['emerge', '-upvND', '@world'], # '--color=n' might simplify parsing if needed
            parser_func=parse_updates,
            on_result=on_updates_result,
            on_finished_callback=self._generic_finished, # Generic success handler
            on_error_callback=on_updates_error,         # *** Use custom error handler ***
            status_message="Checking for updates (emerge -upvND @world)...",
            callback_arg=callback_arg # Pass next step
        )

    # --- Install, Uninstall, Update Actions (Use run_emerge_command) ---

    def _install_packages(self, package_atoms_to_install):
        """Handles the process of installing selected packages."""
        if not package_atoms_to_install:
            self.show_error("No valid package atoms selected or parsed to install.")
            return

        package_str = " ".join(package_atoms_to_install)
        msg_box = QMessageBox(self)
        msg_box.setWindowTitle("Confirm Installation")
        msg_box.setIcon(QMessageBox.Icon.Question)
        msg_box.setText(f"The following packages will be emerged (installed/updated):\n\n<b>{package_str}</b>\n\nRequires root privileges (via pkexec). Continue?")
        msg_box.setStandardButtons(QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        msg_box.setDefaultButton(QMessageBox.StandardButton.No)

        if msg_box.exec() == QMessageBox.StandardButton.Yes:
            # emerge --ask=n requires pkexec later anyway, so might as well use it here.
            # Use --verbose for better output, --ask=n to skip interactive prompts (handled by pkexec)
            command = ['emerge', '--ask=n', '--verbose'] + package_atoms_to_install
            self.run_emerge_command( # Use action runner
                command,
                on_finished_callback=self._action_requires_refresh, # Refresh lists on success
                on_error_callback=None, # Default error handling for actions
                status_message=f"Installing {len(package_atoms_to_install)} package(s)...",
                use_pkexec=True
            )

    def install_selected_browse(self):
        """Gets selected packages from browse list and initiates installation."""
        # Use the helper to get atoms directly
        selected_atoms = self.get_selected_package_atoms(self.browse_package_list)
        if selected_atoms:
            self._install_packages(selected_atoms)
        else:
             self.show_error("No packages selected in the Browse tab.")


    def uninstall_selected(self):
        """Gets selected packages from installed list and initiates uninstallation."""
        selected_atoms = self.get_selected_package_atoms(self.installed_package_list)
        if not selected_atoms:
            self.show_error("No packages selected in the Installed tab.")
            return

        package_str = " ".join(selected_atoms)
        msg_box = QMessageBox(self)
        msg_box.setWindowTitle("Confirm Uninstallation")
        msg_box.setIcon(QMessageBox.Icon.Warning)
        msg_box.setText(f"The following packages will be unmerged:\n\n<b>{package_str}</b>\n\nDependencies will <b>not</b> be automatically removed.\nConsider running 'emerge --depclean' afterwards.\nRequires root privileges. Continue?")
        msg_box.setStandardButtons(QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        msg_box.setDefaultButton(QMessageBox.StandardButton.No)

        if msg_box.exec() == QMessageBox.StandardButton.Yes:
            # Use --ask=n and --verbose
            command = ['emerge', '--ask=n', '--verbose', '--unmerge'] + selected_atoms
            self.run_emerge_command( # Use action runner
                command,
                on_finished_callback=self._action_requires_refresh, # Refresh on success
                on_error_callback=None,
                status_message=f"Unmerging {len(selected_atoms)} package(s)...",
                use_pkexec=True
            )

    def update_selected(self):
        """Gets selected packages from the update list and initiates update."""
        selected_atoms = self.get_selected_package_atoms(self.update_package_list)
        if not selected_atoms:
            self.show_error("No updates selected.")
            return
        # Pass the specific atoms to the update function
        self._perform_update(selected_atoms)

    def update_all(self):
        """Initiates update for @world if updates are available."""
        if not self.update_list_atoms:
            # Check if list is empty or just hasn't been loaded yet
            if self.update_package_list.count() > 0 and "Loading" not in self.update_package_list.item(0).text():
                 self.show_error("No updates available to perform.")
            else:
                 self.show_error("Updates list is not populated. Please refresh first.")
            return
        # Use '@world' target for update all
        self._perform_update(['@world'])

    def _perform_update(self, packages_or_world):
        """Handles the actual emerge command for updating packages or @world."""
        package_str = " ".join(packages_or_world)
        target_desc = "@world (all possible updates)" if package_str == "@world" else f"selected package(s):\n{package_str}"

        msg_box = QMessageBox(self)
        msg_box.setWindowTitle("Confirm Update")
        msg_box.setIcon(QMessageBox.Icon.Question)
        msg_box.setText(f"Perform updates for {target_desc}\n\nUsing 'emerge -uND --verbose --ask=n'.\nRequires root privileges. Continue?")
        msg_box.setStandardButtons(QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        msg_box.setDefaultButton(QMessageBox.StandardButton.No)

        if msg_box.exec() == QMessageBox.StandardButton.Yes:
            # Command includes -uND (Update, New, Deep)
            command = ['emerge', '--ask=n', '--verbose', '-uND'] + packages_or_world
            self.run_emerge_command( # Use action runner
                command,
                on_finished_callback=self._action_requires_refresh, # Refresh on success
                on_error_callback=None,
                status_message=f"Updating {package_str}...",
                use_pkexec=True
            )

    def _action_requires_refresh(self):
        """Generic callback after install/uninstall/update finishes successfully."""
        self.status_bar.showMessage("Operation finished. Refreshing all lists...", 3000)
        # Start the full refresh sequence again to get updated data
        self.refresh_all()


    # --- Utility Functions ---

    def refresh_disk_space(self):
        """Updates the disk space label in the status bar."""
        try:
            # Get stats for the root filesystem
            stats = os.statvfs('/')
            # Calculate sizes in bytes
            total_bytes = stats.f_blocks * stats.f_frsize
            # Available to non-root user
            available_bytes = stats.f_bavail * stats.f_frsize
            # Used = Total - Free (f_bfree includes blocks reserved for root)
            # A more accurate 'used' might be total - available_to_non_root,
            # but let's stick to the common interpretation:
            used_bytes = total_bytes - (stats.f_bfree * stats.f_frsize)

            # Convert to GB
            total_gb, available_gb, used_gb = [b / (1024**3) for b in (total_bytes, available_bytes, used_bytes)]

            # Format the string
            disk_info = f"Disk (/): {used_gb:.1f}/{total_gb:.1f} GB ({available_gb:.1f} GB Free)"
            self.disk_space_label.setText(disk_info)
        except Exception as e:
            self.disk_space_label.setText("Disk: Error")
            print(f"Error getting disk space: {e}")


    def show_error(self, message):
        """Displays a critical error message box."""
        QMessageBox.critical(self, "Error", message)

    def closeEvent(self, event):
        """Handle closing the window, especially if an operation is running."""
        if self.current_worker and self.current_worker.isRunning():
            reply = QMessageBox.question(self, 'Confirm Exit',
                                         "An operation is currently in progress.\nExiting now may leave the system in an inconsistent state.\n\nExit anyway?",
                                         QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                                         QMessageBox.StandardButton.No) # Default to No
            if reply == QMessageBox.StandardButton.Yes:
                self.status_bar.showMessage("Exiting: Attempting to cancel operation...")
                self.cancel_operation()
                # Give the worker a very brief moment to terminate if possible
                if self.current_worker:
                    self.current_worker.wait(500) # Wait 0.5 sec
                event.accept() # Close the window
            else:
                event.ignore() # Don't close
        else:
            event.accept() # No operation running, close normally


# --- Main Execution ---
if __name__ == "__main__":
    # Check if running as root (generally discouraged for GUI apps)
    try:
        if hasattr(os, 'geteuid') and os.geteuid() == 0: # Check if geteuid exists (Unix-like)
            print("-" * 68)
            print(" WARNING: Running this GUI directly as root is not recommended! ")
            print(" Please run as a regular user. Privileged operations will use ")
            print(" 'pkexec' (PolicyKit) to ask for authentication when needed.  ")
            print("-" * 68)
            # Optionally, prevent startup or just warn
            # reply = QMessageBox.warning(None, "Run as Root Warning",
            #                             "Running this GUI directly as root is not recommended.\n"
            #                             "Privileged operations use 'pkexec'.\n\nContinue anyway?",
            #                             QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            #                             QMessageBox.StandardButton.No)
            # if reply == QMessageBox.StandardButton.No:
            #     sys.exit(1)

    except AttributeError: pass # os.geteuid doesn't exist on Windows

    app = QApplication(sys.argv)
    app.setStyle("Fusion") # Fusion style often looks better across platforms

    # Check essential commands needed for data loading
    missing_cmds = []
    for cmd in ['equery', 'eix', 'emerge']:
        if subprocess.run(['which', cmd], capture_output=True).returncode != 0:
            missing_cmds.append(cmd)

    if missing_cmds:
        QMessageBox.critical(None, "Missing Dependencies",
                             f"The following essential command(s) could not be found in PATH:\n\n"
                             f"- {', '.join(missing_cmds)}\n\n"
                             f"Please install them (e.g., app-portage/gentoolkit for equery, app-portage/eix for eix) and ensure they are in your system's PATH.\nThe application will now exit.")
        sys.exit(1)

    # Check for pkexec (needed for actions)
    if subprocess.run(['which', 'pkexec'], capture_output=True).returncode != 0:
         QMessageBox.warning(None, "Missing pkexec",
                              "The 'pkexec' command was not found.\nYou will likely be unable to perform actions like install, update, sync, or uninstall.\n\nPlease ensure PolicyKit is installed and configured.")
         # Allow running, but warn

    main_window = GentooPackageManagerGUI()
    main_window.show()
    sys.exit(app.exec())
