[comment]: <> (***ATTENTION*** ***WARNING*** ***ALERT*** ***CAUTION*** ***DANGER***)
[comment]: <> ()
[comment]: <> (ANY changes made below, once committed/merged must)
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

# Skopeo Image

## Build information

Please see the [containers/image_build repo. README.md for build
details](https://github.com/containers/image_build/blob/main/README.md).

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

## Sample Usage with private registry

1. Assuming one isn't already defined, setup a Podman secret with the `auth.json` contents.
   Alternatively, see the [`containers-auth.json` man
   page](https://github.com/containers/image/blob/main/docs/containers-auth.json.5.md)
   for the file format.  Regardless
   of how the file is created, using it as a Podman secret provides more protections than
   a simple bind-mount.

   ```
   $ auth_tmp=$(mktemp)
   $ echo '{}' > $auth_tmp  # JSON formating is required
   $ podman login --authfile=$auth_tmp example.com/registry
   $ podman secret create registry_name-auth $auth_tmp
   $ rm $auth_tmp
   ```

2. Pass the Podman secret into the Skopeo container along with the intended Skopeo command.
   For example, to retrieve metadata for `example.com/registry/image_name:tag` run:

   ```
   $ podman run --secret=registry_name-auth \
       docker://quay.io/skopeo/stable:latest \
       inspect --authfile=/run/secrets/registry_name_auth \
       docker://example.com/registry/image_name:tag
   ```

   ***NOTE:*** The `--authfile` argument must appear after the sub-command (i.e. `inspect` above)
