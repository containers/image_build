#!/bin/bash

# This script is intended to be used by humans or automation, from a git repo.
# clone, in an environment where the standard automation library, and
# qemu-user-static are all available.  It is assumed that no other containers
# are running and container storage is completely empty of all images or
# manifest-lists.
#
# It must be provided two arguments: <'podman'|'buildah'|'skopeo'> and the
# base-image (golang-based) architecture name (i.e. 'amd64').  Together, these
# select the proper base image build context to process.
#
# When executed, the script will pull build information from the Containerfile.
# Then perform a temporary arch-specific build to query the current package
# repositories to produce a precise N-V-R-A package list.  It will also verify
# the `BASE_TAG` build-arg Containerfile value is up to date with Fedora releases.
#
# The script should be executed after:
#
#   - Any time there is a new (officialy) supported Fedora release.
#   - Following changes to either of the `INST_PKGS` or `EXCL_PKGS`
#     `Containerfile` values.
#   - Periodically, to update the package lists for tracking in version control.

set -eo pipefail

if [[ -r "/etc/automation_environment" ]]; then
  source /etc/automation_environment  # defines AUTOMATION_LIB_PATH
  #shellcheck disable=SC1090,SC2154
  source "$AUTOMATION_LIB_PATH/common_lib.sh"
  dbg "Using automation common library version $(<$AUTOMATION_LIB_PATH/../AUTOMATION_VERSION)"
else
  echo "Expecting to find common automation library installed."
  exit 1
fi

[[ -n "$1" ]] || \
  die "Must pass 'podman'|'buildah'|'skopeo' as first argument"

[[ -n "$2" ]] || \
  die "Must pass golang-based architecture name as second argument"

CONTEXT="$1"
ARCH="$2"

declare -a INST_PKGS EXCL_PKGS

# Name of temporary directory AND temporary container
# SCRIPT_FILENAME comes from automation library
# shellcheck disable=SC2154
TMPD=$(mktemp -d -p '' "${SCRIPT_FILENAME}_${CONTEXT}_${ARCH}_XXXX.tmp")

declare -a DNFARGS
DNFARGS=( --assumeyes --setopt=keepcache=True --nodocs --noplugins --noplugins )

cleanup(){
  ret=$?
  set +e

  if [[ -n "$cntr_name" ]]; then
    (
      podman kill -s 9 "$cntr_name"
      podman rm --ignore --force "$cntr_name"
    ) >> /dev/null
  fi

  # A_DEBUG is defined by automation library
  # shellcheck disable=SC2154
  if ((A_DEBUG)); then
    dbg "Preserving '$TMPD' for inspection/debugging."
  else
    rm -rf "$TMPD"
  fi
  dbg "Exit: $ret"
}

# Given the name of a build-arg, print its value as defined in Containerfile
get_bld_arg_val() {
  local value
  local query

  [[ -n "$1" ]] || \
    die "${FUNCNAME[0]}() must be called with the name of a build-arg."

  # Filter-out in-line comments and quotes + show value to stderr
  query="^ARG $1="
  # For some unknown reason, shellcheck sees $query as an array
  # shellcheck disable=SC1087
  if ! value=$(grep -E -m 1 "$query" ./Containerfile \
               | sed -r -e "s/$query(.+)/\1/" \
               | tr -d "\"'"); then
    die "Can't find/parse build-arg definition for '$1' in ./Containerfile"
  fi

  msg "    Using $1: $value"  # to stderr

  echo -n "$value"
}

##### MAIN #####

trap cleanup EXIT

msg "Operating in '$CONTEXT' subdirectory."
# SCRIPT_PATH is defined by the automation library
# shellcheck disable=SC2154
cd "$SCRIPT_PATH/$CONTEXT"

if [[ ! -r Containerfile ]]; then
    die "Cannot find a 'Containerfile' in $PWD"
fi

# Avoid needing to define these values in more than one place.
msg "Loading build-args from ./Containerfile:"
for arg_name in BASE_IMAGE BASE_TAG; do
  declare $arg_name="$(get_bld_arg_val $arg_name | tr -d '[:blank:]')"
  [[ -n "${!arg_name}" ]] || \
    die "Failed to retrieve value for $arg_name from ./Containerfile build-arg"
done

for arg_name in INST_PKGS EXCL_PKGS; do
  declare -a $arg_name
  readarray -t $arg_name <<<"$(get_bld_arg_val $arg_name | tr -s ' ' '\n')"
  if [[ -z "${arg_name[*]}" ]] || [[ "${#arg_name[@]}" -eq 0 ]]; then
    die "Failed to retrieve $arg_name (space-separated values) from ./Containerfile build-arg"
  fi
done

# Both BASE_IMAGE and BASE_TAG are indirectly defined (above)
# shellcheck disable=SC2154
msg "Confirming $BASE_IMAGE:$BASE_TAG is the latest supported Fedora release."
# The fedora container image workflow tags rawhide builds with it's target
# release number.  That complicates automatic management of the `BASE_TAG`
# build-arg.  Fortunately, it can be looked up from the `latest` (supported)
# tagged fedora container image.
fqin="${BASE_IMAGE}:latest"
# No need to reference $ARCH, assume all are released at the same time.
podman run --rm "$fqin" cat /etc/os-release > "$TMPD/os-release"
# No need to shellcheck this
# shellcheck disable=SC1091,SC2154
_base_tag=$(source "$TMPD/os-release" && echo -n "$VERSION_ID")
expr "$_base_tag" : '[0-9]' >> /dev/null || \
  die "VERSION_ID from os-release file ($_base_tag) in latest fedora image isn't an integer"

if [[ $_base_tag -ne $BASE_TAG ]]; then
  die "./Containerfile BASE_TAG '$BASE_TAG' needs updating to '$_base_tag'."
fi

fqin="${BASE_IMAGE}:${BASE_TAG}"
cntr_name=$(basename "$TMPD")
cache_vol="${SCRIPT_FILENAME%.sh}-dnfcache-${BASE_TAG}-${ARCH}"

# Assist developers and multiple back-to-back runs of this script
podman volume exists "$cache_vol" || podman volume create "$cache_vol"

msg "Starting working container for package inspection."
showrun podman run -d --rm --os linux --arch "$ARCH" --name "${cntr_name}" \
    -v "$cache_vol:/var/cache/dnf:U,Z" "$fqin" sleep 2h

msg "Updating the base container image."
showrun podman exec "${cntr_name}" dnf "${DNFARGS[@]}" update

msg "Obtaining base-image package set as a baseline."
showrun podman exec "${cntr_name}" rpm -qa \
  | sort > "$TMPD/initial_rpms.txt"
declare -a initial_rpms
readarray -t initial_rpms < "$TMPD/initial_rpms.txt"

declare -a _dnfinstall
# Using readarray/mapfile would be inconvenient in this case
# shellcheck disable=SC2207
_dnfinstall=( dnf install "${DNFARGS[@]}" "${INST_PKGS[@]}"
              $(for xclded in "${EXCL_PKGS[@]}"; do echo "-x $xclded"; done) )

msg "Installing packages and dependencies."
showrun podman exec "${cntr_name}" "${_dnfinstall[@]}"

# This is the cleanest way of obtaining ${INST_PKGS[@]} + dependencies
# without relying on scraping the potentially unreliable dnf install output.
msg "Obtaining working container total package set."
showrun podman exec "${cntr_name}" rpm -qa \
  | sort | while read -r name junk; do
  # Exclude any pre-existing packages, they are not dependencies of ${INST_PKGS[@]}
  if ! echo "${initial_rpms[@]}" | grep -F -q -w "$name"; then
    echo "$name"
  fi
done > "$TMPD/target_rpms.txt"
total_packages=$(wc -l < "$TMPD/target_rpms.txt")

# Building the Containerfile requires knowledge of the target architecture
# in order to select the correct package list file.  Use the actual value
# instead of the golang-centric $ARCH value because the $TARGETARCH build-arg
# isn't always available to the Containerfile.
msg "Obtaining the canonical architecture name"
target_arch=$(podman exec "${cntr_name}" uname -m)

msg "Populating $total_packages packages and dependencies into ./${CONTEXT}/${target_arch}_packages.txt"
(
  echo "# DO NOT MAKE MANUAL MODIFICATIONS TO THIS FILE"
  echo "#"
  echo "# It should be maintained by re-running '$SCRIPT_FILENAME $CONTEXT $ARCH'."
  echo "# The list below was produced on $(date -u -Iseconds) using the"
  echo "# script from git commit $(git rev-parse --short HEAD) along with"
  echo "# the ($target_arch) container image $fqin"
  echo "# having a manifest-list digest of $(podman image inspect --format='{{.Digest}}' $fqin)."
  echo "# Installing : ${INST_PKGS[*]}"
  echo "# But excluding: ${EXCL_PKGS[*]}"
  echo "#"
  echo "# DO NOT MAKE MANUAL MODIFICATIONS TO THIS FILE"
  # Extracting the name, version, and release details from the package name produces
  # ambiguous results.  But these details are necessary for tools like Renovate to
  # perform version comparisons.
  for pkg_name in $(< "$TMPD/target_rpms.txt"); do
    # ref: http://ftp.rpm.org/max-rpm/ch-queryformat-tags.html
    nvra_output=$(podman exec "${cntr_name}" rpm -q --qf '%{N} %{V} %{R} %{ARCH}\n' "$pkg_name")
    read name version release arch junk<<<"$nvra_output"
    echo ""
    echo "# distro=Fedora distrel=$_base_tag name=$name version=$version release=$release arch=$arch"
    echo "$pkg_name" | tee -a /dev/stderr
  done
) > "./${target_arch}-packages.txt"
