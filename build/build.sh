#/bin/bash
set -e

SCRIPT_DIR="$(realpath $(dirname $0))"

ROOTDIR="${1:-"$SCRIPT_DIR/../dev"}"
ROOTDIR="$(realpath $ROOTDIR)"

NPROC=$(nproc)
JOBS=$(( 4 * $NPROC ))

DO_BUILD=${DO_BUILD:-1}

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
	Green='\033[0;32m'
	NC='\033[0m'
	echo -e "${Green}*** Cloning '$repo' branch:$branch${NC}"

	# clone only if it doesn't exist
	[ ! -d $name ] && git clone "git@github.com:$repo.git" $name

	enter_dir $name
	git checkout $branch
	exit_dir
}

build_ovs() {
	print_banner "OVS"
	clone_and_checkout "nephele-vm/ovs" "nephele-v01"
	if [ $DO_BUILD -eq 1 ]; then
		enter_dir ovs
		./boot.sh
		./configure --prefix=/root/dist/ovs/ --enable-shared
		make -j$JOBS
		make install
		exit_dir
	fi
}

build_xen() {
	local component="$1"
	print_banner "Xen $component"
	clone_and_checkout "nephele-vm/xen" "nephele-v01"
	if [ $DO_BUILD -eq 1 ]; then
		enter_dir xen

		# configure
		[ -f config.log ] && ./configure --disable-docs --disable-stubdom --prefix=/root/dist/xen/

		# build hypervisor
		if [ "$component" = "hypervisor" -o "$component" = "all" ]; then
			enter_dir xen
			cp $SCRIPT_DIR/xen/config .config
			make -j$JOBS CONFIG_MEM_SHARING=y
			exit_dir
		fi

		# build tools
		if [ "$component" = "tools" -o "$component" = "all" ]; then
			make -j$JOBS dist-tools CONFIG_SEABIOS=n CONFIG_IPXE=n CONFIG_QEMU_XEN=y CONFIG_QEMUU_EXTRA_ARGS="--disable-slirp --enable-virtfs --disable-werror" OCAML_TOOLS=y
			make install-tools
		fi

		exit_dir
	fi
}

build_linux() {
	print_banner "Linux"
	clone_and_checkout "nephele-vm/linux" "nephele-v01"
	if [ $DO_BUILD -eq 1 ]; then
		enter_dir linux

		# configure
		[ ! -f .config ] && cp $SCRIPT_DIR/linux/config-light .config

		if [ "$component" = "kernel" -o "$component" = "all" ]; then
			make -j$JOBS bzImage
			LINUX_VERSION="$(make kernelversion)+"
			INSTALLKERNEL=installkernel sh ./arch/x86/boot/install.sh $LINUX_VERSION arch/x86/boot/bzImage System.map
		fi

		# build modules
		if [ "$component" = "modules" -o "$component" = "all" ]; then
			make -j$JOBS modules
			make modules_install
		fi

		exit_dir
	fi
}

build_minios() {
	print_banner "Mini-OS"

	CLONING_APPS_DIR="$ROOTDIR/unikraft/apps/cloning-apps"
	if [ $DO_BUILD -eq 1 ]; then
		[ ! -d $CLONING_APPS_DIR ] && build_unikraft
	fi

	clone_and_checkout "nephele-vm/lwip" "nephele-v01"
	clone_and_checkout "nephele-vm/mini-os" "nephele-v01"

	if [ $DO_BUILD -eq 1 ]; then
		enter_dir mini-os
		make -j$NPROC debug=n verbose=y CONFIG_PARAVIRT=y CONFIG_NETFRONT=y CONFIG_BLKFRONT=n CONFIG_CONSFRONT=n CONFIG_FBFRONT=n CONFIG_KBDFRONT=n CONFIG_START_NETWORK=y lwip=y LWIPDIR=$ROOTDIR/lwip CLONING_APPS_DIR=$CLONING_APPS_DIR APP=server-udp
		exit_dir
	fi
}

UNIKRAFT_LIBS=(
	# "<libname>;<branch>
	"unikraft/lib-intel-intrinsics;1b2af484b21940d7e0eb53b243f30dcb7b5a0ebf"
	"nephele-unikraft/lib-lwip;nephele-v01"
	"nephele-unikraft/lib-mimalloc;nephele-v01"
	"nephele-unikraft/lib-newlib;nephele-v01"
	"nephele-unikraft/lib-nginx;nephele-v01"
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
	"nephele-unikraft/app-fuzz;nephele-v01"
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

		if [ $DO_BUILD -eq 1 ]; then
			if [ "$name" = "cloning-apps" ]; then
				make -f Makefile.unikraft prepare
				make -f Makefile.unikraft -j$JOBS
			else
				make prepare
				make -j$JOBS
			fi
		fi
		exit_dir
	done
	exit_dir

	exit_dir
}

[ ! -d $ROOTDIR ] && mkdir -p $ROOTDIR
enter_dir $ROOTDIR

COMPONENT="$1"

if [ -z "$COMPONENT" -o "$COMPONENT" = "all" ]; then
	build_xen all
	build_linux all
	build_ovs
	build_unikraft
	build_minios

elif [ "$COMPONENT" = "xen" ]; then
	build_xen hypervisor

elif [ "$COMPONENT" = "linux" ]; then
	build_linux kernel
	build_linux modules

elif [ "$COMPONENT" = "userspace" ]; then
	build_xen tools
	build_ovs

elif [ "$COMPONENT" = "guests" ]; then
	build_unikraft
	build_minios

else
	echo "Unknown component: $COMPONENT."
	echo "Usage: $0 [all|xen|linux|userspace|guests]"
	exit 2
fi

exit_dir

