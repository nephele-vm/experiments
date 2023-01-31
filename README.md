# Nephele Experiments

## Source code
The repositories with the Nephele changes for the Xen virtualization
environment and the VM code that is not Unikraft-specific are in
[`nephele-vm`](https://github.com/orgs/nephele-vm/repositories), while all the
changes for Unikraft are in
[`nephele-unikraft`](https://github.com/orgs/nephele-unikraft/repositories).

## Root filesystem
All the experiments were run on Alpine 3.13. The root filesystem in the
`alpine-v3.13-rootfs.tar.gz` archive from
[here](https://github.com/nephele-vm/alpine) contains the packages required for
buiding all the Nephele components.  Before deploying the root filesystem to a
machine do not forget to add your public key in `/root/.ssh/authorized_keys`.

## Build
The `build/build.sh` script downloads and builds all the components for
Nephele. The `build/` directory also contains the config files for the Linux
kernel and Xen hypervisor.  Only OVS and Xen tools need to be build in an
Alpine filesystem, but for simplicity the `build/build.sh` script also builds
the hypervisor, the Dom0 kernel and modules, and the unikernel-based VMs.

Simply running `build/build.sh` will put everything under the `dev/`
subdirectory.
