#!/bin/bash

# Wrapper around `buildah build` with a post-build command and registry push.
#
# VENDORED from containers/automation build-push/bin/build-push.sh at commit
# 2cdb0b15ee03e7c8e97df72ff3216ec6752f320f.  Upstream no longer ships it.
# Changes: sources ci/lib.sh; dropped the $<NAMESPACE>_USERNAME/_PASSWORD
# lookup and registry_login() (the workflow logs in); dropped --prepcmd and
# the dead cleanup().

set -eo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/lib.sh"

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")

# Useful for non-standard installations & testing
RUNTIME="${RUNTIME:-$(type -P buildah||echo /bin/true)}"  # see init()

# Contract with ci/tag_version.sh -- see its req_env_vars call.
# $ARCHES is exported SPACE-separated; parse_args converts it from CSV.
_CMD_ENV="SCRIPT_FILEPATH RUNTIME PLATFORMOS FQIN CONTEXT
PUSH ARCHES REGSERVER NAMESPACE IMGNAME MODCMD"

# Simple error-message strings
E_FQIN="Must specify a valid 3-component FQIN w/o a tag, not:"
E_CONTEXT="Given context path is not an existing directory:"
E_ONEARCH="Must specify --arches=<value> with '=', and <value> being a comma-separated list, not:"
_E_MOD_SFX="with '=', and <value> being a (quoted) string, not:"
E_USAGE="
Usage: $(basename "${BASH_SOURCE[0]}") [options] <FQIN> <Context> [extra...]

With the required arguments:

    <FQIN> is the fully-qualified image name to build and push.  It must
    contain only three components: Registry FQDN:PORT, Namespace, and
    Image Name.   The image tag must NOT be specified, see --modcmd=<value>
    option below.

    <Context> is the full build-context DIRECTORY path containing the
    target Dockerfile or Containerfile.  This must be a local path to
    an existing directory.

Zero or more [options] and [extra...] optional arguments:

    --help if specified, will display this usage/help message.

    --arches=<value> specifies a comma-separated list of architectures
    to build.  When unspecified, the local system's architecture will
    be used. Architecture names must be the canonical values used/supported
    by golang and available/included in the base-image's manifest list.
    Note: The '=' is required.

    --modcmd=<value> specifies a bash string to execute after a successful
    build but prior to pushing any image(s).  Any embedded quoting will be
    preserved.  Output from the script will be displayed, but ignored.
    Any tags which should/shouldn't be pushed must be handled by this
    command/script (including complete removal or replacement). See the
    'Environment for...' section below for details on what env. vars.
    are made available for use by/substituted in <value>.

    --nopush will bypass pushing the built/tagged image(s).

    [extra...] specifies optional, additional arguments to pass when building
    images.  For example, this may be used to pass in [actual] build-args, or
    volume-mounts.

Environment for --modcmd

The shell environment for executing this string will contain the
following environment variables and their values at runtime:

$_CMD_ENV

Registry Authentication

    Unless --nopush is used, the caller is responsible for having logged
    into the registry beforehand (e.g. \`podman login\`).  Point
    \$REGISTRY_AUTH_FILE at a shared auth file if the login happened in a
    separate process.

Optional Environment Variables:

    \$RUNTIME specifies the complete path to an alternate executable
    to use for building.  Defaults to the location of 'buildah'.

    \$PARALLEL_JOBS specifies the number of builds to execute in parallel.
    When unspecified, it defaults to the number of processor (threads) on
    the system.
"

# Show an error message, followed by usage text to stderr
die_help() {
    local err="${1:-No error message specified}"
    msg "Please use --help for usage information."
    die "$err"
}

init() {
    # /bin/true is used by unit-tests
    if [[ "$RUNTIME" =~ true ]] || [[ ! $(type -P "$RUNTIME") ]]; then
        die_help "Unable to find \$RUNTIME ($RUNTIME) on path: $PATH"
    fi
    if [[ -n "$PARALLEL_JOBS" ]] && [[ ! "$PARALLEL_JOBS" =~ ^[0-9]+$ ]]; then
        PARALLEL_JOBS=""
    fi
    # Can't use $(uname -m) because (for example) "x86_64" != "amd64" in registries
    NATIVE_GOARCH="${NATIVE_GOARCH:-$($RUNTIME info --format='{{.host.arch}}')}"
    PARALLEL_JOBS="${PARALLEL_JOBS:-$($RUNTIME info --format='{{.host.cpus}}')}"

    dbg "Found native go-arch: $NATIVE_GOARCH"
    dbg "Found local CPU count: $PARALLEL_JOBS"

    if [[ -z "$NATIVE_GOARCH" ]]; then
        die_help "Unable to determine the local system architecture, is \$RUNTIME correct: '$RUNTIME'"
    elif ! type -P jq &>/dev/null; then
        die_help "Unable to find 'jq' executable on path: $PATH"
    fi

    # Not likely overridden, but keep the possibility open
    PLATFORMOS="${PLATFORMOS:-linux}"

    # Env. vars set by parse_args()
    FQIN=""                   # required (fully-qualified-image-name)
    CONTEXT=""                # required (directory path)
    PUSH=1                    # optional (1 means push, 0 means do not)
    ARCHES="$NATIVE_GOARCH"   # optional (Native architecture default)
    MODCMD=""                 # optional (--modcmd)
    declare -a BUILD_ARGS
    BUILD_ARGS=()             # optional
    REGSERVER=""              # parsed out of $FQIN
    NAMESPACE=""              # parsed out of $FQIN
    IMGNAME=""                # parsed out of $FQIN
}

parse_args() {
    local -a args
    local arg
    local archarg

    dbg "in parse_args()"

    if [[ $# -lt 2 ]]; then
        die_help "Must specify non-empty values for required arguments."
    fi

    args=("$@")  # Special-case quoting: Will NOT separate quoted arguments
    for arg in "${args[@]}"; do
        dbg "Processing parameter '$arg'"
        case "$arg" in
            --arches=*)
                archarg=$(tr ',' ' '<<<"${arg:9}")
                if [[ -z "$archarg" ]]; then die_help "$E_ONEARCH '$arg'"; fi
                ARCHES="$archarg"
                ;;
            --arches)
                # Argument format not supported (to simplify parsing logic)
                die_help "$E_ONEARCH '$arg'"
                ;;
            --modcmd=*)
                # Bash argument processing automatically strips any outside quotes
                MODCMD="${arg:9}"
                ;;
            --modcmd)
                die_help "Must specify --modcmd=<value> $_E_MOD_SFX '$arg'"
                ;;
            --nopush)
                dbg "Nopush flag detected, will NOT push built images."
                PUSH=0
                ;;
            *)
                if [[ -z "$FQIN" ]]; then
                    dbg "Grabbing FQIN parameter: '$arg'."
                    FQIN="$arg"
                    REGSERVER=$(awk -F '/' '{print $1}' <<<"$FQIN")
                    NAMESPACE=$(awk -F '/' '{print $2}' <<<"$FQIN")
                    IMGNAME=$(awk -F '/' '{print $3}' <<<"$FQIN")
                elif [[ -z "$CONTEXT" ]]; then
                    dbg "Grabbing Context parameter: '$arg'."
                    CONTEXT=$(realpath -e -P $arg || die_help "$E_CONTEXT '$arg'")
                else
                    # Hack: Allow array addition to handle any embedded special characters
                    # shellcheck disable=SC2207
                    BUILD_ARGS+=($(printf "%q" "$arg"))
                fi
                ;;
        esac
    done

    # validate parsed argument contents
    if [[ -z "$FQIN" ]]; then
        die_help "$E_FQIN '<empty>'"
    elif [[ -z "$REGSERVER" ]] || [[ -z "$NAMESPACE" ]] || [[ -z "$IMGNAME" ]]; then
        die_help "$E_FQIN '$FQIN'"
    elif [[ -z "$CONTEXT" ]]; then
        die_help "$E_CONTEXT ''"
    fi
    test "$(tr -d -c '/' <<<"$FQIN" | wc -c)" = '2' || \
        die_help "$E_FQIN '$FQIN'"
    test -r "$CONTEXT/Containerfile" || \
        test -r "$CONTEXT/Dockerfile" || \
        die_help "Given context path does not contain a Containerfile or Dockerfile: '$CONTEXT'"

    dbg "Processed:
    RUNTIME='$RUNTIME'
    FQIN='$FQIN'
    CONTEXT='$CONTEXT'
    PUSH='$PUSH'
    ARCHES='$ARCHES'
    MODCMD='$MODCMD'
    BUILD_ARGS=$(echo -n "${BUILD_ARGS[@]}")
    REGSERVER='$REGSERVER'
    NAMESPACE='$NAMESPACE'
    IMGNAME='$IMGNAME'
"
}

# Build may have a LOT of output, use a standard stage-marker
# to ease reading and debugging from the wall-o-text
stage_notice() {
    local message
    message="$*"
    (
        echo "############################################################"
        echo "$message"
        echo "############################################################"
    ) >> /dev/stderr
}

parallel_build() {
    local arch
    local platforms=""
    local _fqin
    local -a _args

    _fqin="$1"
    dbg "in parallel_build($_fqin)"
    req_env_vars FQIN ARCHES CONTEXT REGSERVER NAMESPACE IMGNAME
    req_env_vars PARALLEL_JOBS PLATFORMOS RUNTIME _fqin

    for arch in $ARCHES; do
        platforms="${platforms:+$platforms,}$PLATFORMOS/$arch"
    done

    # Need to build up the command from parts b/c array conversion is handled
    # in strange and non-obvious ways when it comes to embedded whitespace.
    _args=(--layers --force-rm --jobs="$PARALLEL_JOBS" --platform="$platforms"
           --manifest="$_fqin" "$CONTEXT")

    # Keep user-specified BUILD_ARGS near the beginning so errors are easy to spot
    stage_notice "Executing build command: '$RUNTIME build ${BUILD_ARGS[*]} ${_args[*]}'"
    "$RUNTIME" build "${BUILD_ARGS[@]}" "${_args[@]}"
}

confirm_arches() {
    local inspjson
    local filter=".manifests[].platform.architecture"
    local arch
    local maniarches

    dbg "in confirm_arches()"
    req_env_vars FQIN ARCHES RUNTIME
    if ! inspjson=$($RUNTIME manifest inspect "containers-storage:$FQIN:latest"); then
        die "Error reading manifest list metadata for 'containers-storage:$FQIN:latest'"
    fi

    # Convert into space-delimited string for grep error message (below)
    if ! maniarches=$(jq -r "$filter" <<<"$inspjson" | \
                      grep -v 'null' | \
                      tr -s '[:space:]' ' ' | \
                      sed -z '$ s/[\n ]$//'); then
        die "Error processing manifest list metadata:
$inspjson"
    fi
    dbg "Found manifest arches: $maniarches"

    for arch in $ARCHES; do
        grep -q "$arch" <<<"$maniarches" || \
            die "Failed to locate the $arch arch. in the $FQIN:latest manifest-list: $maniarches"
    done
}

run_modcmd() {
    dbg "Exporting variables '$_CMD_ENV'"
    # The indirect export is intentional here
    # shellcheck disable=SC2163
    export $_CMD_ENV
    stage_notice "Executing mod-command: " "$@"
    bash -c "$@"
    dbg "mod command successful"
}

# Outputs sorted list of FQIN w/ tags to stdout, silent otherwise
get_manifest_tags() {
    local result_json
    local fqin_names
    dbg "in get_manifest_tags()"

    # At the time of this comment, there is no reliable way to
    # lookup all tags based solely on inspecting a manifest.
    # However, since we know $FQIN (remember, value has no tag) we can
    # use it to search all related names in container storage.
    # Required, not an optimisation: --modcmd adds tags out-of-band.
    if ! result_json=$($RUNTIME images --json --filter=reference=$FQIN); then
        die "Error listing manifest-list images that reference '$FQIN'"
    fi

    dbg "Image listing json: $result_json"
    if [[ -n "$result_json" ]]; then  # N/B: value could be '[]'
        # Rely on the caller to handle an empty list, ignore items missing a name key.
        if ! fqin_names=$(jq -r '.[]? | .names[]?'<<<"$result_json"); then
            die "Error obtaining image names from '$FQIN' manifest-list search result:
$result_json"
        fi

        dbg "Sorting fqin_names"
        # Don't emit an empty newline when the list is empty
        [[ -z "$fqin_names" ]] || \
            sort <<<"$fqin_names"
    fi
    dbg "get_manifest_tags() returning successfully"
}

push_images() {
    local fqin_list
    local fqin
    dbg "in push_images()"

    # It's possible that --modcmd=* removed all images, make sure
    # this is known to the caller.
    if ! fqin_list=$(get_manifest_tags); then
        die "Retrieving set of manifest-list tags to push for '$FQIN'"
    fi
    if [[ -z "$fqin_list" ]]; then
        warn "No FQIN(s) to be pushed."
    fi

    if ((PUSH)); then
        dbg "Will try to push FQINs: '$fqin_list'"

        for fqin in $fqin_list; do
            # Note: --all means push manifest AND images it references
            msg "Pushing $fqin"
            $RUNTIME manifest push --all $fqin docker://$fqin
        done
    else
        # Even if --nopush was specified, be helpful to humans with a lookup of all the
        # relevant tags for $FQIN that would have been pushed and display them.
        warn "Option --nopush specified, not pushing: '$fqin_list'"
    fi
}

##### MAIN() #####

# Handle requested help first before anything else
if grep -q -- '--help' <<<"$@"; then
    echo "$E_USAGE" >> /dev/stdout  # allow grep'ing
    exit 0
fi

init
parse_args "$@"

parallel_build "$FQIN:latest"

# If a parallel build or the manifest-list assembly fails, buildah
# may still exit successfully.  Catch this condition by verifying
# all expected arches are present in the manifest list.
confirm_arches

if [[ -n "$MODCMD" ]]; then
    run_modcmd "$MODCMD"
fi

# Handles --nopush internally
push_images
