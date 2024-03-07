#!/bin/bash

# This script is intended to be run from a task using a pre-existing
# build-push VM image (having an image-suffix from the IMG_SFX file).
# It's purpose is to install the latest version of the scripts in the
# `bin` directory onto the system.
#
# WARNING: Use under any other circumstances will probably screw things up.

# Common automation library pre-installed into the build-push VM
if [[ -r /etc/automation_environment ]]; then
    # Defines AUTOMATION_LIB_PATH and updates PATH
    source /etc/automation_environment
    source "$AUTOMATION_LIB_PATH/common_lib.sh"
else
    echo "ERROR: The common automation library has not been installed." > /dev/stderr
    exit 1
fi

# Defined by common automation library
# shellcheck disable=SC2154
cd $(dirname "${BASH_SOURCE[0]}") || exit 1

# Must be installed into $AUTOMATION_LIB_PATH/../bin which is also now on $PATH
install -g root -o root -m 550 ./bin/* $AUTOMATION_LIB_PATH/../bin/
