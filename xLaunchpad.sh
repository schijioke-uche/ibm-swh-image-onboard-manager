#!/usr/bin/env bash
set -Eeuo pipefail

# +----------------------------------------------------------------------------+
# | @Author : Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist                |
# | @Purpose: IBM Software Hub Enterprise Image Onboarding Manager             |
# | @Usage: User-friendly Launchpad to Generate IBM SWH AirGap Image List      |
# | @License: Proprietary                                                      |
# +----------------------------------------------------------------------------+

# xLaunchpad v4.3.5

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
source "${SCRIPT_DIR}/device-manager.sh"
#===============================================================================

rx_id() {
  local digits=""  # initialize.

  while [[ "${#digits}" -lt 7 ]]; do
    digits+="$(
      od -An -N16 -tu1 /dev/urandom \
        | awk '{
            for (i = 1; i <= NF; i++) {
              printf "%d", $i % 10
            }
          }'
    )"
  done

  digits="${digits:0:7}"
  IMAGE_LIST_ID="${digits}"
  export IMAGE_LIST_ID="${IMAGE_LIST_ID}"
}
rx_id

ONBOARD_WORKER="${SCRIPT_DIR}/ibm_swh_image_onboard_v${GENERATE_STABLE}.sh"
DELETE_WORKER="${SCRIPT_DIR}/delete_inprivate_registry_v${DELETE_STABLE}.sh"
sudo chmod +x "$ONBOARD_WORKER"
sudo chmod +x "$DELETE_WORKER"
export LAUNCH_ID="${LAUNCH_ID}"
export LAUNCH_NAME="${LAUNCH_NAME}"
export LAUNCH_DESCRIPTION="${LAUNCH_DESCRIPTION}"
export GENERATE_STABLE="${GENERATE_STABLE}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; MAGENTA=$'\033[35m'; CYAN=$'\033[36m'; WHITE=$'\033[37m'; BG_BLUE=$'\033[44m'
else
  RESET=""; BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; WHITE=""; BG_BLUE=""
fi

term_width() { tput cols 2>/dev/null || printf '100'; }
center() {
  local text="$1" width pad
  width="$(term_width)"
  pad=$(( (width - ${#text}) / 2 ))
  (( pad < 0 )) && pad=0
  printf '%*s%s\n' "$pad" '' "$text"
}
line() {
  local width
  width="$(term_width)"
  printf '%*s\n' "$width" '' | tr ' ' '_'
}

pause() { read -r -p "Press Enter to Return to Main Menu" _; }

banner() {
  clear 2>/dev/null || true
  printf '\n\n'
  center "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
 center "${CYAN}${BOLD}║     IBM Software Hub Image Onboarding Management System  v${ISWH_VERSION}      ║${RESET}"
  center "${CYAN}${BOLD}║               Enterprise and AirGap Image Dispatch                   ║${RESET}"
  center "${CYAN}${BOLD}║             Private Image List Manage User Launchpad                 ║${RESET}"
  center "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  printf '\n'
}

main_menu() {
  banner
  center "${GREEN}${BOLD}General Operations Main Menu${RESET}"
  printf '\n'
  center "${YELLOW}[1${RESET}] Generate IBM SWH AirGap Image List | ${YELLOW}[2${RESET}] Delete Images in Private Registry | ${YELLOW}[q${RESET}] Quit"
  printf '\n'
}

prompt_version() {
  local value
  while :; do
    read -r -p "$(printf '%s' "$BOLD What is the version of IBM Software Hub? [x.y.z or q]: $RESET")" value
    value="$(printf '%s' "$value" | tr -d '[:space:]')"
    case "$value" in
      q|Q) return 1 ;;
    esac
    if [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      VERSION="$value"
      export VERSION
      return 0
    fi
    printf '%sInvalid version format. Use x.y.z, for example 0.0.1%s\n' "$RED" "$RESET"
  done
}

prompt_patch_id() {
  local value
  while :; do
    read -r -p "$(printf '%s' "$BOLD Enter the SWH Patch/Hotfix ID [e.g., 0 or 1 or 2,3,4.. to infinity] [or q to Quit]: $RESET")" value
    case "$value" in
      q|Q) return 1 ;;
    esac
    if [[ -n "$(printf '%s' "$value" | tr -d '[:space:],')" ]]; then
      PATCH_ID="$value"
      export PATCH_ID
      return 0
    fi
    printf '%sPatch ID cannot be empty.%s\n' "$RED" "$RESET"
  done
}

prompt_components() {
  local value
  while :; do
    read -r -p "$(printf '%s' "$BOLD Paste the Comma-Separated Components ID List [or q to Quit]: $RESET")" value
    case "$value" in
      q|Q) return 1 ;;
    esac
    if [[ -n "$(printf '%s' "$value" | tr -d '[:space:],')" ]]; then
      COMPONENTS="$value"
      export COMPONENTS
      ALTERNATIVE_COMPONENTS="$value"
      export ALTERNATIVE_COMPONENTS
      return 0
    fi
    printf '%sComponents list cannot be empty.%s\n' "$RED" "$RESET"
  done
}

prompt_architecture() {
  local choice
  while :; do
    printf '\n'
    printf '%sSelect the System Architecture:%s\n' "$BOLD" "$RESET"
    printf '  %s1%s) amd64 (x86_64)\n' "$YELLOW" "$RESET"
    printf '  %s2%s) s390x\n' "$YELLOW" "$RESET"
    printf '  %s3%s) ppc64le\n' "$YELLOW" "$RESET"
    printf '  %sq%s) Quit\n' "$YELLOW" "$RESET"
    read -r -p "Selection [1/2/3/q]: " choice
    case "$choice" in
      1) ARCH="amd64"; export ARCH; return 0 ;;
      2) ARCH="s390x"; export ARCH; return 0 ;;
      3) ARCH="ppc64le"; export ARCH; return 0 ;;
      q|Q) return 1 ;;
      *) printf '%sInvalid selection.%s\n' "$RED" "$RESET" ;;
    esac
  done
}

duration() {
  STOP_TIME=$(date +%s)
  ELAPSED_TIME=$(( STOP_TIME - START_TIME ))
  if [[ "$RUN" -eq 200 ]]; then
    export START_TIME="$START_TIME"
    export ELAPSED_TIME="$ELAPSED_TIME"
    export STOP_TIME="$STOP_TIME"
    if (( ELAPSED_TIME < 60 )); then
      DURATION=$(printf "${ELAPSED_TIME} Seconds\n")
    elif (( ELAPSED_TIME < 120 )); then
      DURATION=$(printf "1 Minute and $(( ELAPSED_TIME - 60 )) Seconds\n")
    else
      DURATION=$(printf "$(( ELAPSED_TIME / 60 )) Minutes\n")
    fi
  else
    log "Type Determinant not recognized. Unable to provide summary."
  fi
}

onboard_operation() {
  banner
  center "${MAGENTA}${BOLD}Image Onboarding Setup${RESET}"
  printf '\n'

  # If VERSION is not set, prompt the user
  if [[ -z "$VERSION" ]]; then
    prompt_version || return 0
  fi
  # If COMPONENTS is not set, prompt the user
  if [[ -z "$COMPONENTS" ]]; then
    prompt_components || return 0
  fi
  # If ARCH is not set, prompt the user
  if [[ -z "$ARCH" ]]; then
    prompt_architecture || return 0
  fi
  # If PATCH_ID is not set, prompt the user
  if [[ -z "$PATCH_ID" ]]; then
    prompt_patch_id || return 0
  fi
  export IBM_SWH_IMAGE_ONBOARD_LAUNCHED_BY_XLAUNCHPAD=1

  printf '\n%sStarting enterprise airgap image onboarding list generation...%s\n' "$GREEN" "$RESET"
  printf '%sVersion:%s %s\n' "$BOLD" "$RESET" "$VERSION"
  printf '%sPatch ID:%s %s\n' "$BOLD" "$RESET" "${PATCH_ID:-N/A}"
  printf '%sComponents:%s %s\n' "$BOLD" "$RESET" "$COMPONENTS"
  printf '%sArchitecture:%s %s\n' "$BOLD" "$RESET" "$ARCH"
  printf '\n'

  if "$ONBOARD_WORKER"; then
    duration
    printf '\n'
    line
    printf '\n%sYour generated IBM Software Hub Image Onboarding list is located here:%s %s\n' "$GREEN$BOLD" "$RESET" "${CPD_CLI_MANAGE_WORKSPACE}"
    printf '%sYou can now onboard the images to the private registry for %s architecture.%s\n' "$GREEN" "$ARCH" "$RESET"
    printf '%sImage List ID: %s%s\n' "$GREEN" "$IMAGE_LIST_ID" "$RESET"
    printf '%sOperation completed in %s%s\n' "$GREEN" "$DURATION" "$RESET"
    printf '\n'
    line
    printf '\n'
  else
    printf '\n%sOperation failed. Review the messages above and retry.%s\n\n' "$RED" "$RESET"
  fi
  pause
}

delete_operation() {
  banner
  center "${MAGENTA}${BOLD}Delete Images in Private Registry${RESET}"
  printf '\n'
  read -r -p "$(printf '%sThis will delete all images in the private registry. Are you sure? [y/N]: %s' "$RED$BOLD" "$RESET")" confirm
  case "$confirm" in
    y|Y) ;;
    *) printf '%sOperation cancelled.%s\n' "$GREEN" "$RESET"; pause; return 0 ;;
  esac

  if [[ -f "${SCRIPT_DIR}/delete_inprivate_registry_v${DELETE_STABLE}.sh" ]]; then
    duration
    chmod +x "${SCRIPT_DIR}/delete_inprivate_registry_v${DELETE_STABLE}.sh"
    if bash "${SCRIPT_DIR}/delete_inprivate_registry_v${DELETE_STABLE}.sh"; then
      printf '\n%sAll images specified have been deleted successfully.%s\n' "$GREEN" "$RESET"
      printf '%sImage List ID: %s%s\n' "$GREEN" "$IMAGE_LIST_ID" "$RESET"
      printf '%sOperation completed in %s%s\n' "$GREEN" "$DURATION" "$RESET"
    else
      printf '\n%sFailed to delete images in the private registry. Check the script output for details.%s\n' "$RED" "$RESET"
    fi
  else
    printf '\n%sDelete script not found: %s%s\n' "$RED" "${SCRIPT_DIR}/delete_inprivate_registry_v${DELETE_STABLE}.sh" "$RESET"
  fi
  pause
}

main() {
  if [[ ! -x "$ONBOARD_WORKER" ]]; then
    printf '%sWorker script is missing or not executable: %s%s\n' "$RED" "$ONBOARD_WORKER" "$RESET" >&2
    exit 1
  fi

  while :; do
    main_menu
    read -r -p "Select one operation [1 - 2 or q]: " choice
    case "${choice:-}" in
      1) onboard_operation ;;
      2) delete_operation ;;
      q|Q) clear 2>/dev/null || true; printf '%sGoodbye - IBM Software Hub Image Manager ℠%s\n' "$GREEN" "$RESET"; exit 0 ;;
      *) printf '%sInvalid choice.%s\n' "$RED" "$RESET"; sleep 1 ;;
    esac
  done
}

main "$@"

