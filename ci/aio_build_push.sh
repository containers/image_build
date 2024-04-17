#!/bin/bash

# This script is not intended for humans.  It should be run by secure
# (maintainer-only) cron-like automation or in maintainer-authorized PRs.
# Its primary purpose is to build and push the multi-arch all-in-one (AIO)
# skopeo, buildah, podman container image.
#
# The first argument to the script, should be the git URL of the repository
# containing the build context.  This is assumed to be the $CWD. This URL will
# be used to add several labels the images identifying the context source.
#
# Optionally, the `$ARCHES` environment variable may be set to a comma-separated
# list of golang-centric architectures to include in the build.  It is assumed
# that the necessary emulation is setup to handle building of non-native arches.
# Note: these builds will run in parallel, which can make the output difficult
# to read.

set -eo pipefail

if [[ -r "/etc/automation_environment" ]]; then
    source /etc/automation_environment  # defines AUTOMATION_LIB_PATH
    #shellcheck disable=SC1090,SC2154
    source "$AUTOMATION_LIB_PATH/common_lib.sh"
    dbg "Using automation common library version $(<$AUTOMATION_LIB_PATH/../AUTOMATION_VERSION)"
else
    echo "Expecting to find automation common library installed."
    exit 1
fi

if [[ -z $(type -P build-push.sh) ]]; then
    die "It does not appear that build-push.sh is installed properly"
fi

if [[ -z "$1" ]]; then
    die "Expecting a git repository URI as the first argument."
fi

# Assume transitive debugging state for build-push.sh if set
export A_DEBUG

# Arches to build by default - may be overridden for testing
ARCHES="${ARCHES:-amd64,ppc64le,s390x,arm64}"

# First arg, URL for repository for informational purposes
REPO_URL="$1"

_REG="quay.io"

# Make allowances for system testing
if [[ ! "$REPO_URL" =~ github\.com ]] && [[ ! "$REPO_URL" =~ ^file:///tmp/ ]]; then
    die "Script requires a repo hosted on github, received '$REPO_URL'."
    _REG="example.com"
fi

REPO_FQIN="$_REG/containers/aio"

req_env_vars REPO_URL CI SCRIPT_PATH

# Common library defines SCRIPT_FILENAME
# shellcheck disable=SC2154
dbg "$SCRIPT_FILENAME operating constants:
    REPO_URL=$REPO_URL
    ARCHES=$ARCHES
    REPO_FQIN=$REPO_FQIN
"

# Set non-zero to avoid actually executing build-push, simply print
# the command-line that would have been executed
DRYRUN=${DRYRUN:-0}
_DRNOPUSH=""
if ((DRYRUN)); then
    _DRNOPUSH="--nopush"
    warn "Operating in dry-run mode with $_DRNOPUSH"
fi

### MAIN

head_sha=$(git rev-parse HEAD)
dbg "HEAD is $head_sha"

# Docs should always be in the context directory.
[[ -r "./aio/README.md" ]] || \
    die "Expected to find $PWD/aio/README.md file"
docs_url="${REPO_URL%.git}/blob/${head_sha}/aio/README.md"

# There's no useful way to track a combined podman, buildah, and skopeo version.
version_tag=$(date -u +v%Y.%m.%d)
# Note: There's no actual "aio" FLAVOR, the argument is being abused here
# to avoid writing an entirely separate tag_version.sh.
# SCRIPT_PATH is defined by the automation library
# shellcheck disable=SC2154
modcmdarg="$SCRIPT_PATH/tag_version.sh aio $version_tag"

# Labels to add to all images as per
# https://specs.opencontainers.org/image-spec/annotations/?v=v1.0.1
declare -a label_args

# Use both labels and annotations since some older tools only support labels
# Ref: https://github.com/opencontainers/image-spec/blob/main/annotations.md
for arg in "--label" "--annotation"; do
    label_args+=(\
        "$arg=org.opencontainers.image.created=$(date -u --iso-8601=seconds)"
        "$arg=org.opencontainers.image.authors=podman@lists.podman.io"
        "$arg=org.opencontainers.image.url=https://$_REG/containers/aio"
        "$arg=org.opencontainers.image.source=${REPO_URL%.git}/blob/${head_sha}/aio/"
        "$arg=org.opencontainers.image.revision=$head_sha"
        "$arg=org.opencontainers.image.version=$version_tag"
        "$arg=org.opencontainers.image.documentation=${docs_url}"
    )

    # Save users from themselves, block super-duper old versions from being used
    label_args+=("$arg=quay.expires-after=1y")

    # Definitely not any official spec., but offers a quick reference to exactly what produced
    # the images and it's current signature.
    label_args+=(\
        "$arg=built.by.repo=${REPO_URL}"
        "$arg=built.by.commit=${head_sha}"
        "$arg=built.by.exec=$(basename ${BASH_SOURCE[0]})"
        "$arg=built.by.digest=sha256:$(sha256sum<${BASH_SOURCE[0]} | awk '{print $1}')"
    )

    # Script may not be running under Cirrus-CI
    if [[ -n "$CIRRUS_TASK_ID" ]]; then
        label_args+=("$arg=built.by.logs=https://cirrus-ci.com/task/$CIRRUS_TASK_ID")
    fi
done

dbg "Building AIO manifest-list '$_REG/containers/aio"
showrun build-push.sh \
    $_DRNOPUSH \
    --arches="$ARCHES" \
    --modcmd="$modcmdarg" \
    "$_REG/containers/aio" \
    "./aio"
