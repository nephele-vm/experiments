#/bin/bash
set -e

SCRIPT_DIR="$(realpath $(dirname $0))"

ROOTDIR="${1:-"$SCRIPT_DIR/../dev"}"
ROOTDIR="$(realpath $ROOTDIR)"

NPROC=$(nproc)
JOBS=$(( 4 * $NPROC ))

enter_dir()    { pushd "$1" &>/dev/null; }
enter_newdir() { mkdir -p "$1" &>/dev/null; enter_dir "$1"; }
exit_dir()     { popd &>/dev/null; }

print_banner() {
	echo "###################################################################"
	echo "# $1"
	echo "###################################################################"
}

clone_and_checkout() {
	local repo="$1"
	local branch="$2"
	local name="${3-$(basename $repo)}"

	echo
	echo "*** Cloning '$repo' branch:$branch"

	# clone only if it doesn't exist
	[ ! -d $name ] && git clone "git@github.com:$repo.git" $name

	enter_dir $name
	git checkout $branch
	exit_dir
}

build_ovs() {
	print_banner "Building OVS .."
	clone_and_checkout "nephele-vm/ovs" "nephele-v01"
	enter_dir ovs
	./boot.sh
	./configure --prefix=/root/dist/ovs/ --enable-shared
	make -j$JOBS
	make install
	exit_dir
}

build_xen() {
	print_banner "Building Xen .."
	clone_and_checkout "nephele-vm/xen" "nephele-v01"
	enter_dir xen
	./configure --disable-docs --disable-stubdom --prefix=/root/dist/xen/

	# build hypervisor
	enter_dir xen
	cp $SCRIPT_DIR/xen/config .config
	make -j$JOBS CONFIG_MEM_SHARING=y
	exit_dir

	# build tools
	make -j$JOBS dist-tools CONFIG_SEABIOS=n CONFIG_IPXE=n CONFIG_QEMU_XEN=y CONFIG_QEMUU_EXTRA_ARGS="--disable-slirp --enable-virtfs --disable-werror" OCAML_TOOLS=y
	make install-tools

	exit_dir
}

build_linux() {
	print_banner "Building Linux .."
	clone_and_checkout "nephele-vm/linux" "nephele-v01"
	enter_dir linux

	cp $SCRIPT_DIR/linux/config-light .config
	make -j$JOBS bzImage
	LINUX_VERSION="$(make kernelversion)+"
	INSTALLKERNEL=installkernel sh ./arch/x86/boot/install.sh $LINUX_VERSION arch/x86/boot/bzImage System.map

	make -j$JOBS modules
	make modules_install

	exit_dir
}

build_minios() {
	print_banner "Building Mini-OS .."

	CLONING_APPS_DIR="$ROOTDIR/unikraft/apps/cloning-apps"
	[ ! -d $CLONING_APPS_DIR ] && build_unikraft

	clone_and_checkout "nephele-vm/lwip" "nephele-v01"
	clone_and_checkout "nephele-vm/mini-os" "nephele-v01"

	enter_dir mini-os
	make -j$NPROC debug=n verbose=y CONFIG_PARAVIRT=y CONFIG_NETFRONT=y CONFIG_BLKFRONT=n CONFIG_CONSFRONT=n CONFIG_FBFRONT=n CONFIG_KBDFRONT=n CONFIG_START_NETWORK=y lwip=y LWIPDIR=$ROOTDIR/lwip CLONING_APPS_DIR=$CLONING_APPS_DIR APP=server-udp
	exit_dir
}

UNIKRAFT_LIBS=(
	# "<libname>;<branch>
	"unikraft/lib-intel-intrinsics;1b2af484b21940d7e0eb53b243f30dcb7b5a0ebf"
	"nephele-unikraft/lib-lwip;nephele-v01"
	"nephele-unikraft/lib-mimalloc;nephele-v01"
	"nephele-unikraft/lib-newlib;nephele-v01"
	"unikraft/lib-nginx;d89c9a45d6a19eb71815492acb14b675e2da894a"
	"nephele-unikraft/lib-pthread-embedded;nephele-v01"
	"nephele-unikraft/lib-python3;nephele-v01"
	"nephele-unikraft/lib-redis;nephele-v01"
	"unikraft/lib-tinyalloc;49f1efcce141ecc2c6d01731f1afea2d0c619eea"
)
UNIKRAFT_APPS=(
	# "<appname>;<branch>
	"nephele-vm/cloning-apps;nephele-v01"
	"nephele-unikraft/app-nginx;nephele-v01"
	"nephele-unikraft/app-python;nephele-v01"
	"nephele-unikraft/app-redis;nephele-v01"
)

build_unikraft() {
	print_banner "Building Unikraft .."
	enter_newdir "unikraft"

	# Clone kernel
	clone_and_checkout "nephele-unikraft/unikraft" "nephele-v01"

	# Clone libs
	enter_newdir "libs"
	for entry in "${UNIKRAFT_LIBS[@]}"; do
		IFS=";" read repo branch <<< "$entry"
		local name=$(basename $repo)
		name=${name#"lib-"}
		clone_and_checkout "$repo" $branch $name
	done
	exit_dir

	# Clone apps
	enter_newdir "apps"
	for entry in "${UNIKRAFT_APPS[@]}"; do
		IFS=";" read repo branch <<< "$entry"
		local name=$(basename $repo)
		name=${name#"app-"}
		clone_and_checkout "$repo" $branch $name

		enter_dir $name

		# copy config file
		cp config/config-unikraft-build .config

		# build
		if [ "$name" = "cloning-apps" ]; then
			make -f Makefile.unikraft prepare
			make -f Makefile.unikraft -j$JOBS
		else
			make prepare
			make -j$JOBS
		fi
		exit_dir
	done
	exit_dir

	exit_dir
}

[ ! -d $ROOTDIR ] && mkdir -p $ROOTDIR
enter_dir $ROOTDIR

build_ovs
build_xen
build_linux
build_unikraft
build_minios

exit_dir

