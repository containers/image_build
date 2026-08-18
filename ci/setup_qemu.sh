#!/bin/bash

# Register qemu-user-static binfmt_misc handlers so `buildah build --platform`
# can build non-native architectures.  Needs qemu-user-static and --privileged.

set -eo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/lib.sh"

BINFMT_MISC="/proc/sys/fs/binfmt_misc"

# 'register' only appears once mounted, so -d cannot decide whether to mount.
[[ -d "$BINFMT_MISC" ]] || \
    die "'$BINFMT_MISC' is missing; the host kernel lacks binfmt_misc support."

if [[ ! -f "$BINFMT_MISC/register" ]]; then
    dbg "Mounting binfmt_misc on $BINFMT_MISC"
    mount -t binfmt_misc none "$BINFMT_MISC" || \
        die "Unable to mount binfmt_misc on '$BINFMT_MISC'."
fi

[[ -w "$BINFMT_MISC/register" ]] || \
    die "'$BINFMT_MISC/register' is not writable; is this container --privileged?"

# binfmt_misc is kernel-global; a stale entry fails at exec, so clear first.
shopt -s nullglob
for entry in "$BINFMT_MISC"/qemu-*; do
    dbg "Removing pre-existing handler '$entry'"
    echo -1 > "$entry" || warn "Could not remove stale handler '$entry'"
done
shopt -u nullglob

# 'F' is mandatory: the interpreter must resolve inside buildah's per-arch chroot.
registered=0
for conf in /usr/lib/binfmt.d/qemu-*.conf; do
    [[ -r "$conf" ]] || continue
    # Fedora ships these with no trailing newline.
    while read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        [[ "$line" != \#* ]] || continue
        [[ "${line##*:}" == *F* ]] || \
            warn "Handler from '$conf' lacks the 'F' flag: $line"
        printf '%s\n' "$line" > "$BINFMT_MISC/register"
        registered=$((registered + 1))
    done < "$conf"
done

((registered > 0)) || \
    die "Registered no binfmt handlers; is the qemu-user-static package installed?"

msg "Registered $registered binfmt_misc handler(s):"
for entry in "$BINFMT_MISC"/qemu-*; do
    msg "    $(basename "$entry")"
done
