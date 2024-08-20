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
    These images are built daily.  They are intended to contain the latest stable
    versions of their respective container tool. For the most recent `<version>` tags (`vX`,
    `vX.Y`, and `vX.Y.Z`) the image contents will be updated daily to incorporate
    (especially) security updates.
  * `quay.io/containers/*:<version>-immutable` -  Uses the same source as the 'stable'
    images, built daily, but version-tags are never overwritten once pushed.  Tags
    will only be removed in case of an extreme security problem.  Otherwise, these
    images are intended for users that value an unchanging image tag and digest over
    daily security updates.  All three `<version>` values are available, `vX-immutable`,
    `vX.Y-immutable` and `vX.Y.Z-immutable`.
  * `quay.io/containers/*:latest` and `quay.io/*/stable:latest` -
    Built daily using the same `Containerfile` as above.  The tool versions
    will remain the "latest" available in Fedora.
  * `quay.io/containers/aio:latest` and `quay.io/containers/aio:<date stamp>` -
    "All In One" image containing Podman, Buildah, and Skopeo.  Built weekly
    using a similar `Containerfile` as the Podman and Buildah images.  It's a
    smaller, minimal image, intended to be used as a base-image for development
    containers or CI/automation.
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

## All In One Sample Usage

[Please see the subdirectory README.md](https://github.com/containers/image_build/blob/main/aio/README.md)

## Automation

**Warning**: It's easily possible this section is out of date or hasn't been updated.

The exact details of all build automation in every context is best obtained directly from
[`.cirrus.yml`](https://github.com/containers/image_build/blob/main/.cirrus.yml) and
any workflows defined under
[`.github/workflows`](https://github.com/containers/image_build/tree/main/.github/workflows).
What follows is simply a general overview.

### Tooling

The heart of all builds is the `containers/automation` repo [build-push.sh script](https://github.com/containers/automation/tree/main/build-push).
Put simply it does exactly what its name suggests; however, it also has some additional useful features:

* The script always produces manifest-list (i.e. multiple "images" all packed under a single name).  Unless overridden,
  the build will run in parallel for the `amd64`, `arm64`, `ppc64le`, and `s390x` architectures.  For this to work, the
  qemu-user-static package (or [container](https://github.com/multiarch/qemu-user-static)) is required to be installed
  and loaded into the kernel. For the automated builds, this is already available and setup in the VM image.
* Before and after building, `build-push.sh` is able to execute additional commands/scripts.  These are very
  useful for
  [preparing the context](https://github.com/containers/automation/tree/main/build-push#use-in-automation-with-additional-preparation)
  and/or
  [modifying image output and/or tags](https://github.com/containers/automation/tree/main/build-push#use-in-automation-with-modified-images).
  Otherwise the script only/ever builds a `latest` tag.  At the end, the script will search for and push _any_
  (could be zero) command-line named images regardless of tag.
* After building, the script will inspect the output of _existing_ named images to ensure it contains manifests for all
  specified architectures. This is needed to ensure the output represents the input parameters, in case the post-build
  modification script
  mangled something.
* If [a pair of magic envars are set](https://github.com/containers/automation/tree/main/build-push#use-in-build-automation)
  the script will pushes all images matching the name given on the command-line (i.e. the base image-name w/o a tag).
  **Great care is required w/in the CI/automation setup to ensure these envar values cannot leak.**

### Automation runtime

The [containers/automation_images](https://github.com/containers/automation_images) repo produces a VM image
dedicated for use by automation in this repo.  Specifically, the VM is setup
[using a simple script](https://github.com/containers/automation_images/blob/main/cache_images/build-push_packaging.sh)
to make sure all the required packages are installed, along with the common automation library and
[the build-push.sh script](https://github.com/containers/automation/tree/main/build-push).  Note that it always installs
the latest library and script, so any related problems can be quickly fixed with a CI VM image rebuild.

### Automation scripts

All the top-level build scripts used by automation in this repo, for all contexts, resides under the `ci` subdirectory.  These are tailored for each type of build since some (i.e. Podman, Buildah, and Skopeo) are pushed to multiple registry namespaces. However in all cases, these scripts ultimately end up simply calling
[the build-push.sh script](https://github.com/containers/automation/tree/main/build-push).

### Image Labels and Annotations

All build scripts (under the `ci` subdirectory) add labels (and annotation) prefixed with `built.by`.  These can be
extremely helpful for auditing purposes after-the-fact.  For example if a pushed image has something wrong with it,
the build log URL (`built.by.logs`) are available for some time. Or, if there's any question of what version of
build script was used, these details are available in `built.by.commit` (git commit) `built.by.exec` (script)
and `built.by.digest` (script hash).

**Note:** Both labels and annotations are set simply due to script logic convenience and to meet
future and
[past OCI recommendations](https://specs.opencontainers.org/image-spec/annotations/#back-compatibility-with-label-schema).
