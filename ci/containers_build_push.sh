#!/bin/bash

# This script is not intended for humans.  It should be run by secure
# (maintainer-only) cron-like automation or in maintainer-authorized PRs.
# Its primary purpose is to build and push multi-arch skopeo, buildah, podman
# container images to multiple locations.  The destination repository namespace
# as well as the image contents are controlled by the "FLAVOR" argument
# described below.
#
# The first argument to the script, should be the git URL of the repository
# containing the build context.  This is assumed to be the $CWD. This URL will
# be used to add standard labels to the images identifying the source build
# context.
#
# The second argument to this script is the path (relative to the first argument)
# of the build context subdirectory.  In other words, the subdirectory holding
# the `Containerfile`.  If no `Containerfile` is found, the build will fail.
#
# The third argument indicates the image "FLAVOR", which will be passed into
# the build as a `--build-arg`.  This is used by the `Containerfile` to alter
# the build to produce a 'stable', 'immutable', 'testing', or 'upstream' image.
# Importantly, this value also determines where the image is pushed, see the
# top-level README.md for more details.
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

if [[ "$#" -lt 3 ]]; then
    #shellcheck disable=SC2145
    die "Must be called with at least three arguments, got '$*'"
fi

req_env_vars CI SCRIPT_PATH

# Assume transitive debugging state for build-push.sh if set
if [[ "$(automation_version | cut -d '.' -f 1)" -ge 4 ]]; then
    # Valid for version 4.0.0 and above only
    export A_DEBUG
else
    export DEBUG
fi

# Arches to build by default - may be overridden for testing
ARCHES="${ARCHES:-amd64,ppc64le,s390x,arm64}"

# First arg, URL for repository for informational purposes
REPO_URL="$1"

# Make allowances for system testing
if [[ ! "$REPO_URL" =~ github\.com ]] && [[ ! "$REPO_URL" =~ ^file:///tmp/ ]]; then
    die "Script requires a repo hosted on github, received '$REPO_URL'."
fi

# Second arg (CTX_SUB) is the context subdirectory relative to the clone path
CTX_SUB="$2"

# Third arg is the FLAVOR build-arg value
FLAVOR_NAME="$3"

_REG="quay.io"
if [[ "$CTX_SUB" =~ testing ]]; then
    dbg "System tests are running, using example/test registry name."
    _REG="example.com"
fi

REPO_FQIN="$_REG/$CTX_SUB/$FLAVOR_NAME"
if [[ "$FLAVOR_NAME" == "immutable" ]]; then
    # Only the image version-tag varies
    REPO_FQIN="$_REG/$CTX_SUB/stable"
fi
req_env_vars REPO_URL CTX_SUB FLAVOR_NAME

# Common library defines SCRIPT_FILENAME
# shellcheck disable=SC2154
dbg "$SCRIPT_FILENAME operating constants:
    REPO_URL=$REPO_URL
    CTX_SUB=$CTX_SUB
    FLAVOR_NAME=$FLAVOR_NAME
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

declare -a build_args
if [[ "$FLAVOR_NAME" == "immutable" ]]; then
    build_args=("--build-arg=FLAVOR=stable")
else
    build_args=("--build-arg=FLAVOR=$FLAVOR_NAME")
fi

head_sha=$(git rev-parse HEAD)
dbg "HEAD is $head_sha"

# Docs should always be in one of two places, otherwise don't list any.
docs_url=""
for _docs_subdir in "$CTX_SUB/README.md" "$(dirname $CTX_SUB)/README.md"; do
    if [[ -r "./$_docs_subdir" ]]; then
        dbg "Found README.md under './$_docs_subdir'"
        docs_url="${REPO_URL%.git}/blob/${head_sha}/$_docs_subdir"
        break
    fi
done

# Labels to add to all images as per
# https://specs.opencontainers.org/image-spec/annotations/?v=v1.0.1
declare -a label_args

# Use both labels and annotations since some older tools only support labels
# Ref: https://github.com/opencontainers/image-spec/blob/main/annotations.md
for arg in "--label" "--annotation"; do
    label_args+=(\
        "$arg=org.opencontainers.image.created=$(date -u --iso-8601=seconds)"
        "$arg=org.opencontainers.image.authors=podman@lists.podman.io"
        "$arg=org.opencontainers.image.source=${REPO_URL%.git}/blob/${head_sha}/${CTX_SUB}/"
        "$arg=org.opencontainers.image.revision=$head_sha"
    )

    if [[ -n "$docs_url" ]]; then
        label_args+=("$arg=org.opencontainers.image.documentation=${docs_url}")
    fi

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

# SCRIPT_PATH is defined by the automation library
# shellcheck disable=SC2154
modcmdarg="$SCRIPT_PATH/tag_version.sh $FLAVOR_NAME"

# For stable images, the version number of the command is needed for tagging and labeling.
if [[ "$FLAVOR_NAME" == "stable" || "$FLAVOR_NAME" == "immutable" ]]; then
    # only native arch is needed to extract the version
    dbg "Building temporary local-arch image to extract $FLAVOR_NAME version number"
    fqin_tmp="$CTX_SUB:temp"
    showrun podman build --arch=amd64 -t $fqin_tmp "${build_args[@]}" ./$CTX_SUB

    case "$CTX_SUB" in
        skopeo*) version_cmd="--version" ;;
        buildah*) version_cmd="buildah --version" ;;
        podman*) version_cmd="podman --version" ;;
        testing*) version_cmd="cat FAKE_VERSION" ;;
        *) die "Unknown/unsupported context '$CTX_SUB'" ;;
    esac

    pvcmd="podman run -i --rm $fqin_tmp $version_cmd"
    dbg "Extracting version with command: $pvcmd"
    version_output=$($pvcmd)
    dbg "version output: '$version_output'"
    img_cmd_version=$(awk -r -e '/^.+ version /{print $3}' <<<"$version_output")
    dbg "parsed version: $img_cmd_version"
    test -n "$img_cmd_version"

    label_args+=("--label=org.opencontainers.image.version=$img_cmd_version"
                 "--annotation=org.opencontainers.image.version=$img_cmd_version")

    # tag-version.sh expects this arg. when FLAVOR_NAME=stable
    modcmdarg+=" $img_cmd_version"

    dbg "Building $FLAVOR_NAME manifest-list '$_REG/containers/$CTX_SUB'"

    for arg in "--label" "--annotation"; do
        label_args+=("$arg=org.opencontainers.image.url=https://$_REG/containers/$CTX_SUB")
    done

    # Stable images get pushed to 'containers' namespace as latest & version-tagged.
    # Immutable images are only version-tagged, and are never pushed if they already
    # exist.
    showrun build-push.sh \
        $_DRNOPUSH \
        --arches="$ARCHES" \
        --modcmd="$modcmdarg" \
        "$_REG/containers/$CTX_SUB" \
        "./$CTX_SUB" \
        "${build_args[@]}" \
        "${label_args[@]}"
elif [[ "$FLAVOR_NAME" == "testing" ]]; then
    label_args+=("--label=quay.expires-after=30d"
                 "--annotation=quay.expires-after=30d")
elif [[ "$FLAVOR_NAME" == "upstream" ]]; then
    label_args+=("--label=quay.expires-after=15d"
                 "--annotation=quay.expires-after=15d")
fi

dbg "Building manifest-list '$REPO_FQIN'"

for arg in "--label" "--annotation"; do
    label_args+=("$arg=org.opencontainers.image.url=https://${REPO_FQIN}")
done

# All flavors are pushed to quay.io/<reponame>/<flavor>, both
# latest and version-tagged (if available). Stable + Immutable
# images are only version-tagged, and are never pushed if they
# already exist.
showrun build-push.sh \
    $_DRNOPUSH \
    --arches="$ARCHES" \
    --modcmd="$modcmdarg" \
    "$REPO_FQIN" \
    "./$CTX_SUB" \
    "${build_args[@]}" \
    "${label_args[@]}"
