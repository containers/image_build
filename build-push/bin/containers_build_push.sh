#!/bin/bash

# This script is not intended for humans.  It should be run by secure
# (maintainer-only) cron-like automation to service the skopeo, buildah,
# and podman repositories.  It's purpose is to produce a multi-arch container
# image based on the contents of a repository context subdirectory from their
# respective 'main' branches.
#
# The first argument to the script, should be the git URL of the repository
# containing the build context.  If prefixed by a '.' character, the repository
# will not be cloned, and instead $CWD will be used.  In all cases this URL will
# be used to add several labels the produced images.
#
# The second argument to this script is the relative path to the build context
# subdirectory.  The basename of this subdirectory may (see next paragraph)
# indicate the image flavor (i.e. `upstream`, `testing`, or `stable`). Depending
# on this value, the image may be pushed to multiple container registries
# under slightly different rules (see the next option).
#
# If the basename of the context directory (second argument) does NOT reflect
# the image flavor, this name may be passed in as a third argument.  Handling
# of this argument may be repository-specific, so check the actual code below
# to understand it's behavior.

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

# Careful: Changing the error message below could break auto-update test.
if [[ "$#" -lt 2 ]]; then
    #shellcheck disable=SC2145
    die "Must be called with at least two arguments, got '$*'"
fi

req_env_vars CI

# Assume transitive debugging state for build-push.sh if set
if [[ "$(automation_version | cut -d '.' -f 1)" -ge 4 ]]; then
    # Valid for version 4.0.0 and above only
    export A_DEBUG
else
    export DEBUG
fi

# Arches to build by default - may be overridden for testing
ARCHES="${ARCHES:-amd64,ppc64le,s390x,arm64}"

# First arg (REPO_URL) is the clone URL for repository for informational purposes
REPO_URL="$1"
[[ "${REPO_URL:0:1}" != "." ]] || \
    REPO_URL="${1:1}"

REPO_NAME=$(basename "${REPO_URL%.git}")

if [[ ! "$REPO_URL" =~ github\.com ]] && [[ ! "$REPO_URL" =~ testing ]]; then
  die "Script requires a repo hosted on github, received '$REPO_URL'."
fi

# Second arg (CTX_SUB) is the context subdirectory relative to the clone path
CTX_SUB="$2"
# Historically, the basename of second arg set the image flavor(i.e. `upstream`,
# `testing`, or `stable`).  For cases where this convention doesn't fit,
# it's possible to pass the flavor-name as the third argument.  Both methods
# will populate a "FLAVOR" build-arg value.
if [[ "$#" -lt 3 ]]; then
    FLAVOR_NAME=$(basename "$CTX_SUB")
elif [[ "$#" -ge 3 ]]; then
    FLAVOR_NAME="$3"  # An empty-value is valid
else
    die "Expecting a non-empty third argument indicating the FLAVOR build-arg value."
fi
_REG="quay.io"
if [[ "$REPO_NAME" =~ testing ]]; then
    dbg "Unittests are running, using example/test registry name."
    _REG="example.com"
fi
REPO_FQIN="$_REG/$REPO_NAME/$FLAVOR_NAME"
req_env_vars REPO_URL REPO_NAME CTX_SUB FLAVOR_NAME

# Common library defines SCRIPT_FILENAME
# shellcheck disable=SC2154
dbg "$SCRIPT_FILENAME operating constants:
    REPO_URL=$REPO_URL
    REPO_NAME=$REPO_NAME
    CTX_SUB=$CTX_SUB
    FLAVOR_NAME=$FLAVOR_NAME
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

if [[ "${1:0:1}" != "." ]]; then
    dbg "Cloning $REPO_URL and using its $CTX_SUB as build context"
    # SCRIPT_PATH defined by automation library
    # shellcheck disable=SC2154
    CLONE_TMP=$(mktemp -p "" -d "tmp_${SCRIPT_FILENAME}_XXXX")
    trap "rm -rf '$CLONE_TMP'" EXIT
    showrun git clone --depth 1 "$REPO_URL" "$CLONE_TMP"
    cd "$CLONE_TMP"
else
    dbg "Not cloning, using $PWD/$CTX_SUB as build context"
fi

### MAIN

declare -a build_args
if [[ -n "$FLAVOR_NAME" ]]; then
    build_args=("--build-arg=FLAVOR=$FLAVOR_NAME")
fi

head_sha=$(git rev-parse HEAD)
dbg "HEAD is $head_sha"

# Docs should always be in one of two places, otherwise don't list any.
DOCS_URL=""
for _docs_subdir in "$CTX_SUB/README.md" "$(dirname $CTX_SUB)/README.md"; do
    if [[ -r "./$_docs_subdir" ]]; then
        dbg "Found README.md under '$CLONE_TMP/$_docs_subdir'"
        DOCS_URL="${REPO_URL%.git}/blob/${head_sha}/$_docs_subdir"
    fi
done

req_env_vars CIRRUS_TASK_ID CIRRUS_CHANGE_IN_REPO CIRRUS_REPO_NAME

# Labels to add to all images as per
# https://specs.opencontainers.org/image-spec/annotations/?v=v1.0.1
declare -a label_args

# Use both labels and annotations since some older tools only support labels
# CIRRUS_TASK_ID provided by CI and verified non-empty
# shellcheck disable=SC2154
for arg in "--label" "--annotation"; do
  label_args+=(\
    # Avoid any ambiguity as to the source that produced the image.
    # This requires REPO_URL is hosted on github (validated above)
    "$arg=org.opencontainers.image.source=${REPO_URL%.git}/blob/${head_sha}/${CTX_SUB}/"
    "$arg=org.opencontainers.image.revision=$head_sha"
    "$arg=org.opencontainers.image.created=$(date -u --iso-8601=seconds)"
    "$arg=org.opencontainers.image.authors=podman@lists.podman.io"
  )

  if [[ -n "$DOCS_URL" ]]; then
    label_args+=(\
      "$arg=org.opencontainers.image.documentation=${DOCS_URL}"
    )
  fi

  # Perhaps slightly outside the intended purpose, but it kind of fits, and may help
  # somebody ascertain provenance a little better.  Note: Even if the console logs
  # are blank, the Cirrus-CI GraphQL API keeps build and task metadata for years.
  label_args+=(\
    "$arg=org.opencontainers.image.url=https://cirrus-ci.com/task/$CIRRUS_TASK_ID"
  )

  # Definitely not any official spec., but offers a quick reference to exactly what produced
  # the images and it's current signature.
  label_args+=(\
    "$arg=built.by.repo=${CIRRUS_REPO_NAME}"
    "$arg=built.by.commit=${CIRRUS_CHANGE_IN_REPO}"
    "$arg=built.by.exec=$(basename ${BASH_SOURCE[0]})"
    "$arg=built.by.digest=sha256:$(sha256sum<${BASH_SOURCE[0]} | awk '{print $1}')"
  )
done

modcmdarg="tag_version.sh $FLAVOR_NAME"

# For stable images, the version number of the command is needed for tagging and labeling.
if [[ "$FLAVOR_NAME" == "stable" ]]; then
    # only native arch is needed to extract the version
    dbg "Building temporary local-arch image to extract stable version number"
    FQIN_TMP="$REPO_NAME:temp"
    showrun podman build -t $FQIN_TMP "${build_args[@]}" ./$CTX_SUB

    case "$REPO_NAME" in
        skopeo) version_cmd="--version" ;;
        buildah) version_cmd="buildah --version" ;;
        podman) version_cmd="podman --version" ;;
        testing) version_cmd="cat FAKE_VERSION" ;;
        *) die "Unknown/unsupported repo '$REPO_NAME'" ;;
    esac

    pvcmd="podman run -i --rm $FQIN_TMP $version_cmd"
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

    dbg "Building stable-flavor manifest-list '$_REG/containers/$REPO_NAME'"

    # Stable images get pushed to 'containers' namespace as latest & version-tagged
    showrun build-push.sh \
        $_DRNOPUSH \
        --arches="$ARCHES" \
        --modcmd="$modcmdarg" \
        "$_REG/containers/$REPO_NAME" \
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

# All images are pushed to quay.io/<reponame>, both
# latest and version-tagged (if available).
showrun build-push.sh \
    $_DRNOPUSH \
    --arches="$ARCHES" \
    --modcmd="$modcmdarg" \
    "$REPO_FQIN" \
    "./$CTX_SUB" \
    "${build_args[@]}" \
    "${label_args[@]}"
