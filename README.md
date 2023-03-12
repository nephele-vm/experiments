# Nephele Experiments

Nephele is a solution for cloning unikernel-based VMs on Xen and that provides
8x faster instantiation times and can run 3x more active unikernel VMs on the
same hardware compared to booting separate unikernels. Its design,
implementation and evaluation is presented in the paper "Nephele: Extending
Virtualization Environments for Cloning Unikernel-based VMs" which was accepted
at EuroSys'23.

The current repository contains information and files needed for deploying and
running Nephele on commodity hardware.

## Prerequisites
You will need a bare-metal commodity x86_64 server with minimum 4 CPUs and 16
GB RAM to run Xen with the changes added by Nephele.  We provide an Alpine root
filesystem for Dom0, but Nephele can be used with any Linux distribution.

## Source code
The repositories with the Nephele changes for the Xen virtualization
environment and the VM code that is not Unikraft-specific are in
[`nephele-vm`](https://github.com/orgs/nephele-vm/repositories), while all the
changes for Unikraft are in
[`nephele-unikraft`](https://github.com/orgs/nephele-unikraft/repositories).

## Root filesystem
All the experiments were run on Alpine 3.13. The root filesystem in the
`alpine-v3.13-rootfs.tar.gz` archive from
[here](https://github.com/nephele-vm/alpine) contains prebuilt binaries for Xen
hypervisor and Linux kernel with Nephele support and the packages required for
buiding all the other Nephele components.  Before deploying the root filesystem
to a machine do not forget to add your public key in
`/root/.ssh/authorized_keys`.

## Building the Nephele components
The `build/build.sh` script downloads and builds all the components for
Nephele. The `build/` directory also contains the config files for the Linux
kernel and Xen hypervisor. Only OVS and Xen tools need to be build in an Alpine
filesystem, but for simplicity the `build/build.sh` script also builds the
hypervisor, the Dom0 kernel and modules, and the unikernel-based VMs.  Simply
running `build/build.sh all` will put everything under the `dev/` subdirectory.
The command `DO_BUILD=0 build/build.sh` checks out the code without building
anything.

## Steps for running the Nephele virtualization environment
We describe the steps that need to be followed in order to run Nephele on a
server with PXE boot support. This is just one of the many approaches that can
be taken to deploy Nephele.
1. **Boot the host.** The decompressed Alpine 3.13 root filesystem can be
used as is to boot a x86_64 server via PXE as it already contains prebuilt
binaries for Xen hypervisor and Linux kernel with Nephele support.

2. **Build the Linux modules.** Running `build/build.sh linux` will build
and install the Linux kernel modules needed for Nephele (e.g. netback driver).

3. **Build the userspace tools.**  Running `build/build.sh userspace` will
build and install the Xen tools (e.g. `xl`, `oxenstored`, `xencloned`).

4. **Reboot.** At this moment the host can be rebooted as it contains all the
components needed to launch guests with Nephele.

5. **Run `xencloned.** The `xencloned` daemon coordinates the userspace
operations and I/O cloning of Nephele guests.  In a separate shell, run the
`xencloned --cache -x` for full optimization. For automated startup, update the
`/etc/rc.local` or create a dedicated service to launch it.

6. **Build the guests.** Running `build/build.sh guests` will build all the VM
images for the applications evaluated in the Nephele paper:
     * [Cloning applications](https://github.com/nephele-vm/cloning-apps) used in the microbenchmarks and that can run on Mini-OS and Unikraft
     * Unikraft applications:
       * [NGINX](https://github.com/nephele-unikraft/app-nginx)
       * [Redis](https://github.com/nephele-unikraft/app-redis)
       * [Fuzzing application](https://github.com/nephele-unikraft/app-fuzz)
       * [Python interpreter](https://github.com/nephele-unikraft/app-python) used in the lambda use-case

7. **Run the guests.** Additionally to regular [`xl` configuration
parameters](https://xenbits.xen.org/docs/unstable/man/xl.cfg.5.html), in order
to enable cloning for a guest the configuration file must contain the
`max_clones` parameter which will limit the number of clones per family. An
example of `xl.conf` for cloning application that measure the `fork()` duration
for different memory sizes (increasing the memory size will increase the
duration):
 
```
name = "unikraft-cloning-app"
kernel = "cloning-apps_xen-x86_64"
memory = "32"
vcpus = "1"
cpus="2-3"
on_crash = "preserve"

vif=[ 'mac=aa:bb:cc:06:06:02,ip=10.8.0.2 255.255.255.0 10.8.0.1,bridge=bond0' ]

max_clones="2"
cmdline=" -- -a measure-fork -m 16MB"
```

## `xencloned`
The `xencloned` daemon is critical to Nephele as it coordinates the userspace operations and the I/O cloning.
It's worth describing the options it supports:

```
# xencloned --help
Usage: xencloned [OPTION]..

Options:
-D, --daemon                  Run in background
-h, --help                    Display this help and exit
-c, --cache                   Cache parents info
-p, --paused                  Leave clones in paused state
-r, --ring-pages-num <num>    Ring pages number [default: 1]
-n, --no-io                   Skip cloning IO
-x, --use-page-sharing-info-pool   Use page-sharing-info pool
-d, --xenstore-deep-copy      Xenstore deep copy
```

* `-D, --daemon` - launches `xencloned` in background
* `-c, --cache` - caches Xenstore information for parent guests, so that on next cloning requests the information won't be read from Xenstore again
* `-p, --paused` - after cloning completion, the guest remain in the paused state; this is useful for fuzzing because the running of the clones is controlled by the fuzzer
* `-r, --ring-pages-num <num>` - pages number (4K units) for the clone notification ring; increasing the ring size is useful when large numbers of clones are created at once
* `-n, --no-io` - when enabled, Nephele doesn't clone I/O for any guest
* `-x, --use-page-sharing-info-pool` - when enabled, the hypervisor allocates a reserved memory region for the metadata it handles for shared pages; by default, shared pages meta is allocated in the hypervisor dynamic memory 
* `-d, --xenstore-deep-copy` - when enabled, `xencloned` clones parent Xenstore data entry by entry; when disabled, it leverages the `xs_clone` request; this option is used
in the instantiation evaluation for showing the benefits of `xs_clone`
