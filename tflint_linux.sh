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
#   Uninstall tflint (automatic)            : ./tflint.sh --remove
#   Uninstall tflint (manual)               :  sudo rm /usr/local/bin/tflint

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

# Install TFLint if missing
RELEASE_ZIP_NAME="tflint_linux_amd64.zip"
#Check workstation arch and choose the right release
if [[ $(uname -m) == "arm64" ]]; then
    RELEASE_ZIP_NAME="tflint_darwin_arm64.zip"
else
    RELEASE_ZIP_NAME="tflint_linux_amd64.zip"
fi
RELEASE_ZIP_PATH="${TFLINT_DIR}/${RELEASE_ZIP_NAME}"
if [ ! "${SKIP_CHECK}" == "1" ] || [ ! "${FORCE_INSTALL}" == "1" ]; then
    echo -e '\nChecking latest TFLint version ...'
    LATEST_SHA_STRING=$(
        curl -Ls "$(curl -Ls https://api.github.com/repos/terraform-linters/tflint/releases/latest |
            grep -m 1 -o -E "https://.+?checksums.txt")" |
            grep -m 1 -o -E "^([[:alnum:]])+\s+${RELEASE_ZIP_NAME}"
    )
    INSTALLED_SHA_STRING=
    if [ -f "${TFLINT_ZIP_SHA}" ]; then
        INSTALLED_SHA_STRING=$(cat "${TFLINT_ZIP_SHA}")
    fi
fi
if ! command -v ${TFLINT_BIN} &>/dev/null || [ "${FORCE_INSTALL}" == "1" ] || [ ! "${INSTALLED_SHA_STRING}" = "${LATEST_SHA_STRING}" ]; then
    if ! command -v ${TFLINT_BIN} &>/dev/null || [ "${FORCE_INSTALL}" == "1" ]; then
        echo -e '\nInstalling TFLint ...'
    elif [ ! "${INSTALLED_SHA_STRING}" = "${LATEST_SHA_STRING}" ]; then
        echo -e '\nUpgrading TFLint ...'
    fi
    mkdir -p "${TFLINT_DIR}"
    curl -Ls "$(curl -Ls https://api.github.com/repos/terraform-linters/tflint/releases/latest |
        grep -o -E "https://.+?${RELEASE_ZIP_NAME}")" -o "${RELEASE_ZIP_PATH}"
    unzip -o "${RELEASE_ZIP_PATH}" -d "${TFLINT_DIR}"
    echo "${LATEST_SHA_STRING}" >"${TFLINT_ZIP_SHA}"
    rm "${RELEASE_ZIP_PATH}"

    # Add install dir to .gitignore when needed
    if [ -f "${GITIGNORE_FILE}" ]; then
        TFLINT_IS_IN_GITIGNORE_FILE=$(grep -xc '\*\*/\.tflint/\*' "${GITIGNORE_FILE}")
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
    curl -s "${TFLINT_DEFAULT_CFG_URL}" -o "${TFLINT_CFG}"
fi

# Abort if config file is still missing
if [ ! -f "${TFLINT_CFG}" ]; then
    echo -e "\nMissing TFLint config file at '${TFLINT_CFG}'!"
    exit 255
fi

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
