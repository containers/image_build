#!/bin/bash

# This script is intended to be run by Cirrus-CI to validate PR
# content prior to building any images.  It should not be run
# under any other context.

set -eo pipefail

source /etc/automation_environment
source $AUTOMATION_LIB_PATH/common_lib.sh

req_env_vars CIRRUS_PR CIRRUS_BASE_SHA CIRRUS_PR_TITLE CIRRUS_USER_PERMISSION

show_env_vars

# Defined by Cirrus-CI
# shellcheck disable=SC2154
[[ "$CIRRUS_CI" == "true" ]] || \
  die "This script is only/ever intended to be run by Cirrus-CI."

# This is imperfect security-wise, but attempt to catch an accidental
# change in Cirrus-CI Repository settings.  Namely the hard-to-read
# "slider" that enables non-contributors to run Cirrus-CI jobs.  We
# don't want that on this repo, ever. because there are sensitive
# secrets in use. This variable is set by CI and validated non-empty above
# shellcheck disable=SC2154
if [[ "$CIRRUS_USER_PERMISSION" != "write" ]] && [[ "$CIRRUS_USER_PERMISSION" != "admin" ]]; then
  die "CI Execution not supported with permission level '$CIRRUS_USER_PERMISSION'"
fi

### The following checks only apply if validating a PR
if [[ -z "$CIRRUS_PR" ]]; then
  echo "Not validating IMG_SFX changes outside of a PR"
  exit 0
fi

# For Docs-only PRs, no further checks are needed
# Variable is defined by Cirrus-CI at runtime
# shellcheck disable=SC2154
if [[ "$CIRRUS_PR_TITLE" =~ CI:DOCS ]]; then
  msg "This looks like a docs-only PR, skipping further validation checks."
  exit 0
fi

# TODO: Check other stuff
