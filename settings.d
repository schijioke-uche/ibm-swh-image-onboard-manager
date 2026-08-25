#!/usr/bin/env bash

# +----------------------------------------------------------------------------+
# | @Author : Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist                |
# | @Purpose: IBM Software Hub Enterprise Image Onboarding Manager             |
# | @Usage: Automate IBM SWH Enterprise images Generation List  for AirGap     |
# | @License: Proprietary                                                      |
# +----------------------------------------------------------------------------+

#                ⚙️ -- S   E   T   T   I   N   G   S -- ⚙️

#===============================================================================

# ------------------------------------------------------------------------------
# [Filter] By Architecture:                                          [Edit ARCH]
# ------------------------------------------------------------------------------
export ARCH=""  # Set to: amd64 | ppc64le | s390x.
export IMAGE_ARCH="${ARCH}"

# ------------------------------------------------------------------------------
# [Filter] By SWH Release Version:                                       [Edit]
# ------------------------------------------------------------------------------
export VERSION=""

# ------------------------------------------------------------------------------
# [Filter] By IBM Software Hub Version Patch ID: 
# Specify "0" or "latest" as default.                        [Edit]
# But If SWH version is 5.3.1 & you want to specify a specific patch ID.
# For 5.3.1 Patch/hotfix 1, specify 1
# For 5.3.1 Patch/hotfix 2, specify 2
# For 5.3.1 Patch/hotfix 3, specify 3
# For 5.3.1 Patch/hotfix 4, specify 4
# For 5.3.1 Patch/hotfix 5, specify 5
# For 5.3.1 Patch/hotfix 6, specify 6
# ------------------------------------------------------------------------------
export PATCH_ID=

# ------------------------------------------------------------------------------
# IBM Entitled Registry:                                        [Do Not Edit]
# ------------------------------------------------------------------------------
export IBM_REGISTRY_PRIMARY="icr.io"
export IBM_REGISTRY_PRIMARY_USER="iamapikey"
export IBM_REGISTRY_SUBDOMAIN="cp.icr.io"
export IBM_REGISTRY_SUBDOMAIN_USER="cp"

# ------------------------------------------------------------------------------
# IBM Entitled Registry:   [Edit - Required for Worker Operations]
# ------------------------------------------------------------------------------
export IBM_ENTITLEMENT_KEY=""
export IBM_IAM_APIKEY=""

# ------------------------------------------------------------------------------
# Image pull configuration:                                    [Do Not Edit]
# ------------------------------------------------------------------------------
export IMAGE_PULL_SECRET="ibm-entitlement-key"

# ------------------------------------------------------------------------------
# OLM Utils Version:                                           [Do Not Edit]
# ------------------------------------------------------------------------------
if [[ "$VERSION" == "5.2."* ]]; then
  export OLM_UTILS_VERSION="v3"
elif [[ "$VERSION" == "5.3."* ]]; then
  export OLM_UTILS_VERSION="v4"
elif [[ "$VERSION" == "5.4."* ]]; then
  export OLM_UTILS_VERSION="v5"
elif [[ "$VERSION" == "5.5."* ]]; then
  export OLM_UTILS_VERSION="v6"
elif [[ "$VERSION" == "5.6."* ]]; then
  export OLM_UTILS_VERSION="v7"
elif [[ "$VERSION" == "5.7."* ]]; then
  export OLM_UTILS_VERSION="v8"
else
  printf '%sWarning: Unrecognized IBM Software Hub version "%s". Find the supported version by this solution.%s\n' "$YELLOW" "$VERSION" "$RESET"
  printf '%sWarning: Please find the appropriate OLM Utils version for your IBM Software Hub version and try again.%s\n' "$YELLOW" "$RESET"
  exit 1
fi

#--------------------------------------------------------------------------------
# Launchpad Metadata:                                  [Do Not Edit]
# ------------------------------------------------------------------------------
OLM_UTILS_IMAGE="${IBM_REGISTRY_PRIMARY}/cpopen/cpd/olm-utils-${OLM_UTILS_VERSION}:${VERSION}"
export OLM_UTILS_IMAGE="${OLM_UTILS_IMAGE}"
podman image -f rm ${OLM_UTILS_IMAGE} 2>/dev/null && echo "Removed stale ${OLM_UTILS_IMAGE}" || true

# ------------------------------------------------------------------------------
# Components:           [Edit only one block corresponding to your architecture]
# ------------------------------------------------------------------------------
if [[ "${IMAGE_ARCH}" == "s390x" ]]; then        #[BLOCK Option-1: s390x]
  export COMPONENTS="" # You can include: watsonx_ai_ifm
  export COMPONENTS_TO_SKIP=""
  export IMAGE_GROUPS=""   # [Model Images for IFM.]

elif [[ "${IMAGE_ARCH}" == "amd64" ]]; then       #[BLOCK Option-2: amd64]
  export COMPONENTS=""
  export COMPONENTS_TO_SKIP=""
  export IMAGE_GROUPS=""  # [Model Images for IFM.]

elif [[ "${IMAGE_ARCH}" == "ppc64le" ]]; then   #[BLOCK Option-3: ppc64le]
  export COMPONENTS=""
  export COMPONENTS_TO_SKIP=""
  export IMAGE_GROUPS=""
fi

#  -----DO NOT EDIT BELOW THIS LINE UNLESS YOU KNOW WHAT YOU ARE DOING --------
# ------------------------------------------------------------------------------
# Delete Images Variables                         [Destructive]
# ------------------------------------------------------------------------------
export RELEASE_TO_DELETE="${VERSION}"  # Example: "x.y.z" | Default: empty.
export RELEASE_TO_KEEP=""              # Example: "x.y.z" | Default: empty.
export TARGET_REGISTRY="127.0.0.1:12443"
export PREVIEW="false"
export PRIVATE_REGISTRY_PUSH_USER=""
export PRIVATE_REGISTRY_PUSH_PASSWORD=""
export FORCE=1
#------------------------------------------------------------------------------
#------DO NOT EDIT ABOVE THIS LINE UNLESS YOU KNOW WHAT YOU ARE DOING --------

# ------------------------------------------------------------------------------
# Proxy server:                                 [Optional - Edit if applicable]
# ------------------------------------------------------------------------------
# export PROXY_HOST=<enter your proxy server hostname>
# export PROXY_PORT=<enter your proxy server port number>
# export PROXY_USER=<enter your proxy server username>
# export PROXY_PASSWORD=<enter your proxy server password>
# export NO_PROXY_LIST=<a comma-separated list of domain names>