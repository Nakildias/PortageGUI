#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
# set -u # Uncomment if you want stricter variable checking
# Prevent errors in pipelines from being masked.
set -o pipefail

# --- Configuration ---
APP_NAME="PortageGUI"
PYTHON_SCRIPT_NAME="${APP_NAME}.py"
LAUNCHER_NAME="${APP_NAME}"
VENV_DIR="/opt/${APP_NAME}" # Installation directory for venv and script
VENV_PATH="${VENV_DIR}/venv"
LAUNCHER_PATH="/usr/local/bin/${LAUNCHER_NAME}" # Use /usr/local/bin for local installs
ALIAS_FILE="/etc/profile.d/portagegui.sh" # System-wide aliases

# --- Helper Functions ---
log_info() {
    echo "[INFO] $1"
}

log_warning() {
    echo "[WARN] $1" >&2
}

log_error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# --- Pre-flight Checks ---
log_info "Starting PortageGUI installation script..."

# 1. Check if running as root
if [[ "${EUID}" -ne 0 ]]; then
    log_error "This script must be run as root (or with sudo)."
fi

# 2. Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    log_error "python3 command not found. Please install Python 3."
fi
PYTHON3_EXEC=$(command -v python3)
log_info "Using Python 3 interpreter: ${PYTHON3_EXEC}"

# 3. Check if the Python script exists in the current directory
SCRIPT_SOURCE_PATH="$(pwd)/${PYTHON_SCRIPT_NAME}"
if [[ ! -f "${SCRIPT_SOURCE_PATH}" ]]; then
    log_error "Python script '${PYTHON_SCRIPT_NAME}' not found in the current directory ($(pwd))."
fi
log_info "Found Python script: ${SCRIPT_SOURCE_PATH}"

# --- Installation Steps ---

# 3. Install Gentoo dependencies (emerge)
#    - dev-python/pyqt6: For the GUI toolkit itself (Qt6 bindings)
#    - app-portage/gentoolkit: Provides 'equery' used in the script
#    - app-portage/eix: Provides 'eix' used in the script (alternative: could use only equery)
#    - sys-auth/polkit: Provides 'pkexec' for privilege escalation
log_info "Installing required Gentoo packages using emerge..."
log_info "This step requires user confirmation ('--ask')."
emerge --ask --verbose dev-python/pyqt6 app-portage/gentoolkit app-portage/eix sys-auth/polkit || log_error "Failed to install emerge dependencies."
log_info "Emerge dependencies should now be installed."

# 4. Configure Python for Qt6 (Handled by emerge dev-python/pyqt6)
log_info "Python configuration for PyQt6 is handled by the 'emerge dev-python/pyqt6' step."

# 5. Create application directory and venv
log_info "Creating application directory and Python virtual environment..."
if [[ -d "${VENV_DIR}" ]]; then
    log_warning "Installation directory '${VENV_DIR}' already exists. Skipping creation."
else
    mkdir -p "${VENV_DIR}" || log_error "Failed to create directory '${VENV_DIR}'."
    log_info "Created directory: ${VENV_DIR}"
fi

if [[ -d "${VENV_PATH}" ]]; then
    log_warning "Virtual environment '${VENV_PATH}' already exists. Skipping creation."
    # Optionally, you could offer to recreate it here.
else
    "${PYTHON3_EXEC}" -m venv "${VENV_PATH}" || log_error "Failed to create Python virtual environment at '${VENV_PATH}'."
    log_info "Created virtual environment: ${VENV_PATH}"
fi

# 6. Move Python script to the application directory
log_info "Copying Python script to ${VENV_DIR}..."
cp "${SCRIPT_SOURCE_PATH}" "${VENV_DIR}/${PYTHON_SCRIPT_NAME}" || log_error "Failed to copy Python script."
chmod 644 "${VENV_DIR}/${PYTHON_SCRIPT_NAME}" # Set standard read permissions

# 7. Install pip dependencies within the venv
log_info "Installing pip dependencies (ansi2html) into the virtual environment..."
# Activate venv is tricky in scripts, directly call the venv's python/pip
"${VENV_PATH}/bin/python" -m pip install --upgrade pip || log_warning "Failed to upgrade pip in venv. Continuing..."
"${VENV_PATH}/bin/python" -m pip install ansi2html || log_error "Failed to install pip dependencies in venv."
log_info "Pip dependencies installed."

# 1. Create and move the launcher script to /usr/local/bin
log_info "Creating launcher script at ${LAUNCHER_PATH}..."
# Use a 'here document' (EOF) to create the script content
cat > "${LAUNCHER_PATH}" << EOF
#!/bin/bash
# Launcher for PortageGUI

# Activate venv (alternative: directly call python)
# source "${VENV_PATH}/bin/activate"
# python "${VENV_DIR}/${PYTHON_SCRIPT_NAME}" "\$@"

# Direct execution with venv's python (often more reliable in scripts)
exec "${VENV_PATH}/bin/python" "${VENV_DIR}/${PYTHON_SCRIPT_NAME}" "\$@"

EOF

# 8. Make the launcher script executable
log_info "Making launcher script executable..."
chmod +x "${LAUNCHER_PATH}" || log_error "Failed to make launcher script executable."
log_info "Launcher script created and set as executable: ${LAUNCHER_PATH}"

# 2. Add aliases
log_info "Adding system-wide aliases to ${ALIAS_FILE}..."
# Create/overwrite the alias file
cat > "${ALIAS_FILE}" << EOF
# Aliases for PortageGUI
alias portagegui='${LAUNCHER_NAME}'
alias pgui='${LAUNCHER_NAME}'
EOF
chmod 644 "${ALIAS_FILE}" # Make it readable by all
log_info "Aliases 'portagegui' and 'pgui' created."
log_info "You may need to log out and log back in or run 'source ${ALIAS_FILE}' for aliases to take effect in your current shell."

# --- Final Steps ---
log_info ""
log_info "-----------------------------------------------------"
log_info " PortageGUI Installation Complete!"
log_info "-----------------------------------------------------"
log_info " - Dependencies installed via emerge."
log_info " - Virtual environment created at: ${VENV_PATH}"
log_info " - Python script installed at: ${VENV_DIR}/${PYTHON_SCRIPT_NAME}"
log_info " - Launcher installed at: ${LAUNCHER_PATH}"
log_info " - Aliases 'portagegui' and 'pgui' created in ${ALIAS_FILE}."
log_info ""
log_info "To run the application, you can now use:"
log_info "   ${LAUNCHER_NAME}"
log_info " or the aliases (after new login or sourcing profile):"
log_info "   portagegui"
log_info "   pgui"
log_info ""

exit 0
