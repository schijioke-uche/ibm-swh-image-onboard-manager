#!/usr/bin/env bash
set -Eeuo pipefail
export START_TIME=$(date +%s)
export YEAR=$(date -u +%Y)
export RUN=200

# +----------------------------------------------------------------------------+
# | @Author : Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist                |
# | @Purpose: IBM Software Hub Enterprise Image Onboarding Manager             |
# | @Usage: Automate IBM SWH Enterprise images Generation List  for AirGap     |
# | @License: Proprietary                                                      |
# +----------------------------------------------------------------------------+

# xLaunchpad v4.3.5

#===============================================================================
GENERATE_STABLE="2.2.35"
DELETE_STABLE="1.1.9"
LAUNCH_ID="xLauncher-id-worker-call-$(date -u +%Y%m%dT%HZ)"
LAUNCH_NAME="IBM SWH Image Onboarding Management System - Enterprise AirGap Image List Onboarding Generator - Private Image List Manage User Launchpad"
LAUNCH_DESCRIPTION="This launchpad provides a user-friendly interface to generate an onboarding list for IBM Software Hub AirGap images based on user input"
ISWH_VERSION="4.3.5"
#===============================================================================

log() { printf '[INFO] %s\n' "$*"; }
success() { printf '[SUCCESS] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err() { printf '[ERROR] %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
export SCRIPT_NAME="${SCRIPT_NAME}"
export SCRIPT_DIR="${SCRIPT_DIR}"

SWH_VARS_FILE="${SCRIPT_DIR}/settings.sh"
export SWH_VARS_FILE="${SWH_VARS_FILE}"

if [[ ! -f "${SWH_VARS_FILE}" ]]; then
  printf '[ERROR] Required variables file not found: %s\n' "${SWH_VARS_FILE}" >&2
  exit 1
fi

if [[ ! -r "${SWH_VARS_FILE}" ]]; then
  printf '[ERROR] Required variables file is not readable: %s\n' "${SWH_VARS_FILE}" >&2
  exit 1
fi

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; MAGENTA=$'\033[35m'; CYAN=$'\033[36m'; WHITE=$'\033[37m'; BG_BLUE=$'\033[44m'
else
  RESET=""; BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; WHITE=""; BG_BLUE=""
  export NO_COLOR BOLD DIM RED GREEN YELLOW BLUE MAGENTA CYAN WHITE BG_BLUE RESET
fi

set -a
# shellcheck source=/dev/null
source "${SWH_VARS_FILE}"
set +a
#===============================================================================
# ------------------------------------------------------------------------------
# Guardrails:     [Do Not Edit]
# ------------------------------------------------------------------------------
guardrails() {
  if [[ "${LAUNCH_ID:-}" != xLauncher-id-worker-call-* ]]; then
    echo "[INFO] This script must be launched by User xLaunchpad." >&2
    exit 1
  fi
}
#===============================================================================
export GENERATE_STABLE="${GENERATE_STABLE}"
export DELETE_STABLE="${DELETE_STABLE}"
export LAUNCH_ID="${LAUNCH_ID}"
export LAUNCH_NAME="${LAUNCH_NAME}"
export LAUNCH_DESCRIPTION="${LAUNCH_DESCRIPTION}"
export ISWH_VERSION="${ISWH_VERSION}"
#================================================================================
# ------------------------------------------------------------------------------
# Client workstation:     
# ------------------------------------------------------------------------------
export CPD_CLI_MANAGE_WORKSPACE="${HOME}/swh-onboarding"
sudo mkdir -p "${CPD_CLI_MANAGE_WORKSPACE}"
sudo chmod -R 777 "${CPD_CLI_MANAGE_WORKSPACE}"
sudo chown -R "$(id -u):$(id -g)" "${CPD_CLI_MANAGE_WORKSPACE}"
#=============================================================================
#------------------------------------------------------------------------------
# Helper Links
#------------------------------------------------------------------------------
INSTALL_HELP_URL="https://github.com/IBM-Software-Hub/ibm-software-hub-cpd-cli-install"
COMPONENT_HELP_URL="https://www.ibm.com/docs/en/software-hub/5.3.x?topic=manage-component-ids"
LIST_IMAGES_DOC_URL="https://www.ibm.com/docs/en/software-hub/5.3.x?topic=manage-list-images"

#===============================================================================
# ------------------------------------------------------------------------------
pdf_utilities() {
  local required_cmds=("enscript" "ps2pdf")
  local missing_cmds=()
  local packages_to_install=()
  local cmd os_id os_name sudo_cmd pkg_manager

  log "Checking PDF utilities..."

  for cmd in "${required_cmds[@]}"; do
    log "Checking: $cmd"

    if command -v "$cmd" >/dev/null 2>&1; then
      type -a "$cmd" 2>/dev/null || true
      "$cmd" --version 2>&1 | head -n 2 || true
    else
      log "$cmd is NOT found"
      missing_cmds+=("$cmd")
    fi

    log ""
  done

  if [[ ${#missing_cmds[@]} -eq 0 ]]; then
    log "All PDF utilities are already installed."
    return 0
  fi

  sudo_cmd=""
  if [[ "$(id -u)" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo_cmd="sudo"
    else
      echo "ERROR: sudo is required to install missing packages." >&2
      return 1
    fi
  fi

  os_name="$(uname -s 2>/dev/null || echo unknown)"
  os_id=""

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id="${ID:-}"
  fi

  packages_to_install=()

  for cmd in "${missing_cmds[@]}"; do
    case "$cmd" in
      enscript)
        packages_to_install+=("enscript")
        ;;
      ps2pdf)
        # ps2pdf is provided by Ghostscript.
        packages_to_install+=("ghostscript")
        ;;
    esac
  done

  # Deduplicate package list.
  packages_to_install=($(printf '%s\n' "${packages_to_install[@]}" | awk '!seen[$0]++'))

  log "Missing utilities: ${missing_cmds[*]}"
  log "Packages to install: ${packages_to_install[*]}"
  log ""

  case "$os_name" in
    Darwin)
      log "Detected macOS."

      if ! command -v brew >/dev/null 2>&1; then
        err "Homebrew is required on macOS to install: ${packages_to_install[*]}"
        err "Install Homebrew first, then rerun this function."
        return 1
      fi

      brew install "${packages_to_install[@]}"
      ;;

    Linux)
      case "$os_id" in
        rhel)
          log "Detected RHEL."
          if command -v dnf >/dev/null 2>&1; then
            $sudo_cmd dnf install -y "${packages_to_install[@]}"
          elif command -v yum >/dev/null 2>&1; then
            $sudo_cmd yum install -y "${packages_to_install[@]}"
          else
            err "Neither dnf nor yum was found on RHEL."
            return 1
          fi
          ;;

        ubuntu)
          log "Detected Ubuntu."
          $sudo_cmd apt-get update
          $sudo_cmd apt-get install -y "${packages_to_install[@]}"
          ;;

        centos)
          log "Detected CentOS."
          if command -v dnf >/dev/null 2>&1; then
            $sudo_cmd dnf install -y "${packages_to_install[@]}"
          elif command -v yum >/dev/null 2>&1; then
            $sudo_cmd yum install -y "${packages_to_install[@]}"
          else
            err "Neither dnf nor yum was found on CentOS."
            return 1
          fi
          ;;

        fedora)
          log "Detected Fedora."
          $sudo_cmd dnf install -y "${packages_to_install[@]}"
          ;;

        *)
          err "Unsupported Linux OS ID: ${os_id:-unknown}"
          err "Install manually:"
          err "  enscript package provides: enscript"
          err "  ghostscript package provides: ps2pdf"
          return 1
          ;;
      esac
      ;;

    *)
      err "Unsupported OS: $os_name"
      return 1
      ;;
  esac

  log ""
  log "Rechecking PDF utilities after installation..."

  local still_missing=0

  for cmd in "${required_cmds[@]}"; do
    log "Checking: $cmd"

    if command -v "$cmd" >/dev/null 2>&1; then
      type -a "$cmd" 2>/dev/null || true
      "$cmd" --version 2>&1 | head -n 2 || true
    else
      err "$cmd is still NOT found after installation."
      still_missing=1
    fi

    log ""
  done

  if [[ "$still_missing" -ne 0 ]]; then
    err "One or more PDF utilities could not be installed."
    return 1
  fi

  log "PDF utilities are installed and ready."
  return 0
}


dos2unix() {
  local target_file="${1:-settings.sh}"
  local os_name=""
  local os_id=""
  local os_id_like=""
  local sudo_cmd=()

  printf 'Checking target file: %s\n' "$target_file"

  if [[ ! -f "$target_file" ]]; then
    printf 'ERROR: File not found: %s\n' "$target_file" >&2
    return 1
  fi

  if [[ "$(id -u)" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo_cmd=(sudo)
    else
      printf 'ERROR: sudo is required to install dos2unix.\n' >&2
      return 1
    fi
  fi

  os_name="$(uname -s 2>/dev/null || printf 'unknown')"

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id="${ID:-}"
    os_id_like="${ID_LIKE:-}"
  fi

  install_dos2unix_linux_rpm() {
    if command -v dnf >/dev/null 2>&1; then
      "${sudo_cmd[@]}" dnf install -y dos2unix
    elif command -v yum >/dev/null 2>&1; then
      "${sudo_cmd[@]}" yum install -y dos2unix
    else
      printf 'ERROR: neither dnf nor yum was found.\n' >&2
      return 1
    fi
  }

  install_dos2unix_ubuntu() {
    "${sudo_cmd[@]}" apt-get update
    "${sudo_cmd[@]}" apt-get install -y dos2unix
  }

  install_dos2unix_macos() {
    if ! command -v brew >/dev/null 2>&1; then
      printf 'ERROR: Homebrew is required on macOS to install dos2unix.\n' >&2
      printf 'Install Homebrew first, then rerun this function.\n' >&2
      return 1
    fi

    brew install dos2unix
  }

  if ! command -v dos2unix >/dev/null 2>&1; then
    printf 'dos2unix is not installed. Installing now...\n'

    case "$os_name" in
      Darwin)
        printf 'Detected macOS.\n'
        install_dos2unix_macos
        ;;

      Linux)
        case "$os_id" in
          rhel)
            printf 'Detected RHEL.\n'
            install_dos2unix_linux_rpm
            ;;
          ubuntu)
            printf 'Detected Ubuntu.\n'
            install_dos2unix_ubuntu
            ;;
          centos)
            printf 'Detected CentOS.\n'
            install_dos2unix_linux_rpm
            ;;
          fedora)
            printf 'Detected Fedora.\n'
            install_dos2unix_linux_rpm
            ;;
          *)
            if [[ "$os_id_like" == *"rhel"* || "$os_id_like" == *"fedora"* ]]; then
              printf 'Detected RHEL/Fedora-like Linux: %s\n' "${os_id:-unknown}"
              install_dos2unix_linux_rpm
            elif [[ "$os_id_like" == *"debian"* || "$os_id_like" == *"ubuntu"* ]]; then
              printf 'Detected Debian/Ubuntu-like Linux: %s\n' "${os_id:-unknown}"
              install_dos2unix_ubuntu
            else
              printf 'ERROR: unsupported Linux OS: %s\n' "${os_id:-unknown}" >&2
              return 1
            fi
            ;;
        esac
        ;;

      *)
        printf 'ERROR: unsupported OS: %s\n' "$os_name" >&2
        return 1
        ;;
    esac
  else
    printf 'dos2unix is already installed.\n'
  fi

  hash -r 2>/dev/null || true

  if ! command -v dos2unix >/dev/null 2>&1; then
    printf 'ERROR: dos2unix installation failed or command is still unavailable.\n' >&2
    return 1
  fi

  printf 'Converting %s to Unix LF line endings...\n' "$target_file"

  # Important:
  # The function is named dos2unix, so use "command dos2unix"
  # to call the real binary and avoid recursive function calls.
  command dos2unix "$target_file"

  chmod +x "$target_file"

  printf 'Conversion complete: %s\n' "$target_file"

  if grep -q $'\r' "$target_file"; then
    printf 'WARNING: carriage-return characters still found in %s\n' "$target_file" >&2
    return 1
  fi

  printf 'Validation passed: no CRLF carriage returns found.\n'
  return 0
}


