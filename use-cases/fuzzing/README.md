# Use cases: Fuzzing

We use [Kernel Fuzzer for Xen Project (KF/x)](https://github.com/nephele-vm/kernel-fuzzer-for-xen-project) to fuzz Unikraft on Xen.

Components:
* [Kernel Fuzzer for Xen Project fork](https://github.com/nephele-vm/kernel-fuzzer-for-xen-project) with changes for running PV guests with cloning support
* [libvmi fork](https://github.com/nephele-vm/libvmi) adding support for Unikraft introspection
* [AFL fork](https://github.com/nephele-vm/AFL) with minor changes needed to run the fuzzing experiment
* [Unikraft fuzzing application](https://github.com/nephele-unikraft/app-fuzz) used for fuzzing syscall support
* [scripts](https://github.com/nephele-vm/experiments/tree/main/use-cases/fuzzing/scripts) needed to run the experiment for Unikraft, Linux process and Linux kernel module
