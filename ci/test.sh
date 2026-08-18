#!/bin/bash

# DO NOT USE - Confirms 'containers_build_push.sh' behaves as expected against
# a throwaway git repository.  Needs podman, buildah, jq and qemu-user-static.

set -eo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/lib.sh"

req_env_vars CI

# Architectures to test with (golang standard names)
TESTARCHES="amd64 arm64"
# containers_build_push.sh is sensitive to this value
ARCHES=$(tr " " ","<<<"$TESTARCHES")
export ARCHES
# Contrived "version" for testing purposes
FAKE_VER_X=$RANDOM
FAKE_VER_Y=$RANDOM
FAKE_VER_Z=$RANDOM
FAKE_VERSION="$FAKE_VER_X.$FAKE_VER_Y.$FAKE_VER_Z"
# Must stay under /tmp: containers_build_push.sh guards on '^file:///tmp/'.
SRC_TMP=$(TMPDIR=/tmp mktemp -p '' -d tmp-build-push-test-XXXX)
# Do not change, containers_build_push.sh is sensitive to the 'testing' name
TEST_FQIN=example.com/testing/stable
# Stable build should result in manifest list tagged this
TEST_FQIN2=example.com/containers/testing

trap "rm -rf $SRC_TMP" EXIT

# containers_build_push.sh expects a git repository argument
msg "
##### Constructing local test repository #####"
cd $SRC_TMP
showrun git init -b main .
mkdir testing
cd testing
git config --local user.name "Testy McTestface"
git config --local user.email "test@example.com"
git config --local advice.detachedHead "false"
git config --local commit.gpgsign "false"
# Set a default flavor in the Containerfile to detect missing
echo "build-push-test version v$FAKE_VERSION" | tee "FAKE_VERSION"
cat <<EOF | tee "Containerfile"
FROM registry.fedoraproject.org/fedora-minimal:latest
ARG FLAVOR="No Flavor Specified"
ADD /FAKE_VERSION /
RUN echo "FLAVOUR=\$FLAVOR" > /FLAVOUR
EOF
# This file is looked up by the build script.
echo "Test Docs" > README.md
# The images will have the repo & commit ID set as labels
git add --all
git commit -m 'test repo initial commit'
TEST_REVISION=$(git rev-parse HEAD)

TEST_REPO_URL="file://$SRC_TMP"

# Print an error message and exit non-zero if the FQIN:TAG indicated
# by the first argument does not exist.
manifest_exists() {
    msg "Confirming existence of manifest list '$1'"
    if ! showrun podman manifest exists "$1"; then
        die "Failed to find expected manifest-list '$1'"
    fi
}

# Given the flavor-name as the first argument, verify built image
# expectations.  For 'stable' image, verify that containers_build_push.sh will properly
# version-tagged both FQINs.  For 'immutable' verify version tags only for TEST_FQIN2.
# For other flavors, verify expected labels on the `latest` tagged FQINs.
verify_built_images() {
    local _fqin _arch xy_ver x_ver img_ver img_src img_rev _fltr
    local test_tag expected_flavor _test_fqins img_docs
    expected_flavor="$1"
    msg "
##### Testing execution of '$expected_flavor' images for arches $TESTARCHES #####"
    podman --version
    req_env_vars TESTARCHES FAKE_VERSION TEST_FQIN TEST_FQIN2

    declare -a _test_fqins
    _test_fqins=("${TEST_FQIN%stable}$expected_flavor")
    if [[ "$expected_flavor" == "stable" ]]; then
        _test_fqins+=("$TEST_FQIN2")
        test_tag="v$FAKE_VERSION"
        xy_ver="v$FAKE_VER_X.$FAKE_VER_Y"
        x_ver="v$FAKE_VER_X"
    else
        test_tag="latest"
        xy_ver="latest"
        x_ver="latest"
    fi

    for _fqin in "${_test_fqins[@]}"; do
        manifest_exists $_fqin:$test_tag

        if [[ "$expected_flavor" == "stable" ]]; then
            manifest_exists $_fqin:$xy_ver
            manifest_exists $_fqin:$x_ver
            manifest_exists $_fqin:${test_tag}-immutable
            manifest_exists $_fqin:${xy_ver}-immutable
            manifest_exists $_fqin:${x_ver}-immutable

            msg "Confirming there is no 'latest-immutable' tag"
            if showrun podman manifest exists $_fqin:latest-immutable; then
                die "The latest tag must never ever have an immutable suffix"
            fi
        fi

        for _arch in $TESTARCHES; do
            msg "Testing container can execute '/bin/true'"
            showrun podman run -i --arch=$_arch --rm "$_fqin:$test_tag" /bin/true

            msg "Testing container FLAVOR build-arg passed correctly"
            showrun podman run -i --arch=$_arch --rm "$_fqin:$test_tag" \
                cat /FLAVOUR | tee /dev/stderr | grep -Fxq "FLAVOUR=$expected_flavor"
        done

        if [[ "$expected_flavor" == "stable" ]]; then
            msg "Testing image $_fqin:$test_tag version label"
            _fltr='.[].Config.Labels."org.opencontainers.image.version"'
            img_ver=$(podman inspect $_fqin:$test_tag | jq -r -e "$_fltr")
            showrun test "$img_ver" == "v$FAKE_VERSION"
        fi

        msg "Testing image $_fqin:$test_tag source label"
        _fltr='.[].Config.Labels."org.opencontainers.image.source"'
        img_src=$(podman inspect $_fqin:$test_tag | jq -r -e "$_fltr")
        msg "    img_src=$img_src"
        showrun grep -F -q "$TEST_REPO_URL" <<<"$img_src"
        showrun grep -F -q "$TEST_REVISION" <<<"$img_src"

        msg "Testing image $_fqin:$test_tag url label"
        _fltr='.[].Config.Labels."org.opencontainers.image.url"'
        img_url=$(podman inspect $_fqin:$test_tag | jq -r -e "$_fltr")
        msg "    img_url=$img_url"
        showrun grep -F -q "example.com" <<<"$img_url"


        msg "Testing image $_fqin:$test_tag revision label"
        _fltr='.[].Config.Labels."org.opencontainers.image.revision"'
        img_rev=$(podman inspect $_fqin:$test_tag | jq -r -e "$_fltr")
        msg "    img_rev=$img_rev"
        showrun test "$img_rev" == "$TEST_REVISION"

        msg "Testing image $_fqin:$test_tag built.by.commit label"
        _fltr='.[].Config.Labels."built.by.commit"'
        img_bbc=$(podman inspect $_fqin:$test_tag | jq -r -e "$_fltr")
        msg "    img_bbc=$img_bbc"
        showrun test "$img_bbc" == "$TEST_REVISION"

        msg "Testing image $_fqin:$test_tag docs label"
        _fltr='.[].Config.Labels."org.opencontainers.image.documentation"'
        img_docs=$(podman inspect $_fqin:$test_tag | jq -r -e "$_fltr")
        msg "    img_docs=$img_docs"
        showrun grep -F -q "README.md" <<<"$img_docs"
    done
}

remove_built_images() {
    local fqin tag
    local -a tags

    buildah --version

    tags=( latest )
    for tag in v$FAKE_VERSION v$FAKE_VER_X.$FAKE_VER_Y v$FAKE_VER_X; do
        tags+=( "$tag" "${tag}-immutable" )
    done

    for fqin in $TEST_FQIN $TEST_FQIN2; do
        for tag in "${tags[@]}"; do
            # Not all tests produce every possible tag
            podman manifest rm $fqin:$tag &> /dev/null || true
        done
    done
}

_cbp="$SCRIPT_PATH/containers_build_push.sh"

cd $SRC_TMP

for flavor_arg in stable foobarbaz; do
    msg "
##### Testing build-push $flavor_arg flavor run of '$TEST_FQIN' & '$TEST_FQIN2' #####"
    remove_built_images
    export DRYRUN=1  # Force containers_build_push.sh not to push anything
    req_env_vars ARCHES DRYRUN flavor_arg
    # containers_build_push.sh is sensitive to 'testing' value.
    env A_DEBUG=1 $_cbp $TEST_REPO_URL testing $flavor_arg
    verify_built_images $flavor_arg
done
