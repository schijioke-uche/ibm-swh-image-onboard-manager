#!/usr/bin/env bash
set -Eeuo pipefail

# +----------------------------------------------------------------------------+
# | @Author : Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist                |
# | @Purpose: IBM Software Hub enterprise airgap private registry cleanup      |
# | @Usage: Automate IBM SWH Enterprise images Cleanup for AirGap              |
# | @License: Proprietary                                                      |
# +----------------------------------------------------------------------------+

# Delete Operations: v1.1.9

COLOR_ENABLED="${COLOR_ENABLED:-1}"
if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then COLOR_ENABLED=0; fi
if [[ "${COLOR_ENABLED}" == "1" ]]; then
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_MAGENTA=$'\033[35m'
  C_CYAN=$'\033[36m'
  C_WHITE=$'\033[37m'
  C_BOLD=$'\033[1m'
else
  C_RESET=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""; C_WHITE=""; C_BOLD=""
fi

log() { printf '%s[INFO]%s %s\n' "${C_CYAN}${C_BOLD}" "${C_RESET}" "$*"; }
success() { printf '%s[SUCCESS]%s %s\n' "${C_GREEN}${C_BOLD}" "${C_RESET}" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "${C_YELLOW}${C_BOLD}" "${C_RESET}" "$*" >&2; }
err() { printf '%s[ERROR]%s %s\n' "${C_RED}${C_BOLD}" "${C_RESET}" "$*" >&2; }
die() { err "$*"; exit 1; }

print_text_section() {
  local color="$1"
  shift
  local line
  echo
  for line in "$@"; do
    printf '%s%s%s\n' "${color}" "${line}" "${C_RESET}"
  done
}

print_plain_prompt() {
  local color="$1"
  shift
  printf '%s%s%s' "${color}" "$*" "${C_RESET}"
}

REGISTRY="${REGISTRY:-127.0.0.1:12443}"
PRIVATE_REGISTRY_LOCATION="${PRIVATE_REGISTRY_LOCATION:-${REGISTRY}}"
PRIVATE_REGISTRY_PUSH_USER="${PRIVATE_REGISTRY_PUSH_USER:-}"
PRIVATE_REGISTRY_PUSH_PASSWORD="${PRIVATE_REGISTRY_PUSH_PASSWORD:-}"
VERSION="${VERSION:-}"
RELEASE_TO_DELETE="${RELEASE_TO_DELETE:-${VERSION}}"
RELEASE_TO_KEEP="${RELEASE_TO_KEEP:-${DELETE_IMAGES_RELEASE_TO_KEEP:-}}"
COMPONENTS="${COMPONENTS:-}"
COMPONENTS_TO_SKIP="${COMPONENTS_TO_SKIP:-}"
export COMPONENTS_TO_SKIP
PREVIEW="${PREVIEW:-false}"
DRY_RUN="${DRY_RUN:-0}"
FORCE="${FORCE:-0}"
LOGIN_PRIVATE_REGISTRY="${LOGIN_PRIVATE_REGISTRY:-1}"
CPD_CLI_BIN="${CPD_CLI_BIN:-cpd-cli}"
OLM_UTILS_VERSION="${OLM_UTILS_VERSION:-v4}"
IBM_REGISTRY_PRIMARY="${IBM_REGISTRY_PRIMARY:-icr.io}"
OLM_UTILS_CONTAINER_NAME="${OLM_UTILS_CONTAINER_NAME:-olm-utils-play-${OLM_UTILS_VERSION}}"

# Security Addon:
CPD_CLI_MANAGE_WORKSPACE_DELETE_OPERATIONS="${HOME}/swh-image-normalizer"
export CPD_CLI_MANAGE_WORKSPACE_DELETE_OPERATIONS
CPD_CLI_MANAGE_WORKSPACE="${CPD_CLI_MANAGE_WORKSPACE_DELETE_OPERATIONS}"
export CPD_CLI_MANAGE_WORKSPACE

INSTALL_HELP_URL="https://github.com/IBM-Software-Hub/ibm-software-hub-cpd-cli-install"

term_cols() {
  local cols
  cols="${COLUMNS:-}"
  if [[ -z "${cols}" ]] && command -v tput >/dev/null 2>&1; then
    cols="$(tput cols 2>/dev/null || true)"
  fi
  if [[ -z "${cols}" || ! "${cols}" =~ ^[0-9]+$ || "${cols}" -lt 40 ]]; then
    cols=120
  fi
  printf '%s' "${cols}"
}

repeat_char() {
  local char="$1" count="$2"
  if (( count <= 0 )); then
    return 0
  fi
  local i
  for (( i=0; i<count; i++ )); do printf '%s' "${char}"; done
}

print_centered_text_to_fd() {
  local fd="$1"
  local color="$2"
  shift 2
  local text="$*" cols left_pad
  cols="$(term_cols)"
  left_pad=$(( (cols - ${#text}) / 2 ))
  (( left_pad < 0 )) && left_pad=0
  printf '%*s%s%s%s\n' "${left_pad}" '' "${color}" "${text}" "${C_RESET}" >&${fd}
}

print_centered_prompt() {
  local color="$1"
  shift
  local prompt="$*" cols left_pad
  cols="$(term_cols)"
  left_pad=$(( (cols - ${#prompt}) / 2 ))
  (( left_pad < 0 )) && left_pad=0
  printf '%*s%s%s%s' "${left_pad}" '' "${color}" "${prompt}" "${C_RESET}"
}

print_banner() {
  echo
  print_centered_text_to_fd 1 "${C_CYAN}${C_BOLD}" "IBM Software Hub Localhost Registry Image Delete Utility"
  print_centered_text_to_fd 1 "${C_CYAN}${C_BOLD}" "Delete Operations v1.1.9 - Dedicated Cleanup Workspace"
  print_centered_text_to_fd 1 "${C_CYAN}${C_BOLD}" "Target Registry: ${REGISTRY}"
  echo
}
usage() {
  cat <<USAGE
${SCRIPT_NAME} - delete IBM Software Hub images from localhost/intermediary registry

Default target:
  REGISTRY=127.0.0.1:12443

Production v1.1.9 behavior:
  Uses IBM Software Hub cpd-cli manage login-private-registry and delete-images.
  Uses a dedicated delete workspace: \${HOME}/delete-image-operations-only
  If RELEASE_TO_KEEP is not set, prompts interactively. If declined, exits 0 before delete-images because cpd-cli requires --release_to_keep.
  Repairs the OLM Utils /tmp/work mount through podman exec -u 0 before cpd-cli commands.
  Downloads CASE packages with cpd-cli manage case-download before delete-images.

Required:
  VERSION=<release-to-delete> or RELEASE_TO_DELETE=<release-to-delete>
  COMPONENTS=<comma-separated IBM Software Hub component IDs>

Optional:
  RELEASE_TO_KEEP=<release-to-keep-or-comma-separated-values>
  DELETE_IMAGES_RELEASE_TO_KEEP=<release-to-keep-or-comma-separated-values>

Examples:
  VERSION=5.3.1 RELEASE_TO_KEEP=5.3.0 COMPONENTS=cpd_platform,watsonx_orchestrate FORCE=1 ./${SCRIPT_NAME}
  RELEASE_TO_DELETE=5.3.1 COMPONENTS=cpd_platform DRY_RUN=1 ./${SCRIPT_NAME}

Optional registry login credentials:
  PRIVATE_REGISTRY_PUSH_USER=<user>
  PRIVATE_REGISTRY_PUSH_PASSWORD=<password-or-token>

Environment variables:
  REGISTRY                         Default: 127.0.0.1:12443
  PRIVATE_REGISTRY_LOCATION         Default: same as REGISTRY. Do not include http:// or https://
  PRIVATE_REGISTRY_PUSH_USER        Optional. Omit for unsecured localhost registry.
  PRIVATE_REGISTRY_PUSH_PASSWORD    Optional. Omit for unsecured localhost registry.
  VERSION                           Convenience alias for RELEASE_TO_DELETE
  RELEASE_TO_DELETE                 Required unless VERSION is set
  RELEASE_TO_KEEP                   Optional in settings.sh, but required at runtime by cpd-cli delete-images. If omitted, user is prompted; if declined, the script exits 0 without deleting.
  COMPONENTS                        Required comma-separated component IDs
  COMPONENTS_TO_SKIP                Optional comma-separated component IDs to skip during case-download
  PREVIEW                           true or false. Default: false
  DRY_RUN                           1 forces PREVIEW=true
  FORCE                             1 skips destructive confirmation when PREVIEW=false
  LOGIN_PRIVATE_REGISTRY            1 logs into registry first. Default: 1
  CPD_CLI_BIN                       cpd-cli binary path. Default: cpd-cli
  OLM_UTILS_VERSION                 Default: v4

IBM commands used:
  cpd-cli manage login-private-registry PRIVATE_REGISTRY_LOCATION [USER] [PASSWORD]
  cpd-cli manage delete-images --release_to_delete=... --release_to_keep=... --components=... --target_registry=... --preview=...
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then usage; exit 0; fi

normalize_bool_preview() {
  case "${DRY_RUN}" in
    1|true|TRUE|yes|YES) PREVIEW="true" ;;
  esac
  case "${PREVIEW}" in
    true|false) ;;
    1|yes|YES|TRUE) PREVIEW="true" ;;
    0|no|NO|FALSE) PREVIEW="false" ;;
    *) die "PREVIEW must be true or false. Got: ${PREVIEW}" ;;
  esac
}

trim() {
  local value="$*"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  printf '%s' "$value"
}

prompt_release_to_keep_if_missing() {
  if [[ -n "${RELEASE_TO_KEEP}" ]]; then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    warn "RELEASE_TO_KEEP is not set and no interactive terminal is available."
    warn "The installed cpd-cli requires --release_to_keep for delete-images."
    warn "No delete operation was performed. Set RELEASE_TO_KEEP in settings.sh or export it before running."
    exit 0
  fi

  print_text_section "${C_MAGENTA}${C_BOLD}" \
    "Release to Keep is Required by cpd-cli delete-images" \
    "We detected that RELEASE_TO_KEEP is not set." \
    "This delete operation targets release: ${RELEASE_TO_DELETE}" \
    "The real cpd-cli requires --release_to_keep; declining exits safely."
  print_plain_prompt "${C_CYAN}${C_BOLD}" "Do you wish to set RELEASE_TO_KEEP now? [y/N]: "

  local reply
  read -r reply
  echo
  reply="$(trim "$reply")"

  case "${reply}" in
    y|Y|yes|YES|Yes)
      while true; do
        print_text_section "${C_BLUE}${C_BOLD}" \
          "Enter release version(s) to keep." \
          "Use one value such as 5.3.0, or comma-separated values." \
          "Type q to quit without deleting."
        print_plain_prompt "${C_BLUE}${C_BOLD}" "RELEASE_TO_KEEP: "
        local keep_value
        read -r keep_value
        echo
        keep_value="$(trim "$keep_value")"
        case "${keep_value}" in
          q|Q|quit|QUIT|Quit)
            warn "No delete operation was performed. Set RELEASE_TO_KEEP in settings.sh and retry."
            exit 0
            ;;
        esac
        if [[ -z "${keep_value}" ]]; then
          warn "RELEASE_TO_KEEP cannot be empty because cpd-cli requires --release_to_keep."
          continue
        fi
        RELEASE_TO_KEEP="${keep_value}"
        export RELEASE_TO_KEEP
        success "RELEASE_TO_KEEP set to: ${RELEASE_TO_KEEP}"
        return 0
      done
      ;;
    *)
      warn "No delete operation was performed because RELEASE_TO_KEEP is required by cpd-cli delete-images."
      warn "Set RELEASE_TO_KEEP in settings.sh or rerun and answer y to provide it interactively."
      exit 0
      ;;
  esac
}

validate_release_to_keep_not_same_as_delete() {
  [[ -n "${RELEASE_TO_KEEP}" ]] || return 0

  local item clean
  IFS=',' read -r -a _keep_parts <<< "${RELEASE_TO_KEEP}"
  for item in "${_keep_parts[@]}"; do
    clean="$(trim "$item")"
    if [[ "${clean}" == "${RELEASE_TO_DELETE}" ]]; then
      die "Release to keep must be different from RELEASE_TO_DELETE. Got: RELEASE_TO_DELETE=${RELEASE_TO_DELETE} and RELEASE_TO_KEEP contains ${clean}"
    fi
  done
}

prepare_delete_workspace() {
  log "Preparing dedicated delete workspace: ${CPD_CLI_MANAGE_WORKSPACE}"

  mkdir -p "${CPD_CLI_MANAGE_WORKSPACE}"
  chown -R "$(id -u):$(id -g)" "${CPD_CLI_MANAGE_WORKSPACE}" 2>/dev/null || true
  chmod -R 777 "${CPD_CLI_MANAGE_WORKSPACE}" 2>/dev/null || true

  rm -rf "${CPD_CLI_MANAGE_WORKSPACE:?}/work" 2>/dev/null || true
  mkdir -p "${CPD_CLI_MANAGE_WORKSPACE}/work/offline"
  mkdir -p "${CPD_CLI_MANAGE_WORKSPACE}/work/offline/patch"
  mkdir -p "${CPD_CLI_MANAGE_WORKSPACE}/work/olm-utils-ansible-log"
  mkdir -p "${CPD_CLI_MANAGE_WORKSPACE}/work/.olm-utils"
  mkdir -p "${CPD_CLI_MANAGE_WORKSPACE}/work/cpfs_scripts"

  chown -R "$(id -u):$(id -g)" "${CPD_CLI_MANAGE_WORKSPACE}" 2>/dev/null || true
  chmod -R 777 "${CPD_CLI_MANAGE_WORKSPACE}" 2>/dev/null || true

  if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" != "Disabled" ]]; then
    chcon -Rt container_file_t "${CPD_CLI_MANAGE_WORKSPACE}" 2>/dev/null || true
  fi
}

pull_olm_utils_image() {
  local image="${IBM_REGISTRY_PRIMARY}/cpopen/cpd/olm-utils-${OLM_UTILS_VERSION}:${VERSION}"
  log "Pulling OLM Utils image: ${image}"
  podman pull "${image}" >/dev/null 2>&1 || die "Failed to pull ${image}"
  success "Pulled OLM Utils image: ${image}"
}

restart_olm_utils_container_if_possible() {
  log "Restarting OLM Utils container for delete workspace."
  "${CPD_CLI_BIN}" manage restart-container
}

fix_olm_utils_runtime_tmp_work_as_root() {
  : "${VERSION:?Set VERSION first}"
  : "${CPD_CLI_MANAGE_WORKSPACE:?Set CPD_CLI_MANAGE_WORKSPACE first}"

  local container_name="${OLM_UTILS_CONTAINER_NAME}"
  local expected_mount="${CPD_CLI_MANAGE_WORKSPACE}/work"
  local mounted_source=""
  local i

  log "Waiting for ${container_name} to be running..."

  for i in $(seq 1 30); do
    if podman ps --format '{{.Names}}' | grep -qx "${container_name}"; then
      break
    fi
    sleep 1
  done

  if ! podman ps --format '{{.Names}}' | grep -qx "${container_name}"; then
    die "${container_name} is not running. Runtime /tmp/work repair cannot continue."
  fi

  mounted_source="$(
    podman inspect "${container_name}" \
      --format '{{range .Mounts}}{{if eq .Destination "/tmp/work"}}{{.Source}}{{end}}{{end}}'
  )"

  if [[ "${mounted_source}" != "${expected_mount}" ]]; then
    err "Wrong /tmp/work mount."
    err "Current:  ${mounted_source}"
    err "Expected: ${expected_mount}"
    exit 1
  fi

  log "/tmp/work mount verified: ${mounted_source}"
  log "Running mandatory delete-workspace root repair inside ${container_name}: podman exec -u 0"

  podman exec -u 0 "${container_name}" sh -s -- "${VERSION}" <<'EOF'
set -eu

mkdir -p /tmp/work
mkdir -p /tmp/work/offline
mkdir -p /tmp/work/offline/patch
mkdir -p /tmp/work/olm-utils-ansible-log
mkdir -p /tmp/work/.olm-utils
mkdir -p /tmp/work/cpfs_scripts

chown -R 1001:0 /tmp/work
chmod -R 777 /tmp/work

ls -ld /tmp/work
ls -ld /tmp/work/offline
ls -ld /tmp/work/offline/patch
ls -ld /tmp/work/olm-utils-ansible-log
ls -ld /tmp/work/.olm-utils
ls -ld /tmp/work/cpfs_scripts
EOF

  log "Verifying ansible UID 1001 can write to delete workspace /tmp/work..."
  podman exec -u 1001:0 "${container_name}" sh -s -- "${VERSION}" <<'EOF'
set -eu

touch /tmp/work/olm-utils-ansible-log/.delete-write-test
chmod 777 /tmp/work/olm-utils-ansible-log/.delete-write-test
rm -f /tmp/work/olm-utils-ansible-log/.delete-write-test

mkdir -p /tmp/work/offline/.delete-parent-write-test-dir
touch /tmp/work/offline/.delete-parent-write-test-file
chmod 777 /tmp/work/offline
chmod 777 /tmp/work/offline/.delete-parent-write-test-dir
chmod 777 /tmp/work/offline/.delete-parent-write-test-file
rm -rf /tmp/work/offline/.delete-parent-write-test-dir
rm -f /tmp/work/offline/.delete-parent-write-test-file

echo "[INFO] UID 1001 can write logs and create children under /tmp/work/offline for delete-images."
EOF

  success "Runtime /tmp/work repair completed for delete workspace."
}

get_case() {
  : "${VERSION:?Set VERSION first}"
  : "${COMPONENTS:?Set COMPONENTS first}"

  log "Downloading CASE packages required by cpd-cli delete-images."
  log "CASE release to delete: ${VERSION}"
  log "COMPONENTS=${COMPONENTS}"
  log "COMPONENTS_TO_SKIP=${COMPONENTS_TO_SKIP:-<none>}"

  "${CPD_CLI_BIN}" manage case-download \
    --components="${COMPONENTS}" \
    --skip_components="${COMPONENTS_TO_SKIP}" \
    --release="${VERSION}"

  if [[ -n "${RELEASE_TO_KEEP:-}" ]]; then
    local keep_release clean_keep
    IFS=',' read -r -a _case_keep_parts <<< "${RELEASE_TO_KEEP}"
    for keep_release in "${_case_keep_parts[@]}"; do
      clean_keep="$(trim "${keep_release}")"
      [[ -z "${clean_keep}" ]] && continue
      if [[ "${clean_keep}" == "${VERSION}" ]]; then
        continue
      fi
      log "Downloading CASE packages required for release_to_keep=${clean_keep}."
      "${CPD_CLI_BIN}" manage case-download \
        --components="${COMPONENTS}" \
        --skip_components="${COMPONENTS_TO_SKIP}" \
        --release="${clean_keep}"
    done
  fi

  success "Required CASE package download step completed."
}

prepare_cpd_cli_delete_runtime() {
  prepare_delete_workspace
  pull_olm_utils_image
  restart_olm_utils_container_if_possible
  fix_olm_utils_runtime_tmp_work_as_root
  get_case
}

validate_inputs() {
  command -v "${CPD_CLI_BIN}" >/dev/null 2>&1 || die "${CPD_CLI_BIN} is required and was not found in PATH. Install from: ${INSTALL_HELP_URL}"
  command -v podman >/dev/null 2>&1 || die "podman is required and was not found in PATH."
  [[ -n "${PRIVATE_REGISTRY_LOCATION}" ]] || die "PRIVATE_REGISTRY_LOCATION/REGISTRY is required."
  [[ "${PRIVATE_REGISTRY_LOCATION}" != http://* && "${PRIVATE_REGISTRY_LOCATION}" != https://* ]] || die "PRIVATE_REGISTRY_LOCATION must not include http:// or https://. Got: ${PRIVATE_REGISTRY_LOCATION}"
  [[ -n "${RELEASE_TO_DELETE}" ]] || die "Set VERSION or RELEASE_TO_DELETE first."
  [[ -n "${COMPONENTS}" ]] || die "COMPONENTS is required. Example: COMPONENTS=cpd_platform,watsonx_orchestrate"

  prompt_release_to_keep_if_missing
  validate_release_to_keep_not_same_as_delete
  normalize_bool_preview
}

confirm_delete() {
  if [[ "${PREVIEW}" == "true" || "${FORCE}" == "1" ]]; then return 0; fi
  if [[ ! -t 0 ]]; then die "Refusing destructive delete without confirmation. Use FORCE=1 or PREVIEW=true."; fi
  local _keep_display
  if [[ -n "${RELEASE_TO_KEEP}" ]]; then
    _keep_display="${RELEASE_TO_KEEP}"
  else
    _keep_display="<not set>"
  fi
  print_text_section "${C_YELLOW}${C_BOLD}" \
    "Destructive Delete Confirmation" \
    "Registry: ${PRIVATE_REGISTRY_LOCATION}" \
    "Release to delete: ${RELEASE_TO_DELETE}" \
    "Release to keep: ${_keep_display}" \
    "Components: ${COMPONENTS}"
  print_plain_prompt "${C_RED}${C_BOLD}" "Type DELETE to continue: "
  local reply
  read -r reply
  echo
  [[ "${reply}" == "DELETE" ]] || die "Confirmation not received. Nothing deleted."
}

login_private_registry_if_requested() {
  if [[ "${LOGIN_PRIVATE_REGISTRY}" != "1" ]]; then
    log "Skipping cpd-cli login-private-registry because LOGIN_PRIVATE_REGISTRY=${LOGIN_PRIVATE_REGISTRY}."
    return 0
  fi

  log "Logging in to private/intermediary registry: ${PRIVATE_REGISTRY_LOCATION}"
  if [[ -n "${PRIVATE_REGISTRY_PUSH_USER}" || -n "${PRIVATE_REGISTRY_PUSH_PASSWORD}" ]]; then
    "${CPD_CLI_BIN}" manage login-private-registry \
      "${PRIVATE_REGISTRY_LOCATION}" \
      "${PRIVATE_REGISTRY_PUSH_USER}" \
      "${PRIVATE_REGISTRY_PUSH_PASSWORD}"
  else
    "${CPD_CLI_BIN}" manage login-private-registry \
      "${PRIVATE_REGISTRY_LOCATION}"
  fi
  success "login-private-registry completed."
}

run_delete_images() {
  log "Deleting IBM Software Hub images using cpd-cli manage delete-images."
  log "RELEASE_TO_DELETE=${RELEASE_TO_DELETE}"
  log "RELEASE_TO_KEEP=${RELEASE_TO_KEEP}"
  log "COMPONENTS=${COMPONENTS}"
  log "TARGET_REGISTRY=${PRIVATE_REGISTRY_LOCATION}"
  log "PREVIEW=${PREVIEW}"

  local cmd=("${CPD_CLI_BIN}" manage delete-images
    --release_to_delete="${RELEASE_TO_DELETE}"
    --release_to_keep="${RELEASE_TO_KEEP}"
    --components="${COMPONENTS}"
    --target_registry="${PRIVATE_REGISTRY_LOCATION}"
    --preview="${PREVIEW}")

  log "Running delete-images with required release_to_keep=${RELEASE_TO_KEEP}"
  "${cmd[@]}"

  if [[ "${PREVIEW}" == "true" ]]; then
    success "delete-images preview completed. No images were deleted."
  else
    success "delete-images completed for registry ${PRIVATE_REGISTRY_LOCATION}."
    printf '%sAll requested images in the private registry have been deleted successfully.%s\n' "${C_GREEN}${C_BOLD}" "${C_RESET}"
  fi
}

delete() {
  print_banner
  validate_inputs
  confirm_delete
  prepare_cpd_cli_delete_runtime
  login_private_registry_if_requested
  fix_olm_utils_runtime_tmp_work_as_root
  run_delete_images
  DELETE_COMPLETED=1
  export DELETE_COMPLETED
}

delete "$@"
