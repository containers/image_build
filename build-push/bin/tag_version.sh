#!/bin/bash

# This script is not intended for humans.  It should only be referenced
# as an argument to the build-push.sh `--modcmd` option.  It's purpose
# is to ensure stable images are re-tagged with a verison-number
# using a specific scheme, cooresponding to the included tool's version.
# It expects two arguments, the first is the "flavor" of the image.
# Typically 'upstream', 'testing', or 'stable'.  The second argument
# is optional, when provided it should be the container-image's tool
# version number (e.g. podman version).

set -eo pipefail

if [[ -r "/etc/automation_environment" ]]; then
    source /etc/automation_environment  # defines AUTOMATION_LIB_PATH
    #shellcheck disable=SC1090,SC2154
    source "$AUTOMATION_LIB_PATH/common_lib.sh"
else
    echo "Unexpected operating environment"
    exit 1
fi

# Vars defined by build-push.sh spec. for mod scripts
req_env_vars SCRIPT_FILENAME SCRIPT_FILEPATH RUNTIME PLATFORMOS FQIN CONTEXT \
             PUSH ARCHES REGSERVER NAMESPACE IMGNAME MODCMD

if [[ "$#" -lt 1 ]]; then
    # Defined by common automation library
    # shellcheck disable=SC2154
    die "$SCRIPT_FILENAME expects at least one argument"
fi

if [[ "$#" -ge 2 ]]; then
    FLAVOR_NAME="$1"
    # Version is optional
    unset VERSION
    [[ -z "$2" ]] || \
        VERSION="v${2#v}"
fi

if [[ -z "$FLAVOR_NAME" ]]; then
    # Defined by common_lib.sh
    # shellcheck disable=SC2154
    warn "$SCRIPT_FILENAME passed empty flavor-name argument."
elif [[ -z "$VERSION" ]]; then
    warn "$SCRIPT_FILENAME received empty version argument."
fi

# shellcheck disable=SC2154
dbg "$SCRIPT_FILENAME operating on '$FLAVOR_NAME' flavor of '$FQIN' with tool version '$VERSION' (optional)"

if [[ "$FLAVOR_NAME" == "stable" ]]; then
    # Stable images must all be tagged with a version number.
    # Confirm this value is passed in by caller.
    if grep -E -q '^v[0-9]+\.[0-9]+\.[0-9]+'<<<"$VERSION"; then
        msg "Using provided image command version '$VERSION'"
    else
        die "Encountered unexpected/non-conforming version '$VERSION'"
    fi

    # shellcheck disable=SC2154
    $RUNTIME tag $FQIN:latest $FQIN:$VERSION
    msg "Successfully tagged $FQIN:$VERSION"

    # Tag as x.y to provide a consistent tag even for a future z+1
    xy_ver=$(awk -F '.' '{print $1"."$2}'<<<"$VERSION")
    $RUNTIME tag $FQIN:latest $FQIN:$xy_ver
    msg "Successfully tagged $FQIN:$xy_ver"

    # Tag as x to provide consistent tag even for a future y+1
    x_ver=$(awk -F '.' '{print $1}'<<<"$xy_ver")
    $RUNTIME tag $FQIN:latest $FQIN:$x_ver
    msg "Successfully tagged $FQIN:$x_ver"
else
    warn "$SCRIPT_FILENAME not version-tagging for '$FLAVOR_NAME' flavor'$FQIN'"
fi
