#!/usr/bin/env bash

set -eo pipefail

# Perform linting of terraform code using TFLint.
#   - Loops over all *.tfvars (if any).
#   - Loops through all terraform module directories (if any).
#   - Prints summary.
#   - Exit code is sum of all exit codes for all permutations, 0 when there are no issues and 255 when prerequs ar not met.

# Prereqs:
# - unzip and jq available on the command line:
#       Debian/Ubuntu: sudo apt-get update && sudo apt-get install unzip jq -y
#       Mac: brew install jq
# - terrform init ,ust be performed prior in order for module directories to be linted
# On mac you need to install latest version of bash - using brew install bash

# Usage:
#   Install and run linting in current dir  : ./tflint.sh
#   Force install/upgrade tflint            : ./tflint.sh --force-install
#   Do not check for new tflint version     : ./tflint.sh --skip-latest-check
#   Run with specific version of tflint     : ./tflint.sh --use-version v0.54.0
#   Force re-install of plugins             : ./tflint.sh --re-init
#   Uninstall tflint (automatic)            : ./tflint.sh --remove
#   Uninstall tflint (manual)               :  sudo rm /usr/local/bin/tflint

FORCE_INSTALL="0"
UNINSTALL="0"
SKIP_CHECK="0"
RE_INIT="0"
TFLINT_VERSION="latest"

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
    # Support --force-install ex. for upgrading tflint
    -f | --force-install | --install)
        FORCE_INSTALL="1"
        shift
        ;;
    # Support --remove for removing .tflint directory
    -r | --remove | --uninstall)
        UNINSTALL="1"
        shift
        ;;
    # Support --skip-latest-check for disabling checking if currentliy installed tflint is latest
    -s | --skip-latest-check)
        SKIP_CHECK="1"
        shift
        ;;
    # Support --re-init for re-installing plugins
    -ri | --re-init)
        RE_INIT="1"
        shift
        ;;
    # Support --use-version for specifying version of tflint
    -uv | --use-version)
        TFLINT_VERSION="$2"
        shift
        shift
        ;;
    # Support --help for displaying help
    -h | --help)
        echo -e "\nOptions:"
        echo -e "  --force-install\t\tForce install/upgrade tflint"
        echo -e "  --remove\t\t\tUninstall tflint"
        echo -e "  --skip-latest-check\t\tDo not check for new tflint version"
        echo -e "  --re-init\t\t\tForce re-install of plugins"
        echo -e "  --use-version 'v0.54.0'\tRun with specific version of tflint"
        echo -e "  --help\t\t\tDisplay help"
        exit 0
        ;;
    *) # unknown option
        shift
        ;;
    esac
done

# Helper functions
get_abs_file_path() {
    # $1 : relative filename
    echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}

# Static variables
TFLINT_DIR=$(get_abs_file_path './.tflint')
TFLINT_BIN="${TFLINT_DIR}/tflint"
TFLINT_PLUGIN_DIR="${HOME}/.tflint.d/plugins"
TFLINT_ZIP_SHA="${TFLINT_DIR}/tflint_zip.sha"
TFLINT_CFG=$(get_abs_file_path './.tflint.hcl')
TFLINT_DEFAULT_CFG_URL='https://raw.githubusercontent.com/dsb-norge/terraform-tflint-wrappers/main/default.tflint.hcl'
TF_DIR='./.terraform'
TF_MODULES_FILE="${TF_DIR}/modules/modules.json"
GITIGNORE_FILE='./.gitignore'

# Header
SEP_LONG=$(echo '='$___{1..80} | tr -d ' ')
SEP_SHORT=$(echo '='$___{1..40} | tr -d ' ')
echo "${SEP_LONG}"
echo -e '\n\tTFLint - A Pluggable Terraform Linter\n'
echo "${SEP_LONG}"

# Uninstall?
if [ "${UNINSTALL}" == "1" ]; then
    echo -e '\nUninstalling TFLint ...'
    if [ -d "${TFLINT_DIR}" ]; then
        echo "Removing dir '${TFLINT_DIR}' ..."
        rm -rf "${TFLINT_DIR}" # no longer need the temp file
    fi
    if [ -d "${TFLINT_PLUGIN_DIR}" ]; then
        echo "Removing plugins dir '${TFLINT_PLUGIN_DIR}' ..."
        rm -rf "${TFLINT_PLUGIN_DIR}"
    fi
    echo -e 'Done.'
    exit 0
fi

# Check prereqs
if ! command -v jq --version &>/dev/null; then
    echo -e '\nMissing prerequsite: jq - commandline JSON processor. Please install manually.'
    exit 255
fi
if ! command -v unzip -v &>/dev/null; then
    echo -e '\nMissing prerequsite: unzip. Please install manually.'
    exit 255
fi
if [ ! -d "${TF_DIR}" ]; then
    echo -e '\nMissing ".terraform" directory. Please perform "terraform init" first.'
    exit 255
fi

# Check if github cli is installed and authenticated
USE_GH=0
if command -v gh --version &>/dev/null; then
    if gh auth status &>/dev/null; then
        echo -e 'Calls to github API will be made using the cli.'
        USE_GH=1
    fi
fi

# Install TFLint if missing
# Check workstation arch and choose the right release
if [[ $(uname -m) == "arm64" ]]; then
    RELEASE_ZIP_NAME="tflint_darwin_arm64.zip"
elif [[ $(uname -m) == "aarch64" ]] && [[ $(uname -s) == "Linux" ]]; then
    RELEASE_ZIP_NAME="tflint_linux_arm64.zip"
elif [[ $(uname -m) == "x86_64" ]] && [[ $(uname -s) == "Linux" ]]; then
    RELEASE_ZIP_NAME="tflint_linux_amd64.zip"
else
    echo -e "Architecture: $(uname -m)"
    echo -e "Operating system: $(uname -s)"
    echo -e '\nUnsupported architecture/OS. Exiting.'
    exit 255
fi

RELEASE_ZIP_PATH="${TFLINT_DIR}/${RELEASE_ZIP_NAME}"

# when:
#   user has asked for specific version
#   or user has not asked to skip the check AND has not asked to force install
if [ ! "${TFLINT_VERSION}" == "latest" ] || [ ! "${SKIP_CHECK}" == "1" ] && [ ! "${FORCE_INSTALL}" == "1" ]; then

    # Get the checksums for the desired release of tflint
    if [ "${TFLINT_VERSION}" == "latest" ]; then
        echo -e '\nChecking latest TFLint version ...'
        TFLINT_VERSION_RELEASE_URL="https://api.github.com/repos/terraform-linters/tflint/releases/latest"
    else
        echo -e "\nChecking for TFLint version: ${TFLINT_VERSION} ..."
        TFLINT_VERSION_RELEASE_URL="https://api.github.com/repos/terraform-linters/tflint/releases/tags/${TFLINT_VERSION}"
    fi
    if [ "${USE_GH}" == "1" ]; then
        if ! gh release view "${TFLINT_VERSION//latest/}" --repo terraform-linters/tflint --json 'id' &>/dev/null; then
            echo -e "\nFailed to get release information for TFLint version: ${TFLINT_VERSION}"
            echo -e "Are you sure the version exists?"
            echo -e "Please check https://github.com/terraform-linters/tflint/releases for available versions."
            exit 255
        fi
        if ! TFLINT_VERSION_SHA_STRING=$(
            # gh cli does not support 'latest' as version, we pass empty string to get the latest otherwise use the version supplied by the user
            gh release download "${TFLINT_VERSION//latest/}" --repo terraform-linters/tflint --pattern 'checksums.txt' --output - |
                grep --max-count=1 --only-matching --extended-regexp "^([[:alnum:]])+\s+${RELEASE_ZIP_NAME}"
        ); then
            echo -e "\nFailed to get checksum for TFLint version: ${TFLINT_VERSION}"
            echo -e "Unable to locate checksum for the file '${RELEASE_ZIP_NAME}' in the checksums.txt file."
            echo -e "Please verify that the checksums.txt file exists in the release here: https://github.com/terraform-linters/tflint/releases/tag/${TFLINT_VERSION}"
            echo -e "Also verify that the file '${RELEASE_ZIP_NAME}' exists as part of the release assets."
            exit 255
        fi
    else
        if ! TFLINT_RELEASE_JSON=$(curl --location --silent --fail "${TFLINT_VERSION_RELEASE_URL}"); then
            echo -e "\nFailed to get release information for TFLint version: ${TFLINT_VERSION}"
            echo -e "Are you sure the version exists?"
            echo -e "Please check https://github.com/terraform-linters/tflint/releases for available versions."
            exit 255
        fi
        if ! TFLINT_VERSION_CHECKSUM_URL=$(
            echo "${TFLINT_RELEASE_JSON}" | grep --max-count=1 --only-matching --extended-regexp "https://.+?checksums.txt"
        ); then
            echo -e "\nFailed to obtain checksums.txt for TFLint version: ${TFLINT_VERSION}"
            echo -e "Please verify that the file exists in the release here: https://github.com/terraform-linters/tflint/releases/tag/${TFLINT_VERSION}"
            exit 255
        fi
        if ! TFLINT_VERSION_SHA_STRING=$(
            curl --location --silent "${TFLINT_VERSION_CHECKSUM_URL}" |
                grep --max-count=1 --only-matching --extended-regexp "^([[:alnum:]])+\s+${RELEASE_ZIP_NAME}"
        ); then
            echo -e "\nFailed to get checksum for TFLint version: ${TFLINT_VERSION}"
            echo -e "Unable to locate checksum for the file '${RELEASE_ZIP_NAME}' in the checksums.txt file."
            exit 255
        fi
    fi

    # Get the checksum of the installed version of tflint (if any)
    INSTALLED_VERSION_SHA_STRING=
    if [ -f "${TFLINT_ZIP_SHA}" ]; then
        INSTALLED_VERSION_SHA_STRING=$(cat "${TFLINT_ZIP_SHA}")
    fi
fi

# when tflint is missing or user has asked to force install or the installed version is not that of the latest
if ! command -v ${TFLINT_BIN} &>/dev/null || [ "${FORCE_INSTALL}" == "1" ] || [ ! "${INSTALLED_VERSION_SHA_STRING}" = "${TFLINT_VERSION_SHA_STRING}" ]; then

    if ! command -v ${TFLINT_BIN} &>/dev/null || [ "${FORCE_INSTALL}" == "1" ]; then
        echo -e '\nInstalling TFLint ...'
    elif [ ! "${INSTALLED_VERSION_SHA_STRING}" = "${TFLINT_VERSION_SHA_STRING}" ]; then
        echo -e '\nChanging TFLint version ...'
    fi

    mkdir -p "${TFLINT_DIR}"

    # Download and install the latest version of tflint
    if [ "${USE_GH}" == "1" ]; then
        # gh cli does not support 'latest' as version, we pass empty string to get the latest otherwise use the version supplied by the user
        gh release download "${TFLINT_VERSION//latest/}" --repo terraform-linters/tflint --pattern "${RELEASE_ZIP_NAME}" --output "${RELEASE_ZIP_PATH}" --clobber
    else
        if [ "${TFLINT_VERSION}" == "latest" ]; then
            TFLINT_VERSION_RELEASE_URL="https://api.github.com/repos/terraform-linters/tflint/releases/latest"
        else
            TFLINT_VERSION_RELEASE_URL="https://api.github.com/repos/terraform-linters/tflint/releases/tags/${TFLINT_VERSION}"
        fi
        if ! LATEST_ZIP_URL=$(
            curl --location --silent --fail "${TFLINT_VERSION_RELEASE_URL}" |
            grep --only-matching --extended-regexp "https://.+?${RELEASE_ZIP_NAME}"
            ); then
            echo -e "\nFailed to get download URL for TFLint version: ${TFLINT_VERSION}"
            echo -e "Please verify that the version exists."
            echo -e "Please check https://github.com/terraform-linters/tflint/releases for available versions."
            exit 255
        fi
        curl --location --silent "${LATEST_ZIP_URL}" --output "${RELEASE_ZIP_PATH}"
    fi
    unzip -o "${RELEASE_ZIP_PATH}" -d "${TFLINT_DIR}" 1>/dev/null
    echo "${TFLINT_VERSION_SHA_STRING}" >"${TFLINT_ZIP_SHA}"
    rm "${RELEASE_ZIP_PATH}"

    # Add install dir to .gitignore if .gitignore file exists
    if [ -f "${GITIGNORE_FILE}" ]; then
        TFLINT_IS_IN_GITIGNORE_FILE=$(grep --line-regexp --count '\*\*/\.tflint/\*' "${GITIGNORE_FILE}")
        if [ "$TFLINT_IS_IN_GITIGNORE_FILE" -eq 0 ]; then
            echo -e "\nUpdate .gitignore: Exclude **/.tflint/* ..."
            echo -e '\n# Local tflint directories\n**/.tflint/*' >>"${GITIGNORE_FILE}"
        fi
    fi
fi

# Install default TFLint config if config is missing
if [ ! -f "${TFLINT_CFG}" ]; then
    echo -e "\nMissing TFLint config fetching default config ..."
    echo -e "Source: ${TFLINT_DEFAULT_CFG_URL}"
    echo -e "Target: ${TFLINT_CFG}"
    curl --silent "${TFLINT_DEFAULT_CFG_URL}" -o "${TFLINT_CFG}"
fi

# Abort if config file is still missing
if [ ! -f "${TFLINT_CFG}" ]; then
    echo -e "\nMissing TFLint config file at '${TFLINT_CFG}'!"
    exit 255
fi

# show the version of tflint
TFLINT_INSTALLED_VERSION="$(head -n 1 <(${TFLINT_BIN} --version))"
echo -e "\nUsing TFLint version: '${TFLINT_INSTALLED_VERSION}'"

# Re-init TFLint plugins if requested
if [ "${RE_INIT}" == "1" ]; then
    echo -e '\nRe-initializing TFLint plugins ...'
    if [ -d "${TFLINT_PLUGIN_DIR}" ]; then
        rm -rf "${TFLINT_PLUGIN_DIR}"
    fi
else
    echo -e '\nInitializing TFLint plugins ...'
fi

mkdir -p "${TFLINT_PLUGIN_DIR}"

# Install TFLint plugins
${TFLINT_BIN} --init 1>/dev/null

# Look for *.tfvars files
VAR_FILE_PREFIX=' --var-file='
VAR_FILES_ARG=('')
if ls ./*.tfvars &>/dev/null; then
    readarray -t VAR_FILES_ARG < <(for VAR_FILE in ./*.tfvars; do echo "${VAR_FILE_PREFIX}$(get_abs_file_path ${VAR_FILE})"; done)
fi

# Look for terraform module directories
#   Note: modules.json includes the root directories
if [ -f "${TF_MODULES_FILE}" ]; then
    LINT_IN_DIRS=()
    for MODULE_DIR in $(jq -r '[ .Modules[].Dir | select( startswith(".terraform") | not) ] | unique | sort | .[]' "${TF_MODULES_FILE}"); do
        # If directory actually exists queue it for linting
        if [ -d "${MODULE_DIR}" ]; then
            LINT_IN_DIRS+=("${MODULE_DIR}")
        fi
    done
else
    LINT_IN_DIRS=('.') # Lint only root directory when no modules are found
fi

# Loop over all directories
set +eo pipefail
declare -A TFLINT_RESULTS
for LINT_DIR in "${LINT_IN_DIRS[@]}"; do
    echo -e "\nLinting in: ${LINT_DIR}"
    echo "${SEP_SHORT}"
    # Loop over all *.tfvars (if any)
    for VAR_ARG in "${VAR_FILES_ARG[@]}"; do
        ${TFLINT_BIN} --config=${TFLINT_CFG} ${VAR_ARG} --chdir="${LINT_DIR}"
        TFLINT_RESULTS[${VAR_ARG}, "./${LINT_DIR}"]=$?
    done
done

echo -e '\n\nTFLint summary:'
echo "${SEP_SHORT}"
for VAR_ARG in "${VAR_FILES_ARG[@]}"; do
    for LINT_DIR in "${LINT_IN_DIRS[@]}"; do
        echo "$([[ ${TFLINT_RESULTS[${VAR_ARG}, "./${LINT_DIR}"]} -ne 0 ]] && echo 'failure ->' || echo 'success ->') ${VAR_ARG#$VAR_FILE_PREFIX} @ ./${LINT_DIR}"
    done
    echo ""
done
echo "${SEP_LONG}"

TFLINT_SUM_EXIT_CODES=$(
    IFS=+
    echo "$((${TFLINT_RESULTS[*]}))"
)
exit ${TFLINT_SUM_EXIT_CODES}
