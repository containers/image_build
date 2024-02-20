[comment]: <> (***ATTENTION*** ***WARNING*** ***ALERT*** ***CAUTION*** ***DANGER***)
[comment]: <> ()
[comment]: <> (ANY changes made to this file, once committed/merged must)
[comment]: <> (be manually copy/pasted -in markdown- into the description)
[comment]: <> (field on Quay at the following locations:)
[comment]: <> ()
[comment]: <> (https://quay.io/repository/containers/skopeo)
[comment]: <> (https://quay.io/repository/skopeo/stable)
[comment]: <> (https://quay.io/repository/skopeo/testing)
[comment]: <> (https://quay.io/repository/skopeo/upstream)
[comment]: <> ()
[comment]: <> (***ATTENTION*** ***WARNING*** ***ALERT*** ***CAUTION*** ***DANGER***)

<img src="https://cdn.rawgit.com/containers/skopeo/main/docs/skopeo.svg" width="250">

----

# skopeoimage

## Overview

This directory contains the Containerfiles necessary to create the skopeoimage container
images that are housed on quay.io under the skopeo account.  All repositories where
the images live are public and can be pulled without credentials.  These container images are secured and the
resulting containers can run safely with privileges within the container.

The container images are built using the latest Fedora and then Skopeo is installed into them.
The ENTRYPOINT of the container is set to execute the `skopeo` binary.

The container images are:

  * `quay.io/containers/skopeo:v<version>` and `quay.io/skopeo/stable:v<version>` -
    These images are built daily.  These images are intended contain an unchanging
    and stable version of skopeo.  For the most recent `<version>` tags (`vX`,
    `vX.Y`, and `vX.Y.Z`) the image contents will be updated daily to incorporate
    (especially) security updates.  For build details, please[see the configuration
    file](stable/Containerfile).
  * `quay.io/containers/skopeo:latest` and `quay.io/skopeo/stable:latest` -
    Built daily using the same Containerfile as above.  The skopeo version
    will remain the "latest" available in Fedora, however the other image
    contents may vary compared to the version-tagged images.
  * `quay.io/skopeo/testing:latest` - This image is built daily, using the
    latest version of Skopeo that was in the Fedora `updates-testing` repository.
    The image is Built with [the testing Containerfile](testing/Containerfile).
  * `quay.io/skopeo/upstream:latest` - This image is built daily using the latest
    code found in this GitHub repository.  Due to the image changing frequently,
    it's not guaranteed to be stable or even executable.  The image is built with
    [the upstream Containerfile](upstream/Containerfile).


## Sample Usage

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
