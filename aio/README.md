[comment]: <> (***ATTENTION*** ***WARNING*** ***ALERT*** ***CAUTION*** ***DANGER***)
[comment]: <> ()
[comment]: <> (ANY changes made below, once committed/merged must)
[comment]: <> (be manually copy/pasted -in markdown- into the description)
[comment]: <> (field on Quay at the following locations:)
[comment]: <> ()
[comment]: <> (https://quay.io/repository/containers/aio)
[comment]: <> ()
[comment]: <> (***ATTENTION*** ***WARNING*** ***ALERT*** ***CAUTION*** ***DANGER***)

![PODMAN logo](https://raw.githubusercontent.com/containers/common/main/logos/podman-logo-full-vert.png)
![buildah logo](https://cdn.rawgit.com/containers/buildah/main/logos/buildah-logo_large.png)
<img src="https://cdn.rawgit.com/containers/skopeo/main/docs/skopeo.svg" width="250">

# All In One: Podman, Buildah and Skopeo Image

## Build information

Please see the [containers/image_build repo. README.md for build
details](https://github.com/containers/image_build/blob/main/README.md).

## Sample Usage

Running as 'root' inside the container:

```
# Create a directory on the host to mount the container's
# /var/lib/container directory to so containers can be
# run within the container.
mkdir /var/lib/mycontainers

# Run a shell in the container, will full nested container run and build
# possibilities:
podman run -it --net=host --security-opt label=disable --privileged \
    --security-opt seccomp=unconfined --device /dev/fuse:rw \
    -v /var/lib/mycontainers:/var/lib/containers:Z \
    quay.io/containers/aio:latest
```

Running rootless inside the container:
```
mkdir $HOME/mycontainers

# Run a shell in the container, will full nested container run and build
# possibilities:
podman run -it --net=host --security-opt label=disable --privileged \
    --security-opt seccomp=unconfined --device /dev/fuse:rw \
    --user user --userns=keep-id:uid=1000,gid=1000 \
    -v $HOME/mycontainers:/home/user/.local/share/containers:Z \
    quay.io/containers/aio:latest
```

**Note:** If you encounter a `fuse: device not found` error when running the container image, it is likely that
the fuse kernel module has not been loaded on your host system.  Use the command `modprobe fuse` to load the
module and then run the container image.  To enable this automatically at boot time, you can add a configuration
file to `/etc/modules.load.d`.  See `man modules-load.d` for more details.
