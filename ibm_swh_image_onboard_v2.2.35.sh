#!/usr/bin/env bash

# +----------------------------------------------------------------------------+
# | @Author : Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist                |
# | @Purpose: IBM Software Hub Enterprise Image Onboarding Manager             |
# | @Usage: Automate IBM SWH Enterprise images Generation List  for AirGap     |
# | @License: Proprietary                                                      |
# +----------------------------------------------------------------------------+

# Onboarding v2.2.35 - 2026-06-06

#===============================================================================
source "${SCRIPT_DIR}/device-manager.sh"
guardrails
: "${VERSION:?VERSION is required.}"
: "${CPD_CLI_MANAGE_WORKSPACE:?CPD_CLI_MANAGE_WORKSPACE is required.}"
: "${COMPONENTS:?COMPONENTS is required.}"
: "${IMAGE_ARCH:?IMAGE_ARCH is required.}"
: "${IBM_ENTITLEMENT_KEY:?IBM_ENTITLEMENT_KEY is required.}"
: "${IBM_IAM_APIKEY:?IBM_IAM_APIKEY is required.}"
: "${IBM_REGISTRY_PRIMARY:?IBM_REGISTRY_PRIMARY is required.}"
: "${IBM_REGISTRY_PRIMARY_USER:?IBM_REGISTRY_PRIMARY_USER is required.}"
: "${IBM_REGISTRY_SUBDOMAIN:?IBM_REGISTRY_SUBDOMAIN is required.}"
: "${IBM_REGISTRY_SUBDOMAIN_USER:?IBM_REGISTRY_SUBDOMAIN_USER is required.}"

COMPONENTS_TO_SKIP="${COMPONENTS_TO_SKIP:-}"
export COMPONENTS_TO_SKIP

swh_release_version() {
  local cpd_cli_version_output=""

  SWH_RELEASE_VERSION="unset"
  export SWH_RELEASE_VERSION

  if ! command -v cpd-cli >/dev/null 2>&1; then
    log "SWH CLI is not installed"
    return 1
  fi

  cpd_cli_version_output="$(cpd-cli version 2>/dev/null || true)"

  SWH_RELEASE_VERSION="$(
    printf '%s\n' "${cpd_cli_version_output}" \
      | awk '/SWH Release Version:/ {
          for (i = 1; i <= NF; i++) {
            if ($i ~ /^[0-9]+(\.[0-9]+)+$/) {
              print $i
              exit
            }
          }
        }'
  )"

  if [[ -n "${SWH_RELEASE_VERSION}" && "${SWH_RELEASE_VERSION}" != "unset" ]]; then
    export SWH_RELEASE_VERSION="${SWH_RELEASE_VERSION}"
    log " SWH Release Version Installed is: ${SWH_RELEASE_VERSION}"
    : "${VERSION:?VERSION is required.}"
    if [[ "${SWH_RELEASE_VERSION}" != "${VERSION}" ]]; then
      err "SWH Release Version mismatch. Installed SWH Release Version Detected: ${SWH_RELEASE_VERSION}, Expected: ${VERSION}."
      err "Ensure the correct cpd-cli version is installed for this onboarding script."
      err "Upgrade or Downgrade by going here: https://github.com/IBM-Software-Hub/ibm-software-hub-cpd-cli-install"
      exit 1
    fi
    return 0
  fi

  if [[ "${SWH_RELEASE_VERSION}" == "unset" ]]; then
    export SWH_RELEASE_VERSION="${SWH_RELEASE_VERSION}"
    log "SWH CLI is not installed."
    log "Install it using this: https://github.com/IBM-Software-Hub/ibm-software-hub-cpd-cli-install"
    return 1
  fi
}
swh_release_version

# Preserve IBM Software Hub release value separately from workstation OS metadata.
# Linux /etc/os-release commonly defines VERSION="...".  The onboarding
# VERSION must always remain the IBM Software Hub release from settings.sh.
IBM_SOFTWARE_HUB_VERSION="${VERSION}"
export IBM_SOFTWARE_HUB_VERSION

validate_software_hub_version() {
  if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "VERSION must remain the IBM Software Hub release in x.y.z format. Current value: ${VERSION}."
  fi
}

assert_software_hub_version_sacred() {
  if [[ "${VERSION}" != "${IBM_SOFTWARE_HUB_VERSION}" ]]; then
    die "VERSION is sacred and must not be overwritten. Expected IBM Software Hub VERSION=${IBM_SOFTWARE_HUB_VERSION}, but current VERSION=${VERSION}. Store workstation OS release data in OS_WORKSTATION_VERSION only."
  fi
}

############################################################################

#||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
#||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
#||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
#||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
#            [AUTHENTICATION AND WORKSPACE PREPARATION BEGINS]

fix_olm_utils_runtime_tmp_work_as_root() {
  : "${VERSION:?Set VERSION first}"
  : "${CPD_CLI_MANAGE_WORKSPACE:?Set CPD_CLI_MANAGE_WORKSPACE first}"

  local mode="${1:-runtime}"
  local container_name="${OLM_UTILS_CONTAINER_NAME:-olm-utils-play-v4}"
  local expected_mount="${CPD_CLI_MANAGE_WORKSPACE}/work"
  local mounted_source=""
  local i

  echo "[INFO] Waiting for ${container_name} to be running..."

  for i in $(seq 1 30); do
    if "${CONTAINER_EXE}" ps --format '{{.Names}}' | grep -qx "${container_name}"; then
      break
    fi
    sleep 1
  done

  if ! "${CONTAINER_EXE}" ps --format '{{.Names}}' | grep -qx "${container_name}"; then
    echo "[ERROR] ${container_name} is not running. Runtime /tmp/work repair cannot continue." >&2
    return 1
  fi

  mounted_source="$(
    "${CONTAINER_EXE}" inspect "${container_name}" \
      --format '{{range .Mounts}}{{if eq .Destination "/tmp/work"}}{{.Source}}{{end}}{{end}}'
  )"

  if [[ "${mounted_source}" != "${expected_mount}" ]]; then
    echo "[ERROR] Wrong /tmp/work mount." >&2
    echo "[ERROR] Current:  ${mounted_source}" >&2
    echo "[ERROR] Expected: ${expected_mount}" >&2
    return 1
  fi

  echo "[INFO] /tmp/work mount verified: ${mounted_source}"
  echo "[INFO] Running mandatory root repair inside ${container_name}: ${CONTAINER_EXE} exec -u 0"
  echo "[INFO] Runtime repair mode: ${mode}"

  "${CONTAINER_EXE}" exec -u 0 "${container_name}" sh -s -- "${VERSION}" "${mode}" <<'EOF_ROOT_FIX'
set -eu

version="$1"
mode="$2"

echo "[INFO] Runtime root identity:"
id

echo "[INFO] Creating required /tmp/work base structure..."
mkdir -p /tmp/work
mkdir -p /tmp/work/offline
mkdir -p /tmp/work/offline/patch
mkdir -p /tmp/work/olm-utils-ansible-log
mkdir -p /tmp/work/.olm-utils
mkdir -p /tmp/work/cpfs_scripts

# Important: IBM Software Hub list-images Ansible owns creation of
# /tmp/work/offline/${version}. If the script pre-creates that version
# directory, Ansible's file module can later fail while trying to set mode on
# the bind-mounted directory. Immediately before list-images, remove only that
# release directory and let Ansible recreate it as uid 1001.
if [ "${mode}" = "pre-list-images" ]; then
  rm -rf "/tmp/work/offline/${version}"
fi

echo "[INFO] Applying runtime ownership and permissions to /tmp/work base paths..."
chown -R 1001:0 /tmp/work
chmod -R 777 /tmp/work

echo "[INFO] Runtime /tmp/work state after root repair:"
ls -ld /tmp/work
ls -ld /tmp/work/offline
ls -ld /tmp/work/offline/patch
ls -ld /tmp/work/olm-utils-ansible-log
ls -ld /tmp/work/.olm-utils
ls -ld /tmp/work/cpfs_scripts
if [ -d "/tmp/work/offline/${version}" ]; then
  ls -ld "/tmp/work/offline/${version}"
else
  echo "[INFO] /tmp/work/offline/${version} intentionally absent; list-images will create it."
fi
EOF_ROOT_FIX

  echo "[INFO] Verifying ansible UID 1001 can write to /tmp/work base paths..."

  "${CONTAINER_EXE}" exec -u 1001:0 "${container_name}" sh -s -- "${VERSION}" <<'EOF_ANSIBLE_FIX'
set -eu

version="$1"

id

touch /tmp/work/olm-utils-ansible-log/.ansible-write-test
chmod 777 /tmp/work/olm-utils-ansible-log/.ansible-write-test
rm -f /tmp/work/olm-utils-ansible-log/.ansible-write-test

mkdir -p /tmp/work/offline/.ansible-parent-write-test-dir
touch /tmp/work/offline/.ansible-parent-write-test-file
chmod 777 /tmp/work/offline
chmod 777 /tmp/work/offline/.ansible-parent-write-test-dir
chmod 777 /tmp/work/offline/.ansible-parent-write-test-file
rm -rf /tmp/work/offline/.ansible-parent-write-test-dir
rm -f /tmp/work/offline/.ansible-parent-write-test-file

echo "[INFO] UID 1001 can write logs and create children under /tmp/work/offline."
EOF_ANSIBLE_FIX

  echo "[INFO] Runtime /tmp/work repair completed successfully."
  echo
}

# ------------------------------------------------------------------------------
# Workstation OS Detection and Workspace Policy: Onboarding v2.2.35
# ------------------------------------------------------------------------------
read_os_release_value() {
  local key="$1" file="$2" value=""
  if [[ -f "${file}" ]]; then
    value="$(awk -F= -v key="${key}" '
      $1 == key {
        value=$2
        gsub(/^"|"$/, "", value)
        print value
        exit
      }
    ' "${file}" 2>/dev/null || true)"
  fi
  printf '%s' "${value}"
}

detect_workstation_os() {
  # Never source /etc/os-release here. It can define VERSION=... and overwrite
  # the IBM Software Hub VERSION variable.  Store workstation OS metadata in
  # OS_WORKSTATION_VERSION and WORKSTATION_* variables only.
  WORKSTATION_KERNEL="$(uname -s 2>/dev/null || printf 'unknown')"
  WORKSTATION_OS_ID="unknown"
  OS_WORKSTATION_VERSION="unknown"
  WORKSTATION_OS_VERSION_ID="${OS_WORKSTATION_VERSION}"
  WORKSTATION_OS_FAMILY="linux"

  case "${WORKSTATION_KERNEL}" in
    Darwin)
      WORKSTATION_OS_ID="macos"
      WORKSTATION_OS_FAMILY="macos"
      OS_WORKSTATION_VERSION="$(sw_vers -productVersion 2>/dev/null || printf 'unknown')"
      WORKSTATION_OS_VERSION_ID="${OS_WORKSTATION_VERSION}"
      log "This workstation where this is running is a macOS System."
      warn "macOS is detected. This script remains Linux-first; ensure cpd-cli and a working container engine are available."
      ;;
    Linux)
      local os_release_file="${WORKSTATION_OS_RELEASE_FILE:-/etc/os-release}"
      local parsed_id parsed_version_id
      parsed_id="$(read_os_release_value ID "${os_release_file}")"
      parsed_version_id="$(read_os_release_value VERSION_ID "${os_release_file}")"
      WORKSTATION_OS_ID="${parsed_id:-unknown}"
      OS_WORKSTATION_VERSION="${parsed_version_id:-unknown}"
      WORKSTATION_OS_VERSION_ID="${OS_WORKSTATION_VERSION}"
      WORKSTATION_OS_ID="${WORKSTATION_OS_ID,,}"

      case "${WORKSTATION_OS_ID}" in
        rhel|redhat|redhatenterpriseserver)
          WORKSTATION_OS_FAMILY="rhel"
          log "This workstation where this is running is an RHEL System."
          ;;
        ubuntu)
          WORKSTATION_OS_FAMILY="ubuntu"
          log "This workstation where this is running is an Ubuntu System."
          ;;
        fedora)
          WORKSTATION_OS_FAMILY="fedora"
          log "This workstation where this is running is a Fedora System."
          ;;
        centos)
          WORKSTATION_OS_FAMILY="centos"
          log "This workstation where this is running is a CentOS System."
          ;;
        rocky|almalinux|ol|oracle)
          WORKSTATION_OS_FAMILY="rhel-compatible"
          log "This workstation where this is running is an RHEL-compatible Linux System."
          ;;
        *)
          WORKSTATION_OS_FAMILY="linux"
          log "This workstation where this is running is a Linux System."
          ;;
      esac
      ;;
    *)
      WORKSTATION_OS_FAMILY="unknown"
      warn "This workstation OS could not be classified: ${WORKSTATION_KERNEL}."
      ;;
  esac

  export WORKSTATION_KERNEL WORKSTATION_OS_ID OS_WORKSTATION_VERSION WORKSTATION_OS_VERSION_ID WORKSTATION_OS_FAMILY
  assert_software_hub_version_sacred
  validate_software_hub_version
  log "Detected workstation OS ID: ${WORKSTATION_OS_ID} ${OS_WORKSTATION_VERSION}"
  log "OS_WORKSTATION_VERSION=${OS_WORKSTATION_VERSION}"
  log "IBM Software Hub release preserved as VERSION=${VERSION}"
}
detect_container_engine() {
  if [[ -n "${CONTAINER_EXE:-}" ]]; then
    command -v "${CONTAINER_EXE}" >/dev/null 2>&1 || { err "Configured CONTAINER_EXE=${CONTAINER_EXE} was not found in PATH."; exit 1; }
  elif command -v podman >/dev/null 2>&1; then
    CONTAINER_EXE="podman"
  elif command -v docker >/dev/null 2>&1; then
    CONTAINER_EXE="docker"
  else
    err "Neither podman nor docker was found. Install a supported container engine before running onboarding."
    exit 1
  fi

  export CONTAINER_EXE
  log "Using container engine: ${CONTAINER_EXE}"
}

run_privileged() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}

safe_chown_to_current_user() {
  local target="$1"
  local uid gid
  uid="$(id -u)"
  gid="$(id -g)"
  if [[ ! -e "${target}" ]]; then
    return 0
  fi
  chown -R "${uid}:${gid}" "${target}" 2>/dev/null || run_privileged chown -R "${uid}:${gid}" "${target}" 2>/dev/null || true
}

safe_chmod_777() {
  local target="$1"
  if [[ ! -e "${target}" ]]; then
    return 0
  fi
  chmod -R 777 "${target}" 2>/dev/null || run_privileged chmod -R 777 "${target}" 2>/dev/null || true
}

prepare_host_workspace_for_cpd_cli() {
  : "${CPD_CLI_MANAGE_WORKSPACE:?CPD_CLI_MANAGE_WORKSPACE is required.}"

  log "Preparing host-side cpd-cli workspace for ${WORKSTATION_OS_FAMILY}: ${CPD_CLI_MANAGE_WORKSPACE}"

  if [[ -d "${CPD_CLI_MANAGE_WORKSPACE}/work" ]]; then
    log "Existing workspace detected at ${CPD_CLI_MANAGE_WORKSPACE}."
    log "Cleaning up before proceeding..."
    rm -rf "${CPD_CLI_MANAGE_WORKSPACE}" 2>/dev/null || run_privileged rm -rf "${CPD_CLI_MANAGE_WORKSPACE}" 2>/dev/null || true
  else
    log "No existing workspace detected. Creating new workspace at ${CPD_CLI_MANAGE_WORKSPACE}..."
  fi

  mkdir -p "${CPD_CLI_MANAGE_WORKSPACE}/work/offline" \
           "${CPD_CLI_MANAGE_WORKSPACE}/work/offline/patch" \
           "${CPD_CLI_MANAGE_WORKSPACE}/work/olm-utils-ansible-log" \
           "${CPD_CLI_MANAGE_WORKSPACE}/work/.olm-utils" \
           "${CPD_CLI_MANAGE_WORKSPACE}/work/cpfs_scripts" 2>/dev/null || \
    run_privileged mkdir -p "${CPD_CLI_MANAGE_WORKSPACE}/work/offline" \
                     "${CPD_CLI_MANAGE_WORKSPACE}/work/offline/patch" \
                     "${CPD_CLI_MANAGE_WORKSPACE}/work/olm-utils-ansible-log" \
                     "${CPD_CLI_MANAGE_WORKSPACE}/work/.olm-utils" \
                     "${CPD_CLI_MANAGE_WORKSPACE}/work/cpfs_scripts"

  # Critical cross-distro rule:
  # Before cpd-cli manage restart-container runs, the host user must own the
  # work tree.  Do not chown this tree to 1001:0 on the host before restart-
  # container.  cpd-cli itself chmods the host work directory; non-owner chmod
  # fails on Ubuntu, RHEL 9, Fedora, CentOS, and other non-UID-1001 systems.
  safe_chown_to_current_user "${CPD_CLI_MANAGE_WORKSPACE}"
  safe_chmod_777 "${CPD_CLI_MANAGE_WORKSPACE}"

  if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce 2>/dev/null || true)" != "Disabled" ]]; then
    run_privileged chcon -Rt container_file_t "${CPD_CLI_MANAGE_WORKSPACE}" 2>/dev/null || true
  fi

  log "Host-side workspace is ready for cpd-cli restart-container."
}

# ------------------------------------------------------------------------------
# Workspace Manager:
# ------------------------------------------------------------------------------
# OS-aware host workspace preparation.  This replaces the old sudo-created
# workspace pattern that could leave work owned by root or 1001 before cpd-cli
# attempted its own chmod on non-RHEL10 systems.
detect_workstation_os
detect_container_engine
prepare_host_workspace_for_cpd_cli
pdf_utilities
# dos2unix

## Silent login:
podman logout "${IBM_REGISTRY_SUBDOMAIN}" >/dev/null 2>&1 || true
if "${CONTAINER_EXE}" login "${IBM_REGISTRY_SUBDOMAIN}" -u "${IBM_REGISTRY_SUBDOMAIN_USER}" -p "${IBM_ENTITLEMENT_KEY}" 2>/dev/null; then
  log "Login Succeeded! [${IBM_REGISTRY_SUBDOMAIN}]"
else
  err "Failed to log into IBM registry ${IBM_REGISTRY_SUBDOMAIN}. Check your credentials and network connectivity."
  exit 1
fi
podman logout "${IBM_REGISTRY_PRIMARY}" >/dev/null 2>&1 || true
if "${CONTAINER_EXE}" login "${IBM_REGISTRY_PRIMARY}" -u "${IBM_REGISTRY_PRIMARY_USER}" -p "${IBM_IAM_APIKEY}" 2>/dev/null; then
  log "Login Succeeded! [${IBM_REGISTRY_PRIMARY}]"
else
  log "Login to [${IBM_REGISTRY_PRIMARY}] is optional, we did not login at first try. Re-trying..."
  LOGIN_OUTPUT="$("${CONTAINER_EXE}" login -u "${IBM_REGISTRY_PRIMARY_USER}" -p "${IBM_IAM_APIKEY}" "${IBM_REGISTRY_PRIMARY}" 2>&1)" || true
  if echo "$LOGIN_OUTPUT" | grep -q "currently logged in" && \
    echo "$LOGIN_OUTPUT" | grep -q "auth file contains an Identity token"; then
    log "Login Succeeded! [${IBM_REGISTRY_PRIMARY}]"
  fi
fi

log "Please wait while the OLM Utils runtime workspace is repaired and prepared for operations..."

export OLM_UTILS_IMAGE="${IBM_REGISTRY_PRIMARY}/cpopen/cpd/olm-utils-${OLM_UTILS_VERSION}:${VERSION}"
clean_runtime_olm_utils_containers_and_images() {
  podman ps -a --format '{{.ID}} {{.Names}} {{.Image}}' \
    | awk '$0 ~ /olm-utils-v[0-9]+/ {print $1}' \
    | sort -u \
    | xargs -r podman rm -f >/dev/null 2>&1 || true

  podman images --format '{{.Repository}}:{{.Tag}} {{.ID}}' \
    | awk '$1 ~ /olm-utils-v[0-9]+/ {print $2}' \
    | sort -u \
    | xargs -r podman rmi -f >/dev/null 2>&1 || true
}

clean_runtime_olm_utils_containers_and_images

#[LOGIN]::::::::::::::::::::::::::::::::::::::
login_entitled_registry_once() {
  : "${IBM_ENTITLEMENT_KEY:?Set IBM_ENTITLEMENT_KEY first}"

  echo "[INFO] Logging in to IBM entitled registry..."

  cpd-cli manage login-entitled-registry \
    "${IBM_ENTITLEMENT_KEY}"

  log "Login to IBM entitled registry completed successfully."
  echo
}

# Prepare host workspace only.
assert_software_hub_version_sacred
validate_software_hub_version

if "${CONTAINER_EXE}" pull "${IBM_REGISTRY_PRIMARY}/cpopen/cpd/olm-utils-${OLM_UTILS_VERSION}:${VERSION}" >/dev/null 2>&1; then
  log "Successfully pulled OLM Utils image: ${IBM_REGISTRY_PRIMARY}/cpopen/cpd/olm-utils-${OLM_UTILS_VERSION}:${VERSION}"
else
  log "Failed to pull OLM Utils image: ${IBM_REGISTRY_PRIMARY}/cpopen/cpd/olm-utils-${OLM_UTILS_VERSION}:${VERSION}"
  exit 1
fi

# Re-assert host ownership immediately before restart-container without
# deleting the prepared workspace.  The runtime repair to 1001:0 happens only
# inside the OLM Utils container after it starts.
safe_chown_to_current_user "${CPD_CLI_MANAGE_WORKSPACE}"
safe_chmod_777 "${CPD_CLI_MANAGE_WORKSPACE}"

# This recreates olm-utils-play-v4.
cpd-cli manage restart-container

# This must happen after restart-container.
fix_olm_utils_runtime_tmp_work_as_root

# Now run entitlement login.
login_entitled_registry_once

# Run the runtime repair again before downstream cpd-cli operations.
fix_olm_utils_runtime_tmp_work_as_root pre-list-images

#              [AUTHENTICATION AND WORKSPACE PREPARATION ENDS]
#||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
#||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
#||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
#||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||

##############################################################################
# ------------------------------------------------------------------------------
# Presenter Guide
# ------------------------------------------------------------------------------
COLOR_ENABLED="${COLOR_ENABLED:-1}"
if [[ ! -t 1 ]]; then COLOR_ENABLED=0; fi
if [[ "${NO_COLOR:-}" ]]; then COLOR_ENABLED=0; fi
if [[ "$COLOR_ENABLED" == "1" ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_MAGENTA=$'\033[35m'; C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'
else
  C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""; C_BOLD=""
fi

log() { printf '%s[INFO]%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
success() { printf '%s[SUCCESS]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err() { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

usage() {
  cat <<USAGE
${SCRIPT_NAME} - IBM Software Hub image onboarding worker

This worker is intentionally guarded. Run ./xLaunchpad.sh instead.

Environment values accepted from xLaunchpad.sh:
  VERSION       IBM Software Hub release, for example 5.3.1
  COMPONENTS    Comma-separated component IDs, for example cpd_platform,wkc,watsonx_ai
  ARCH    amd64, s390x, or ppc64le

Advanced test controls:
  IBM_SWH_IMAGE_ONBOARD_LAUNCHED_BY_XLAUNCHPAD=1   required for normal execution
  IBM_SWH_DRY_RUN=1                                 validate logic without running cpd-cli list-images
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--self-test" ]]; then
  echo "self-test: script loads successfully"
  exit 0
fi

if [[ "${IBM_SWH_IMAGE_ONBOARD_LAUNCHED_BY_XLAUNCHPAD:-0}" != "1" ]]; then
  err "Direct execution is blocked by production policy. Run ./xLaunchpad.sh."
  exit 1
fi

# Component IDs from IBM Software Hub 5.1 component ID documentation.
COMPONENT_VALIDATE_ARRAY=(
  ibm-cert-manager ibm-licensing scheduler cpfs cpd_platform zen
  factsheet analyticsengine cognos_analytics dashboard datagate dp dataproduct datarefinery replication
  datastage_ent datastage_ent_plus dv db2oltp bigsql dmc db2wh dods edb_cp4d postgresql hee
  wkc ikc_premium ikc_standard datalineage match360 streamsets informix_cp4d informix mantaflow
  mongodb mongodb_cp4d openpages ws_pipelines planning_analytics productmaster rstudio spss syntheticdata
  voice_gateway watson_discovery wml openscale watson_speech ws ws_runtimes watsonx_ai watson_assistant
  wca wca_ansible wca_z wca_z_ce watsonx_data watsonx_governance watsonx_orchestrate
  canvasbase ccs db2aaservice db2u wca_base watsonx_ai_ifm
)

component_is_valid() {
  local candidate="$1" valid
  for valid in "${COMPONENT_VALIDATE_ARRAY[@]}"; do
    [[ "$candidate" == "$valid" ]] && return 0
  done
  return 1
}

trim() {
  local s="$*"
  s="${s#${s%%[![:space:]]*}}"
  s="${s%${s##*[![:space:]]}}"
  printf '%s' "$s"
}

validate_components() {
  local components_csv="$1"
  local item clean invalid=()
  IFS=',' read -r -a _parts <<< "$components_csv"
  if [[ ${#_parts[@]} -eq 0 ]]; then
    err "No components were provided."
    exit 1
  fi
  for item in "${_parts[@]}"; do
    clean="$(trim "$item")"
    if [[ -z "$clean" ]]; then
      invalid+=("<empty>")
      continue
    fi
    if ! component_is_valid "$clean"; then
      invalid+=("$clean")
    fi
  done
  if [[ ${#invalid[@]} -gt 0 ]]; then
    err "Invalid IBM Software Hub component ID(s): ${invalid[*]}"
    err "Check component IDs here: ${COMPONENT_HELP_URL}"
    exit 1
  fi
}

normalize_components() {
  local components_csv="$1"
  local item clean out=()
  IFS=',' read -r -a _parts <<< "$components_csv"
  for item in "${_parts[@]}"; do
    clean="$(trim "$item")"
    [[ -n "$clean" ]] && out+=("$clean")
  done
  local IFS=','
  printf '%s' "${out[*]}"
}

map_cli_operand_to_swh() {
  local cli_version="$1"
  local major_minor patch
  cli_version="${cli_version#v}"
  major_minor="${cli_version%.*}"
  patch="${cli_version##*.}"
  case "$major_minor" in
    14.3) printf '5.3.%s\n' "$patch" ;;
    14.2) printf '5.2.%s\n' "$patch" ;;
    14.1) printf '5.1.%s\n' "$patch" ;;
    14.0) printf '5.0.%s\n' "$patch" ;;
    13.1) printf '4.8.%s\n' "$patch" ;;
    13.0) printf '4.7.%s\n' "$patch" ;;
    12.0) printf '4.6.%s\n' "$patch" ;;
    11.0) printf '4.5.%s\n' "$patch" ;;
    10.0) printf '4.0.%s\n' "$patch" ;;
    3.5)  printf '3.5.%s\n' "$patch" ;;
    3.0)  printf '3.0.%s\n' "$patch" ;;
    *) return 1 ;;
  esac
}

extract_cpd_cli_version() {
  local version_output cli_operand mapped
  if ! command -v cpd-cli >/dev/null 2>&1; then
    err "cpd-cli is not installed or is not in PATH."
    err "Install the correct cpd-cli version from: ${INSTALL_HELP_URL}"
    exit 1
  fi

  version_output="$(cpd-cli version 2>/dev/null || true)"
  if [[ -z "$version_output" ]]; then
    err "Unable to retrieve cpd-cli version output."
    exit 1
  fi

  CPD_CLI_VERSION="$(printf '%s\n' "$version_output" | awk -F': *' '/SWH Release Version|CPD Release Version/ {print $2; exit}' | tr -d '[:space:]')"
  if [[ -z "$CPD_CLI_VERSION" ]]; then
    cli_operand="$(printf '%s\n' "$version_output" | awk -F': *' '/^Version/ {print $2; exit}' | awk '{print $1}' | tr -d '[:space:]')"
    if [[ -n "$cli_operand" ]]; then
      mapped="$(map_cli_operand_to_swh "$cli_operand" 2>/dev/null || true)"
      if [[ -n "$mapped" ]]; then
        CPD_CLI_VERSION="$mapped"
      else
        CPD_CLI_VERSION="$cli_operand"
      fi
    fi
  fi

  if [[ -z "$CPD_CLI_VERSION" ]]; then
    err "Could not determine IBM Software Hub release version from cpd-cli version output."
    printf '%s\n' "$version_output" >&2
    exit 1
  fi

  export CPD_CLI_VERSION
  log "Detected cpd-cli IBM Software Hub release version: ${CPD_CLI_VERSION}"
}

validate_arch() {
  case "${ARCH:-}" in
    amd64|s390x|ppc64le) return 0 ;;
    *) err "Invalid ARCH '${ARCH:-}'. Expected amd64, s390x, or ppc64le."; exit 1 ;;
  esac
}

find_generated_csv() {
  local root="$1"
  local version="$2"
  local preferred="${root}/work/offline/${version}/list_images.csv"
  if [[ -f "$preferred" ]]; then
    printf '%s\n' "$preferred"
    return 0
  fi
  find "$root" -type f \( -name '*list*image*.csv' -o -name '*.csv' \) -print 2>/dev/null | sort | tail -n 1
}

get_case() {
  : "${VERSION:?Set VERSION first}"
  : "${COMPONENTS:?Set COMPONENTS first}"
  : "${CPD_CLI_MANAGE_WORKSPACE:?Set CPD_CLI_MANAGE_WORKSPACE first}"
  : "${ARCH:?Set ARCH first}"

  ALTERNATIVE_COMPONENTS="${ALTERNATIVE_COMPONENTS:-None}"
  COMPONENTS="${COMPONENTS}"
  export COMPONENTS
  export ALTERNATIVE_COMPONENTS
  COMPONENTS_TO_SKIP="${COMPONENTS_TO_SKIP:-}"
  export COMPONENTS_TO_SKIP

  local case_index_dir="${CPD_CLI_MANAGE_WORKSPACE}/CASE-INDEX/${ARCH}"

  log "Downloading CASE packages before list-images."
  log "Settings Specified Components: ${COMPONENTS}"
  log "User-pasted Specified Components: ${ALTERNATIVE_COMPONENTS:-None}"
  log "Setting components to Skip: ${COMPONENTS_TO_SKIP:-None}"
  log "IBM Software Hub Version specified: ${VERSION}"

error_details_for_image_groups() {
  local image_groups="${IMAGE_GROUPS}"

  cat <<'EOF'

+------------------------------------------------------------------------------------------------------------------+
| Missing or invalid IMAGE_GROUPS for watsonx Orchestrate foundation models                                        |
+------------------------------------------------------------------------------------------------------------------+
| Model ID                         | Image group                     | Dependency                                  |
+----------------------------------+---------------------------------+---------------------------------------------+
| granite-3-8b-instruct            | ibmwxGranite38BInstruct         | None                                        |
| llama-3-1-70b-instruct           | ibmwxLlama3170bInstruct         | ibmwxSlate30mEnglishRtrvr                   |
| llama-3-2-90b-vision-instruct    | ibmwxLlama3290bVisionInstruct   | ibmwxSlate30mEnglishRtrvr                   |
| slate-30m-english-rtrvr          | ibmwxSlate30mEnglishRtrvr       | Required for Llama 70B and Llama 90B Vision |
+----------------------------------+---------------------------------+---------------------------------------------+

Note:
  ibm-granite-8b-unified-api-model-v2 is not listed because its image group is not applicable.
  It is automatically onboarded when watsonx Orchestrate images are onboarded as default.

Current IMAGE_GROUPS:
EOF

  if [ -n "${image_groups}" ]; then
    echo "  ${image_groups}"
  else
    echo "  <empty>"
  fi

  cat <<'EOF'

Expected IMAGE_GROUPS examples when you add watsonx_ai_ifm component is one of the following::

  IMAGE_GROUPS="ibmwxGranite38BInstruct"
  IMAGE_GROUPS="ibmwxLlama3170bInstruct,ibmwxSlate30mEnglishRtrvr"
  IMAGE_GROUPS="ibmwxLlama3290bVisionInstruct,ibmwxSlate30mEnglishRtrvr"

If you do NOT wish to onboard any AI models into the private registry, remove watsonx_ai_ifm from the COMPONENTS list and run the script again. 
The watsonx Orchestrate component, when onboarded, will onboard the default foundation model (ibm-granite-8b-unified-api-model-v2).

EOF
}

  ai_models_image_group_checker() {
    if [[ "${COMPONENTS:-}" =~ (^|[,\ ])watsonx_ai_ifm($|[,\ ]) ]] && [ -z "${IMAGE_GROUPS}" ]; then
      error_details_for_image_groups
      exit 1
    fi
  }
  ai_models_image_group_checker

  if [[ "${COMPONENTS:-}" =~ (^|[,\ ])watsonx_ai_ifm($|[,\ ]) ]] && [ -n "${IMAGE_GROUPS:-}" ]; then
    cpd-cli manage case-download \
      --components="${COMPONENTS}" \
      --skip_components="${COMPONENTS_TO_SKIP}" \
      --arch=${IMAGE_ARCH} \
      --groups="${IMAGE_GROUPS}" \
      --release="${VERSION}"
  else
    cpd-cli manage case-download \
      --components="${COMPONENTS}" \
      --skip_components="${COMPONENTS_TO_SKIP}" \
      --arch=${IMAGE_ARCH} \
      --release="${VERSION}"
  fi

  log "Repairing OLM Utils runtime workspace permissions after case-download."
  fix_olm_utils_runtime_tmp_work_as_root runtime

  mkdir -p "${case_index_dir}"
  sudo cp -a "${CPD_CLI_MANAGE_WORKSPACE}/work/." "${case_index_dir}/"
  sudo chown -R "$(id -u):$(id -g)" "${CPD_CLI_MANAGE_WORKSPACE}/CASE-INDEX" 2>/dev/null || true
  sudo chmod -R 777 "${CPD_CLI_MANAGE_WORKSPACE}/CASE-INDEX" 2>/dev/null || true

  # Re-assert container-side permissions after staging. list-images runs inside
  # the same OLM Utils container against /tmp/work.
  log "Re-asserting OLM Utils runtime permissions before list-images."
  fix_olm_utils_runtime_tmp_work_as_root runtime

  success "CASE packages staged at: ${case_index_dir}"
  log "Pausing for 10 seconds before cpd-cli manage list-images starts."
  sleep 10
}

analyze_and_deduplicate_list() {
  local original_csv="$1"
  local onboard_dir="${CPD_CLI_MANAGE_WORKSPACE}/${IMAGE_LIST_ID}/${ARCH}"
  local output_csv="${onboard_dir}/ibm-swh-${VERSION}-onboarding-${ARCH}-image-list.csv"
  local analysis_file="${onboard_dir}/ibm-swh-${VERSION}-onboarding-${ARCH}-image-list-analysis.txt"
  local analysis_file_receipt="${onboard_dir}/ibm-swh-${VERSION}-onboarding-${ARCH}-image-list-analysis.pdf"

  if [[ ! -f "$original_csv" ]]; then
    err "Generated image list CSV was not found: $original_csv"
    exit 1
  fi

  mkdir -p "${onboard_dir}"
  awk 'NR==1 {print; next} !seen[$0]++ {print}' "$original_csv" > "$output_csv"

  local original_rows dedup_rows duplicates_removed
  original_rows=$(( $(wc -l < "$original_csv" | tr -d ' ') - 1 ))
  dedup_rows=$(( $(wc -l < "$output_csv" | tr -d ' ') - 1 ))
  (( original_rows < 0 )) && original_rows=0
  (( dedup_rows < 0 )) && dedup_rows=0
  duplicates_removed=$(( original_rows - dedup_rows ))
  (( duplicates_removed < 0 )) && duplicates_removed=0

  local skipped_components_ids
  skipped_components_ids="$(trim "${COMPONENTS_TO_SKIP:-}")"
  if [[ -z "${skipped_components_ids}" ]]; then
    skipped_components_ids="None"
  fi

  # Get cpd-cli version for receipt:
  cpd_cli_version_build_info="$(cpd-cli version 2>/dev/null || true)"
  export cpd_cli_version_build_info

  # If watsonx-ai_ifm is not in the COMPONENTS list, declare IMAGE_GROUPS as None::
  if [[ ! "${COMPONENTS}" =~ (^|[,\ ])watsonx_ai_ifm($|[,\ ]) ]]; then
    IMAGE_GROUPS="None"
    export IMAGE_GROUPS
  else
    IMAGE_GROUPS="${IMAGE_GROUPS}"
    export IMAGE_GROUPS
  fi

  if [[ ! "${COMPONENTS}" =~ (^|[,\ ])watsonx_orchestrate($|[,\ ]) ]]; then
    WXO_AI_MODEL="None"
    export WXO_AI_MODEL
  else
    WXO_AI_MODEL="ibm-granite-8b-unified-api-model-v2"
    export WXO_AI_MODEL
  fi

  cat > "$analysis_file" <<REPORT
RECEIPT FOR IBM SOFTWARE HUB IMAGE ONBOARDING GENERATED IMAGE LIST
==================================================================
IBM Software Hub image onboarding list analysis & receipt
==================================================================
Version: ${VERSION}
Patch ID: ${PATCH_ID}
Architecture: ${ARCH}
Image List ID: ${IMAGE_LIST_ID}
Components: ${COMPONENTS}
IBM watsonx Orchestrate Automatic AI Model Included: ${WXO_AI_MODEL}
IBM AI Model Image Groups: ${IMAGE_GROUPS}
Skipped Components IDs: ${skipped_components_ids}
Original CSV: ${original_csv}
Deduplicated CSV: ${output_csv}
Original data rows: ${original_rows}
Deduplicated data rows: ${dedup_rows}
Duplicate rows removed: ${duplicates_removed}
Generated at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
---------------------------------------------------------
Retain the original generated CSV and this analysis file.
Provide both to IBM support when requesting help for this.
For questions, contact your IBM Client Engineering Lead.



IBM Software Hub/CPD Build Information:
Patch ID: ${PATCH_ID}
SWH Version: ${VERSION}
${cpd_cli_version_build_info}

NOTE: 
- Customer must install this exact cpd-cli build to use this generated image list.
- Customer should not use a different cpd-cli version & patch.
- Customer must use the same SWH Version and Patch ID listed during installation of the SWH Instance on OpenShift.



Software Information:
Software: ISWH Image Onboarding Manager
Current Version: ${ISWH_VERSION}
Software Author: Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist
Email: jeffrey.chijioke-uche@ibm.com

IBM Support Information:
Info: https://www.ibm.com/mysupport/s/?language=en_US

IBM Corporation (c) ${YEAR}. All rights reserved.
----------------------------------------------------------
REPORT

  export IBM_SWH_ONBOARDING_IMAGE_LIST="$output_csv"
  success "Deduplicated image onboarding list created: ${output_csv}"
  log "Analysis report & receipt: ${analysis_file_receipt}"

  # Produce Receipt:
  receipt() {
    enscript -p temp.ps "$analysis_file"
    ps2pdf temp.ps "${analysis_file_receipt}"
    sudo rm temp.ps
    sudo rm "$analysis_file"
  }
  # Silent use:
  receipt >/dev/null 2>&1 || true
}

run_list_images() {
  mkdir -p "$CPD_CLI_MANAGE_WORKSPACE"
  export CPD_CLI_MANAGE_WORKSPACE
  export IMAGE_ARCH="$ARCH"

  log "Using CPD_CLI_MANAGE_WORKSPACE=${CPD_CLI_MANAGE_WORKSPACE}"
  log "Running cpd-cli manage list-images for VERSION=${VERSION}, ARCH=${ARCH}, COMPONENTS=${COMPONENTS}"

  if [[ "${IBM_SWH_DRY_RUN:-0}" == "1" ]]; then
    log "Dry-run mode enabled. Skipping cpd-cli manage list-images execution."
    mkdir -p "${CPD_CLI_MANAGE_WORKSPACE}/work/offline/${VERSION}"
    cat > "${CPD_CLI_MANAGE_WORKSPACE}/work/offline/${VERSION}/list_images.csv" <<CSV
image,source,component,architecture
icr.io/cpopen/example-a:1,icr.io,cpd_platform,${ARCH}
icr.io/cpopen/example-a:1,icr.io,cpd_platform,${ARCH}
icr.io/cpopen/example-b:1,icr.io,${COMPONENTS%%,*},${ARCH}
CSV
    mkdir -p "${CPD_CLI_MANAGE_WORKSPACE}/CASE-INDEX/${ARCH}"
    sudo cp -a "${CPD_CLI_MANAGE_WORKSPACE}/work/." "${CPD_CLI_MANAGE_WORKSPACE}/CASE-INDEX/${ARCH}/"
    sudo chown -R "$(id -u):$(id -g)" "${CPD_CLI_MANAGE_WORKSPACE}/CASE-INDEX/${ARCH}" 2>/dev/null || true
    sudo chmod -R 777 "${CPD_CLI_MANAGE_WORKSPACE}/CASE-INDEX" 2>/dev/null || true
  else
    export IMAGE_ARCH="$ARCH"
    export COMPONENTS_TO_SKIP="${COMPONENTS_TO_SKIP:-}"

    get_case

    # Keep CASE artifacts produced by case-download. Do not use pre-list-images here
    # because that mode intentionally removes /tmp/work/offline/${VERSION}.
    fix_olm_utils_runtime_tmp_work_as_root runtime

    if [[ "${COMPONENTS}" =~ (^|[,\ ])watsonx_ai_ifm($|[,\ ]) ]] && [ -n "${IMAGE_GROUPS}" ]; then
      local list_images_cmd=(cpd-cli manage list-images
        --components="${COMPONENTS}"
        --skip_components="${COMPONENTS_TO_SKIP}"
        --release="${VERSION}"
        --arch="${IMAGE_ARCH}"
        --groups="${IMAGE_GROUPS}"
        --case_download=false)
    else
      local list_images_cmd=(cpd-cli manage list-images
        --components="${COMPONENTS}"
        --skip_components="${COMPONENTS_TO_SKIP}"
        --release="${VERSION}"
        --arch="${IMAGE_ARCH}"   
        --case_download=false)
    fi

    if [[ -n "${COMPONENTS_TO_SKIP}" ]]; then
      list_images_cmd+=(--skip_components="${COMPONENTS_TO_SKIP}")
    fi

    "${list_images_cmd[@]}"
  fi

  export CPD_CLI_MANAGE_WORKSPACE="${CPD_CLI_MANAGE_WORKSPACE}"
  ID="$(id -u):$(id -g)"
  sudo chown -R "$ID" "${CPD_CLI_MANAGE_WORKSPACE}" 2>/dev/null || true
  host_workspace="$(sudo chmod -R 777 "${CPD_CLI_MANAGE_WORKSPACE}" 2>/dev/null || true)"
  export host_workspace="${host_workspace}"
  if [[ -n "$host_workspace" ]]; then
    log "Host workspace (${CPD_CLI_MANAGE_WORKSPACE}) permissions updated successfully."
  fi

  cd "$CPD_CLI_MANAGE_WORKSPACE"
  local csv_file
  csv_file="$(find_generated_csv "$CPD_CLI_MANAGE_WORKSPACE" "$VERSION")"
  if [[ -z "$csv_file" || ! -f "$csv_file" ]]; then
    err "No generated CSV file was found under ${CPD_CLI_MANAGE_WORKSPACE}."
    err "IBM documentation states list-images output is saved under work/offline/\${VERSION}/list_images.csv."
    exit 1
  fi
  log "Original generated CSV retained at: ${csv_file}"
  analyze_and_deduplicate_list "$csv_file"
}

main() {
  : "${VERSION:?VERSION is required.}"
  : "${COMPONENTS:?COMPONENTS is required.}"
  : "${ARCH:?ARCH is required.}"

  local normalized_version
  normalized_version="$(trim "$VERSION")"
  if [[ "${normalized_version}" != "${VERSION}" ]]; then
    die "VERSION in settings.sh contains leading or trailing whitespace. VERSION is sacred and must be set cleanly in settings.sh. Current value: ${VERSION}"
  fi
  assert_software_hub_version_sacred
  validate_software_hub_version
  COMPONENTS="$(normalize_components "$COMPONENTS")"
  ARCH="$(trim "$ARCH")"
  export COMPONENTS ARCH

  validate_arch
  validate_components "$COMPONENTS"
  extract_cpd_cli_version

  if [[ "$VERSION" != "$CPD_CLI_VERSION" ]]; then
    warn "The version entered (${VERSION}) must match the IBM Software Hub release version installed (${CPD_CLI_VERSION})."
    warn "Install the correct cpd-cli version from: ${INSTALL_HELP_URL}"
    exit 1
  fi

  if [[ ! -f "$SWH_VARS_FILE" ]]; then
    err "Required variable script not found: ${SWH_VARS_FILE}"
    exit 1
  fi

  # shellcheck source=/dev/null
  source "$SWH_VARS_FILE"
  assert_software_hub_version_sacred
  validate_software_hub_version

  run_list_images
  ONBOARD_COMPLETED=1
  export ONBOARD_COMPLETED
}

main "$@"
