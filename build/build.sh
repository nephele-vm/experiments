#/bin/bash
set -e

SCRIPT_DIR="$(realpath $(dirname $0))"

ROOTDIR="${ROOTDIR:-"$SCRIPT_DIR/../dev"}"
ROOTDIR="$(realpath $ROOTDIR)"

NPROC=$(nproc)
JOBS=$(( 4 * $NPROC ))

DO_BUILD=${DO_BUILD:-1}
DO_DEV=0

# Set default branch
if [ $DO_DEV -eq 1 ]; then
	BRANCH_DEFAULT="nephele-v01"
else
	BRANCH_DEFAULT="tags/eurosys23"
fi

cat /etc/*release* | grep -i alpine &>/dev/null && OS="alpine"

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
	local name="${3:-$(basename $repo)}"
	local submodules="${4:-no}"

	echo
	Green='\033[0;32m'
	NC='\033[0m'
	echo -e "${Green}*** Cloning '$repo' branch:$branch${NC}"

	# clone only if it doesn't exist
	if [ ! -d $name ]; then
		if [ $DO_DEV -eq 1 ]; then
			git clone "git@github.com:$repo.git" $name
		else
			git clone "https://github.com/$repo.git" $name
		fi
	fi

	enter_dir $name
	local current_branch_basename=$(basename $(git rev-parse --abbrev-ref HEAD))
	local branch_basename=$(basename $branch)
	if [ "$current_branch_basename" != "$branch_basename" ]; then
		if [ `dirname $branch` = "tags" ]; then
			git checkout $branch -b "$branch_basename"
		else
			git checkout $branch
		fi
	fi
	[ "$submodules" = "yes" ] && git submodule update --init
	exit_dir
}

build_ovs() {
	print_banner "OVS"
	clone_and_checkout "nephele-vm/ovs" "$BRANCH_DEFAULT"
	OVS_DIST=/root/dist/ovs/
	if [ $DO_BUILD -eq 1 -a ! -d "$OVS_DIST" ]; then
		enter_dir ovs
		if [ ! -f config.log ]; then
			./boot.sh
			./configure --prefix="$OVS_DIST" --enable-shared
		fi
		make -j$JOBS
		make install
		exit_dir
	fi
	export OVS_SRC=$(realpath ovs)
	echo "OVS_SRC=$OVS_SRC"
}

build_xen() {
	local component="$1"
	print_banner "Xen $component"
	clone_and_checkout "nephele-vm/xen" "$BRANCH_DEFAULT"
	if [ $DO_BUILD -eq 1 ]; then
		[ "$component" = "tools" -o "$component" = "all" ] && build_ovs

		enter_dir xen

		# configure
		[ ! -f config.log ] && ./configure --disable-docs --disable-stubdom #--prefix=/root/dist/xen/

		# build hypervisor
		if [ "$component" = "hypervisor" -o "$component" = "all" ]; then
			enter_dir xen
			cp $SCRIPT_DIR/xen/config .config
			make -j$JOBS CONFIG_MEM_SHARING=y
			exit_dir
		fi

		# build tools
		if [ "$component" = "tools" -o "$component" = "all" ]; then
			make -j$JOBS dist-tools CONFIG_SEABIOS=n CONFIG_IPXE=n CONFIG_QEMU_XEN=y CONFIG_QEMUU_EXTRA_ARGS="--disable-slirp --enable-virtfs --disable-werror" OCAML_TOOLS=y GIT_HTTP=y
			make install-tools
		fi

		exit_dir
	fi
}

build_linux() {
	print_banner "Linux"
	clone_and_checkout "nephele-vm/linux" "$BRANCH_DEFAULT"
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

build_kfx() {
	print_banner "KFX"
	clone_and_checkout "nephele-vm/kernel-fuzzer-for-xen-project" "$BRANCH_DEFAULT" "kfx" "yes"
	if [ $DO_BUILD -eq 1 ]; then
		if [ "$OS" = "alpine" ]; then
			apk add capstone-dev cmake json-c-dev
		else
			echo "Unsupported OS for building KFX"
			exit 2
		fi

		enter_dir kfx

		# libvmi
		enter_dir libvmi
		autoreconf -vif
		./configure --disable-kvm --disable-bareflank --disable-file
		make -j4
		make install
		set +e
		ldconfig
		set -e
		exit_dir

		# kfx
		autoreconf -vif
		./configure
		make -j$JOBS

		# AFL
		enter_dir AFL
		patch -p1 < ../patches/0001-AFL-Xen-mode.patch
		make -j$JOBS
		exit_dir

		exit_dir
	fi
}

build_minios() {
	print_banner "Mini-OS"

	CLONING_APPS_DIR="$ROOTDIR/unikraft/apps/cloning-apps"
	if [ $DO_BUILD -eq 1 ]; then
		[ ! -d $CLONING_APPS_DIR ] && build_unikraft
	fi

	clone_and_checkout "nephele-vm/lwip" "$BRANCH_DEFAULT"
	clone_and_checkout "nephele-vm/mini-os" "$BRANCH_DEFAULT"

	if [ $DO_BUILD -eq 1 ]; then
		enter_dir mini-os
		make -j$NPROC debug=n verbose=y CONFIG_PARAVIRT=y CONFIG_NETFRONT=y CONFIG_BLKFRONT=n CONFIG_CONSFRONT=n CONFIG_FBFRONT=n CONFIG_KBDFRONT=n CONFIG_START_NETWORK=y lwip=y LWIPDIR=$ROOTDIR/lwip CLONING_APPS_DIR=$CLONING_APPS_DIR APP=server-udp
		exit_dir
	fi
}

UNIKRAFT_LIBS=(
	# "<libname>;<branch>
	"unikraft/lib-intel-intrinsics;1b2af484b21940d7e0eb53b243f30dcb7b5a0ebf"
	"nephele-unikraft/lib-lwip;$BRANCH_DEFAULT"
	"nephele-unikraft/lib-mimalloc;$BRANCH_DEFAULT"
	"nephele-unikraft/lib-newlib;$BRANCH_DEFAULT"
	"nephele-unikraft/lib-nginx;$BRANCH_DEFAULT"
	"nephele-unikraft/lib-pthread-embedded;$BRANCH_DEFAULT"
	"nephele-unikraft/lib-python3;$BRANCH_DEFAULT"
	"nephele-unikraft/lib-redis;$BRANCH_DEFAULT"
	"unikraft/lib-tinyalloc;49f1efcce141ecc2c6d01731f1afea2d0c619eea"
)
UNIKRAFT_APPS=(
	# "<appname>;<branch>
	"nephele-vm/cloning-apps;$BRANCH_DEFAULT"
	"nephele-unikraft/app-nginx;$BRANCH_DEFAULT"
	"nephele-unikraft/app-python;$BRANCH_DEFAULT"
	"nephele-unikraft/app-redis;$BRANCH_DEFAULT"
	"nephele-unikraft/app-fuzz;$BRANCH_DEFAULT"
)

build_unikraft() {
	print_banner "Building Unikraft .."
	enter_newdir "unikraft"

	# Clone kernel
	clone_and_checkout "nephele-unikraft/unikraft" "$BRANCH_DEFAULT"

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
			if [ "$name" = "cloning-apps" -o "$name" = "fuzz" ]; then
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
	build_unikraft
	build_minios
	build_kfx

elif [ "$COMPONENT" = "xen" ]; then
	build_xen hypervisor

elif [ "$COMPONENT" = "linux" ]; then
	build_linux kernel
	build_linux modules

elif [ "$COMPONENT" = "userspace" ]; then
	build_xen tools

elif [ "$COMPONENT" = "guests" ]; then
	build_unikraft
	build_minios

elif [ "$COMPONENT" = "kfx" ]; then
	build_kfx

else
	echo "Unknown component: $COMPONENT."
	echo "Usage: $0 [all|xen|linux|userspace|guests|kfx]"
	exit 2
fi

exit_dir

