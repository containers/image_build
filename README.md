# Image Build

Monorepo menagerie of container images and associated build automation

## Podman / Buildah / Skopeo

## Overview

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
    and stable version of their respective container image. For the most recent `<version>`
    tags (`vX`, `vX.Y`, and `vX.Y.Z`) the image contents will be updated daily to incorporate
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

[Please see the subdirectory README.md](https://github.com/containers/image_build/blob/main/podman/README.md)

## Buildah Sample Usage

[Please see the subdirectory README.md](https://github.com/containers/image_build/blob/main/buildah/README.md)

## Skopeo Sample Usage

[Please see the subdirectory README.md](https://github.com/containers/image_build/blob/main/skopeo/README.md)
