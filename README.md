# Image Build

Monorepo menagerie of container images and associated build automation

## Podman / Buildah / Skopeo

## Overview

[comment]: <> (***ATTENTION*** ***WARNING*** ***ALERT*** ***CAUTION*** ***DANGER***)
[comment]: <> ()
[comment]: <> (ANY changes made below, once committed/merged must)
[comment]: <> (be manually copy/pasted -in markdown- into the description)
[comment]: <> (field on Quay at the following locations, where * represents podman|buildah|skopeo:)
[comment]: <> ()
[comment]: <> (https://quay.io/repository/containers/*)
[comment]: <> (https://quay.io/repository/*/stable)
[comment]: <> (https://quay.io/repository/*/testing)
[comment]: <> (https://quay.io/repository/*/upstream)
[comment]: <> ()
[comment]: <> (***ATTENTION*** ***WARNING*** ***ALERT*** ***CAUTION*** ***DANGER***)

The latest version of these docs may be obtained from [the upstream
repo.](https://github.com/containers/image_build/blob/main/README.md)

These directories contain the Containerfiles necessary to create the images housed on
quay.io under their namespace in addition to the 'containers' namespace.  These
images are public and can be pulled without credentials.  These container images are secured and the
resulting containers can run safely with or without privileges.

The container images are built using the latest Fedora and then the respective tools are installed.
The `$PATH` in the container images is set to the default provided by Fedora.  Neither the
`$ENTRYPOINT` nor the `$WORKDIR` variables are set within these container images, and as
such they default to `/`.

The container images are tagged as follows, where `*` represents either `podman`, `buildah`
or `skopeo`:

  * `quay.io/containers/*:<version>` and `quay.io/*/stable:<version>` -
    These images are built daily.  They are intended to contain an unchanging
    and stable version of their container image. For the most recent `<version>` tags (`vX`,
    `vX.Y`, and `vX.Y.Z`) the image contents will be updated daily to incorporate
    (especially) security updates.
  * `quay.io/containers/*:latest` and `quay.io/*/stable:latest` -
    Built daily using the same `Containerfile` as above.  The tool versions
    will remain the "latest" available in Fedora.
  * `quay.io/*/testing:latest` - This image is built daily, using the
    latest tooling version available in the Fedora `updates-testing` repository.
  * `quay.io/*/upstream:latest` - This image is built daily using the latest
    code found on the main branch of the respective upstream repository. Due to the
    image changing frequently, it's not guaranteed to be stable or even executable.
    Note: The actual tool compilation [occurs continuously in
    COPR](https://copr.fedorainfracloud.org/coprs/rhcontainerbot/podman-next/).

## Podman Sample Usage

![PODMAN logo](https://raw.githubusercontent.com/containers/common/main/logos/podman-logo-full-vert.png)

```
podman pull docker://quay.io/podman/stable:latest

podman run --privileged stable podman version

# Create a directory on the host to mount the container's
# /var/lib/container directory to so containers can be
# run within the container.
mkdir /var/lib/mycontainer

# Run the image detached using the host's network in a container name
# podmanctr, turn off label and seccomp confinement in the container
# and then do a little shell hackery to keep the container up and running.
podman run --detach --name=podmanctr --net=host --security-opt label=disable --security-opt seccomp=unconfined --device /dev/fuse:rw -v /var/lib/mycontainer:/var/lib/containers:Z --privileged  stable sh -c 'while true ;do sleep 100000 ; done'

podman exec -it  podmanctr /bin/sh

# Now inside of the container

podman pull alpine

podman images

exit
```

**Note:** If you encounter a `fuse: device not found` error when running the container image, it is likely that
the fuse kernel module has not been loaded on your host system.  Use the command `modprobe fuse` to load the
module and then run the container image.  To enable this automatically at boot time, you can add a configuration
file to `/etc/modules.load.d`.  See `man modules-load.d` for more details.

More details:

Dan Walsh wrote a blog post on the [Enable Sysadmin](https://www.redhat.com/sysadmin/) site titled [How to use Podman inside of a container](https://www.redhat.com/sysadmin/podman-inside-container).  In it, he details how to use these images as a rootful and as a rootless user.  Please refer to this blog for more detailed information.


## Buildah Sample Usage

![buildah logo](https://cdn.rawgit.com/containers/buildah/main/logos/buildah-logo_large.png)

Although not required, it is suggested that [Podman](https://github.com/containers/podman) be used with
these container images.

```
podman pull docker://quay.io/buildah/stable:latest

podman run stable buildah version

# Create a directory on the host to mount the container's
# /var/lib/container directory to so containers can be
# run within the container.
mkdir /var/lib/mycontainer

# Run the image detached using the host's network in a container name
# buildahctr, turn off label and seccomp confinement in the container
# and then do a little shell hackery to keep the container up and running.
podman run --detach --name=buildahctr --net=host --security-opt label=disable --security-opt seccomp=unconfined --device /dev/fuse:rw -v /var/lib/mycontainer:/var/lib/containers:Z  stable sh -c 'while true ;do sleep 100000 ; done'

podman exec -it  buildahctr /bin/sh

# Now inside of the container

buildah from alpine

buildah images

exit
```

**Note:** If you encounter a `fuse: device not found` error when running the container image, it is likely that
the fuse kernel module has not been loaded on your host system.  Use the command `modprobe fuse` to load the
module and then run the container image.  To enable this automatically at boot time, you can add a configuration
file to `/etc/modules.load.d`.  See `man modules-load.d` for more details.


## Skopeo Sample Usage

<img src="https://cdn.rawgit.com/containers/skopeo/main/docs/skopeo.svg" width="250">

Although not required, it is suggested that [Podman](https://github.com/containers/podman) be used with these container images.

```
# Get Help on Skopeo
podman run docker://quay.io/skopeo/stable:latest --help

# Get help on the Skopeo Copy command
podman run docker://quay.io/skopeo/stable:latest copy --help

# Copy the Skopeo container image from quay.io to
# a private registry
podman run docker://quay.io/skopeo/stable:latest copy docker://quay.io/skopeo/stable docker://registry.internal.company.com/skopeo

# Inspect the fedora:latest image
podman run docker://quay.io/skopeo/stable:latest inspect --config docker://registry.fedoraproject.org/fedora:latest  | jq
```
