

# DO NOT USE - This script is intended to be called by the Cirrus-CI
# `test_build-push` task.  It is not intended to be used otherwise
# and may cause harm.  It's purpose is to confirm the
# 'containers_build_push.sh' script behaves in an expected way, given
# a special testing git repository (setup here) as input.

set -eo pipefail

source /etc/automation_environment
source $AUTOMATION_LIB_PATH/common_lib.sh

req_env_vars CIRRUS_CI CIRRUS_CHANGE_IN_REPO

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
# Contrived source repository for testing
SRC_TMP=$(mktemp -p '' -d tmp-build-push-test-XXXX)
# Do not change, containers_build_push.sh is sensitive to the 'testing' name
TEST_FQIN=example.com/testing/stable
# Stable build should result in manifest list tagged this
TEST_FQIN2=example.com/containers/testing
# Don't allow containers_build_push.sh or tag_version.sh to auto-update at runtime
export BUILDPUSHAUTOUPDATED=1

trap "rm -rf $SRC_TMP" EXIT

# containers_build_push.sh expects a git repository argument
msg "
##### Constructing local test repository #####"
cd $SRC_TMP
showrun git init -b main testing
cd testing
git config --local user.name "Testy McTestface"
git config --local user.email "test@example.com"
git config --local advice.detachedHead "false"
git config --local commit.gpgsign "false"
# The following paths match the style of sub-dir in the actual
# skopeo/buildah/podman repositories.  Only the 'stable' flavor
# is tested here, since it involves the most complex workflow.
# Set a default flavor in the Containerfile to detect missing
# flavor arg / envar processing.
mkdir -vp "contrib/testimage/stable"
cd "contrib/testimage/stable"
echo "build-push-test version v$FAKE_VERSION" | tee "FAKE_VERSION"
cat <<EOF | tee "Containerfile"
FROM registry.fedoraproject.org/fedora:latest
ARG FLAVOR="No Flavor Specified"
ADD /FAKE_VERSION /
RUN echo "FLAVOUR=\$FLAVOR" > /FLAVOUR
EOF
# As an additional test, build and check images when pasing
# the 'stable' flavor name as a command-line arg instead
# of using the subdirectory dirname (old method).
cd $SRC_TMP/testing/contrib/testimage
# This file is looked up by the build script.
echo "Test Docs" > README.md
cp stable/* ./
cd $SRC_TMP/testing
# The images will have the repo & commit ID set as labels
git add --all
git commit -m 'test repo initial commit'
TEST_REVISION=$(git rev-parse HEAD)

TEST_REPO_URL="file://$SRC_TMP/testing"

# Given the flavor-name as the first argument, verify built image
# expectations.  For 'stable' image, verify that containers_build_push.sh will properly
# version-tagged both FQINs.  For other flavors, verify expected labels
# on the `latest` tagged FQINs.
verify_built_images() {
    local _fqin _arch xy_ver x_ver img_ver img_src img_rev _fltr
    local _test_tag expected_flavor _test_fqins img_docs
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
        for _arch in $TESTARCHES; do
            msg "Testing container can execute '/bin/true'"
            showrun podman run -i --arch=$_arch --rm "$_fqin:$test_tag" /bin/true

            msg "Testing container FLAVOR build-arg passed correctly"
            showrun podman run -i --arch=$_arch --rm "$_fqin:$test_tag" \
                cat /FLAVOUR | tee /dev/stderr | grep -Fxq "FLAVOUR=$expected_flavor"

            if [[ "$expected_flavor" == "stable" ]]; then
                msg "Testing tag '$xy_ver'"
                if ! showrun podman manifest exists $_fqin:$xy_ver; then
                    die "Failed to find manifest-list tagged '$xy_ver'"
                fi

                msg "Testing tag '$x_ver'"
                if ! showrun podman manifest exists $_fqin:$x_ver; then
                    die "Failed to find manifest-list tagged '$x_ver'"
                fi
            fi
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

        msg "Testing image $_fqin:$test_tag revision label"
        _fltr='.[].Config.Labels."org.opencontainers.image.revision"'
        img_rev=$(podman inspect $_fqin:$test_tag | jq -r -e "$_fltr")
        msg "    img_rev=$img_rev"
        showrun test "$img_rev" == "$TEST_REVISION"

        msg "Testing image $_fqin:$test_tag built.by.commit label"
        _fltr='.[].Config.Labels."built.by.commit"'
        img_bbc=$(podman inspect $_fqin:$test_tag | jq -r -e "$_fltr")
        msg "    img_bbc=$img_bbc"
        # Checked at beginning of script
        # shellcheck disable=SC2154
        showrun test "$img_bbc" == "$CIRRUS_CHANGE_IN_REPO"

        msg "Testing image $_fqin:$test_tag docs label"
        _fltr='.[].Config.Labels."org.opencontainers.image.documentation"'
        img_docs=$(podman inspect $_fqin:$test_tag | jq -r -e "$_fltr")
        msg "    img_docs=$img_docs"
        showrun grep -F -q "README.md" <<<"$img_docs"
    done
}

remove_built_images() {
    buildah --version
    for _fqin in $TEST_FQIN $TEST_FQIN2; do
        for tag in latest v$FAKE_VERSION v$FAKE_VER_X.$FAKE_VER_Y v$FAKE_VER_X; do
            # Don't care if this fails
            podman manifest rm $_fqin:$tag || true
        done
    done
}

msg "
##### Testing build-push subdir-flavor run of '$TEST_FQIN' & '$TEST_FQIN2' #####"
cd $SRC_TMP/testing
export DRYRUN=1  # Force containers_build_push.sh not to push anything
req_env_vars ARCHES DRYRUN
# containers_build_push.sh is sensitive to 'testing' value.
# Also confirms containers_build_push.sh is on $PATH
env A_DEBUG=1 containers_build_push.sh $TEST_REPO_URL contrib/testimage/stable
verify_built_images stable

msg "
##### Testing build-push flavour-arg run for '$TEST_FQIN' & '$TEST_FQIN2' #####"
remove_built_images
env A_DEBUG=1 containers_build_push.sh $TEST_REPO_URL contrib/testimage foobarbaz
verify_built_images foobarbaz

msg "
##### Testing build-push local repo run for '$TEST_FQIN'"
env A_DEBUG=1 containers_build_push.sh .$TEST_REPO_URL contrib/testimage foobarbaz
verify_built_images foobarbaz
