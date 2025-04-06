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
# Standard location for optional software packages
INSTALL_BASE_DIR="/opt"
VENV_DIR="${INSTALL_BASE_DIR}/${APP_NAME}" # Installation directory for venv and script
VENV_PATH="${VENV_DIR}/venv"
# Use /usr/local/bin for locally installed executables/scripts
LAUNCHER_PATH="/usr/local/bin/${LAUNCHER_NAME}"
# Standard location for system-wide shell configuration snippets
ALIAS_FILE="/etc/profile.d/${APP_NAME,,}.sh" # Use lowercase name for convention

# --- Helper Functions ---
log_info() {
    echo "[INFO] $1"
}

log_warning() {
    # Output warnings to standard error
    echo "[WARN] $1" >&2
}

log_error() {
    # Output errors to standard error and exit
    echo "[ERROR] $1" >&2
    exit 1
}

# --- Pre-flight Checks ---
log_info "Starting ${APP_NAME} installation script..."

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

# 4. Install/Update Gentoo system dependencies (emerge)
#    - Uses --update --deep --newuse (-uDN) to only install/update missing,
#      outdated, or packages with changed USE flags. Prevents reinstalling
#      already up-to-date packages.
#    - dev-python/pyqt6: Provides Qt6 bindings AND ensures system Qt6 libs are present.
#                        *** Using emerge is strongly recommended over pip for PyQt6 on Gentoo. ***
#    - app-portage/gentoolkit: Provides 'equery' (often used in Portage helper scripts).
#    - app-portage/eix: Provides 'eix' (optional alternative/addition to equery).
#    - sys-auth/polkit: Provides 'pkexec' for running commands as root from the GUI.
log_info "Ensuring required Gentoo packages are installed/updated using emerge..."
log_info "This step requires user confirmation ('--ask'). Dependencies: dev-python/pyqt6, app-portage/gentoolkit, app-portage/eix, sys-auth/polkit"
# Use --update --deep --newuse (-uDN) to avoid reinstalling packages already installed and up-to-date
emerge --ask --verbose --update --deep --newuse dev-python/pyqt6 app-portage/gentoolkit app-portage/eix sys-auth/polkit || log_error "Failed to install/update emerge dependencies. Check emerge output for details."
log_info "Emerge dependency check/installation command finished."

# 5. Create application directory and Python virtual environment
log_info "Setting up application directory and Python virtual environment..."
if [[ -d "${VENV_DIR}" ]]; then
    log_warning "Installation directory '${VENV_DIR}' already exists. Contents may be overwritten."
else
    mkdir -p "${VENV_DIR}" || log_error "Failed to create directory '${VENV_DIR}'."
    log_info "Created application directory: ${VENV_DIR}"
fi

# Ensure VENV_PATH doesn't exist or remove it if user confirms (optional safety)
# if [[ -d "${VENV_PATH}" ]]; then
#   read -p "[WARN] Virtual environment '${VENV_PATH}' already exists. Remove and recreate? (y/N): " confirm
#   if [[ "${confirm}" =~ ^[Yy]$ ]]; then
#       log_info "Removing existing virtual environment..."
#       rm -rf "${VENV_PATH}" || log_error "Failed to remove existing venv."
#   else
#       log_warning "Keeping existing virtual environment. Pip dependencies might not be correct."
#       # Skip venv creation if kept? Or force install deps? Depends on desired behavior.
#       # Forcing install is safer if we keep the existing venv.
#   fi
# fi

# Create venv if it doesn't exist (or after removal)
if [[ ! -d "${VENV_PATH}" ]]; then
    log_info "Creating Python virtual environment at '${VENV_PATH}'..."
    "${PYTHON3_EXEC}" -m venv "${VENV_PATH}" || log_error "Failed to create Python virtual environment."
    log_info "Virtual environment created."
else
    log_info "Virtual environment '${VENV_PATH}' already exists. Skipping creation."
fi

# 6. Copy Python script to the application directory
log_info "Copying Python script to ${VENV_DIR}..."
cp -p "${SCRIPT_SOURCE_PATH}" "${VENV_DIR}/${PYTHON_SCRIPT_NAME}" || log_error "Failed to copy Python script."
# -p preserves permissions, but let's ensure owner/group/perms are reasonable anyway
chown root:root "${VENV_DIR}/${PYTHON_SCRIPT_NAME}"
chmod 644 "${VENV_DIR}/${PYTHON_SCRIPT_NAME}" # Read for all, write for owner (root)
log_info "Python script copied."

# 7. Install pip dependencies within the virtual environment
log_info "Installing pip dependencies (ansi2html) into the virtual environment..."
# Activate venv is tricky in scripts; directly call the venv's python/pip instead.
# Ensure pip is up-to-date within the venv
"${VENV_PATH}/bin/python" -m pip install --upgrade pip || log_warning "Failed to upgrade pip in venv. Continuing..."
# Install required packages
# Note: PyQt6 should ideally be handled by emerge on Gentoo (done in step 4)
"${VENV_PATH}/bin/python" -m pip install ansi2html || log_error "Failed to install pip dependencies (ansi2html) in venv."
log_info "Pip dependencies installed within the virtual environment."

# 8. Create the launcher script in /usr/local/bin
log_info "Creating launcher script at ${LAUNCHER_PATH}..."
# Use a 'here document' (EOF) to create the script content.
# Using 'exec' replaces the shell process with the Python process.
cat > "${LAUNCHER_PATH}" << EOF
#!/bin/bash
# Launcher for ${APP_NAME}
# Executes the application using its dedicated virtual environment Python interpreter.

VENV_PYTHON="${VENV_PATH}/bin/python"
APP_SCRIPT="${VENV_DIR}/${PYTHON_SCRIPT_NAME}"

# Check if Python interpreter exists
if [[ ! -x "\${VENV_PYTHON}" ]]; then
  echo "[ERROR] Python interpreter not found or not executable: \${VENV_PYTHON}" >&2
  exit 1
fi

# Check if App script exists
if [[ ! -f "\${APP_SCRIPT}" ]]; then
  echo "[ERROR] Application script not found: \${APP_SCRIPT}" >&2
  exit 1
fi

# Use exec to replace the bash script process with the Python process
# Pass all command-line arguments ("\$@") to the Python script
exec "\${VENV_PYTHON}" "\${APP_SCRIPT}" "\$@"

EOF

# 9. Make the launcher script executable
log_info "Making launcher script executable..."
chmod 755 "${LAUNCHER_PATH}" || log_error "Failed to make launcher script executable."
# Ensure ownership is root, as it's in /usr/local/bin
chown root:root "${LAUNCHER_PATH}"
log_info "Launcher script created and set as executable: ${LAUNCHER_PATH}"

# 10. Create system-wide aliases
log_info "Adding system-wide aliases to ${ALIAS_FILE}..."
# Create/overwrite the alias file. Using the full path to the launcher is robust.
cat > "${ALIAS_FILE}" << EOF
# Aliases for ${APP_NAME}
# Generated by installation script on $(date)

alias portagegui='${LAUNCHER_PATH}'
alias pgui='${LAUNCHER_PATH}'

EOF
chmod 644 "${ALIAS_FILE}" # Make it readable by all users
chown root:root "${ALIAS_FILE}"
log_info "Aliases 'portagegui' and 'pgui' defined in ${ALIAS_FILE}."
log_warning "IMPORTANT: For the new aliases to work, you must either:"
log_warning "  a) Log out and log back in."
log_warning "  b) Manually source the file in your current shell: source ${ALIAS_FILE}"

# --- Final Steps ---
log_info ""
log_info "-----------------------------------------------------"
log_info " ${APP_NAME} Installation Complete!"
log_info "-----------------------------------------------------"
log_info " - System dependencies checked/installed/updated via emerge (including PyQt6)."
log_info " - Virtual environment setup at: ${VENV_PATH}"
log_info " - App script installed at: ${VENV_DIR}/${PYTHON_SCRIPT_NAME}"
log_info " - Pip dependencies (ansi2html) installed in venv."
log_info " - Launcher installed at: ${LAUNCHER_PATH}"
log_info " - Aliases ('portagegui', 'pgui') created in: ${ALIAS_FILE}"
log_info ""
log_info "To run the application, you can now use the command:"
log_info "   ${LAUNCHER_NAME}"
log_info ""
log_info "Or, AFTER starting a new login shell (or sourcing ${ALIAS_FILE}), use the aliases:"
log_info "   portagegui"
log_info "   pgui"
log_info ""

exit 0
