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

![PODMAN logo](https://raw.githubusercontent.com/containers/common/main/logos/podman-logo-full-vert.png)

# Podman Image

## Build information

Please see the [top-level image_build repo. README.md for build
details](https://github.com/containers/image_build/blob/main/README.md).

## Sample Usage

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

### Blog Post with Details

Dan Walsh wrote a blog post on the [Enable Sysadmin](https://www.redhat.com/sysadmin/) site titled [How to use Podman inside of a container](https://www.redhat.com/sysadmin/podman-inside-container).  In it, he details how to use these images as a rootful and as a rootless user.  Please refer to this blog for more detailed information.
