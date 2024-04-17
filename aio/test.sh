#!/bin/bash

# This script is not intended for humans.  It's meant to be run
# by a CI system after a test-build of the
# quay.io/containers/aio:latest manifest list.

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

FQIN="quay.io/containers/aio:latest"
FQIN_FILE="$(basename $FQIN | tr ':' '-').tar"

# msg() doesn't support a prefix, nor show file/line-no.
# Abuse warn() to print testing messages and make them stand-out.
WARNING_MSG_PREFIX="***** TEST:"
msg() { warn "$1"; }

# These tests need to be run rootless, assume the environment is disposable.
# N/B: This condition does not return!
if [[ "$UID" -eq 0 ]]; then
    msg "Check that $FQIN exists in local storage"
    showrun podman manifest exists $FQIN

    msg "Verify manifest-list contains image for amd64 architecture"
    arches=$(showrun podman manifest inspect $FQIN | showrun jq -r -e '.manifests[].platform.architecture')
    showrun grep -F -x -q 'amd64' <<<"$arches"

    msg "Verify skopeo can inspect the local manifest list"
    showrun skopeo inspect --raw containers-storage:$FQIN | jq .

    msg "Setting up for rootless testing"
    TESTUSER="testuser$RANDOM"
    showrun useradd "$TESTUSER"
    export TUHOME="/home/$TESTUSER"
    showrun podman save -o "$TUHOME/$FQIN_FILE" "$FQIN"
    showrun chown $TESTUSER:$TESTUSER "$TUHOME/$FQIN_FILE"
    (umask 077; showrun mkdir -p "/root/.ssh")
    (umask 077; showrun ssh-keyscan localhost >> "/root/.ssh/known_hosts")
    showrun ssh-keygen -t rsa -P "" -f "/root/.ssh/id_rsa"
    (umask 077; showrun mkdir -p "$TUHOME/.ssh")
    showrun cp "/root/.ssh/id_rsa.pub" "$TUHOME/.ssh/authorized_keys"
    showrun chown -R $TESTUSER:$TESTUSER "$TUHOME/.ssh"
    showrun chmod 0600 "$TUHOME/.ssh/authorized_keys"
    # $SCRIPT_PATH/$SCRIPT_FILENAME defined by automation library
    # shellcheck disable=SC2154
    showrun exec ssh $TESTUSER@localhost $SCRIPT_PATH/$SCRIPT_FILENAME
fi

# SCRIPT_FILENAME defined by automation library
# shellcheck disable=SC2154
TMPD=$(mktemp -p '' -d ${SCRIPT_FILENAME}_XXXXX_tmp)
trap "podman unshare rm -rf '$TMPD'" EXIT

msg "Loading test image"
showrun podman load -i $HOME/$FQIN_FILE

# These tests come directly from the aio/README.md examples
mkdir $TMPD/cntr_storage
mkdir $TMPD/context
echo -e 'FROM registry.fedoraproject.org/fedora-minimal:latest\nENV TESTING=true' > $TMPD/context/Containerfile
for tool in buildah podman; do
    msg "Verify $tool can create a simple image as root inside $FQIN"
    showrun podman unshare rm -rf $TMPD/cntr_storage/* $TMPD/cntr_storage/.??*
    showrun podman run -i --rm --net=host --security-opt label=disable --privileged \
        --security-opt seccomp=unconfined --device /dev/fuse:rw \
        -v $TMPD/cntr_storage:/var/lib/containers:Z \
        -v $TMPD/context:/root/context:Z \
        $FQIN $tool build -t root_testimage /root/context

    msg "Verify $tool can create a simple image as rootless inside $FQIN"
    showrun podman unshare rm -rf $TMPD/cntr_storage/* $TMPD/cntr_storage/.??*
    showrun podman run -i --rm --net=host --security-opt label=disable --privileged \
        --security-opt seccomp=unconfined --device /dev/fuse:rw \
        --user user --userns=keep-id:uid=1000,gid=1000 \
        -v $TMPD/cntr_storage:/home/user/.local/share/containers:Z \
        -v $TMPD/context:/home/user/context:Z \
        $FQIN $tool build -t rootless_testimage /home/user/context
done
