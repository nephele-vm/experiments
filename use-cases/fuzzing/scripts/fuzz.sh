#!/bin/bash

APP_PARAM_TRACE_SYSCALLS=0
APP_PARAM_BASELINE=0
TIMEOUT_SEC=300
PLOT_INTERVAL_MSEC=500
DO_BUILD=0
DO_LOG=0
LOGFILE="kfx.log"
#GDB="gdbserver :2000"

SCRIPT_DIR="$(dirname $0)"
DATA_EXTRACTOR_SCRIPT="$SCRIPT_DIR/data_extractor.py"

DOMAIN_NAME=""

# configuration
if [ ! -f "$FUZZ_CONFIG_FILE" ]; then
	if [ -z "$FUZZ_CONFIG_FILE" ]; then
		echo "FUZZ_CONFIG_FILE environment variable should point to configuration parameters"
	else
		echo "Invalid config file: $FUZZ_CONFIG_FILE"
	fi
	exit 2
fi
source $FUZZ_CONFIG_FILE


usage() {
	echo "Usage:"
	echo "$0 --unikraft(cloning|no-cloning) <Options>"
	echo "$0 --linux(app|module) <Options>"
	echo
	echo "Options:"
	echo "   -t, --time <seconds>     Session duration"
}
usage_and_exit() {
	usage
	exit $1
}


# Parse arguments
while [[ $# -gt 0 ]]; do
	key="$1"
	case $key in
	--unikraft)
		SYSTEM="unikraft"
		MODE="$2"
		shift # past argument
		shift # past value
		if [ "$MODE" != "cloning" -a "$MODE" != "no-cloning" ]; then
			usage_and_exit 1
		fi
		;;
	--linux)
		SYSTEM="linux"
		MODE="$2"
		shift # past argument
		shift # past value
		if [ "$MODE" != "app" -a "$MODE" != "module" ]; then
			usage_and_exit 1
		fi
		;;	
	--trace-syscalls)
		APP_PARAM_TRACE_SYSCALLS=1
		shift # past argument
		;;
	--baseline)
		APP_PARAM_BASELINE=1
		shift # past argument
		;;
	--timeout)
		TIMEOUT_SEC=$2
		shift # past argument
		shift # past value
		;;
	--build)
		DO_BUILD=1
		shift # past argument
		;;
	--log)
		DO_LOG=1
		shift # past argument
		;;
	--debug)
		DEBUG="-vvvvvvvvvvvv"
		DO_LOG=1
		shift # past argument
		;;
	*)
		echo "Unknown option: $key"
		exit 1
		;;
		
	esac
done
if [ -z $SYSTEM ]; then
	usage_and_exit 2
fi

generate_cmdline() {
	local cmdline=""
	if [ $SYSTEM = "unikraft" ]; then
		cmdline="$cmdline --close-stdin"
		[ $MODE = "no-cloning" ] && cmdline="$cmdline -r"
	fi
	[ $APP_PARAM_TRACE_SYSCALLS -eq 1 ] && cmdline="$cmdline -t"
	[ $APP_PARAM_BASELINE -eq 1 ] && cmdline="$cmdline --baseline"
	echo $cmdline
}

generate_config_file() {
	local tmpl="$1"
	local generated="$2"
	export APP_CMDLINE="$(generate_cmdline)"
	envsubst < $tmpl > $generated
}

create_vm() {
	local xl_config="$1"
	if [ ! -f "$xl_config" ]; then
		echo "Invalid xl config file: $xl_config"
		exit 2
	fi

	echo "Create VM from config: $xl_config"
	DOMAIN_NAME=$(grep '^ *name *=' $xl_config | cut -d'"' -f2)
	echo "Name: $DOMAIN_NAME"

	local img=$(grep '^ *kernel *=' $xl_config | cut -d'"' -f2)
	echo "Image: $img"

	xl create -q -e $xl_config
}

create_io_dirs() {
	[ ! -d $AFL_INPUT_DIR ] && mkdir -p $AFL_INPUT_DIR
	#[ ! -f $AFL_INPUT_DIR/example0 ] && truncate -s 28 > $AFL_INPUT_DIR/example0
	[ ! -f $AFL_INPUT_DIR/example0 ] && echo aaaa > $AFL_INPUT_DIR/example0
	[ ! -d $AFL_OUTPUT_DIR ] && mkdir -p $AFL_OUTPUT_DIR
}

kfx_setup() {
	local vm_json_file="$1"
	if [ ! -f "$vm_json_file" ]; then
		echo "Invalid JSON file: $vm_json_file"
		exit 2
	fi

	[ $DO_LOG -eq 1 ] && log_params="--logfile $LOGFILE.setup"


	#LIBVMI_DEBUG=1 $KFX --domain $DOMAIN_NAME $log_params --json $vm_json_file --setup &
	$KFX --domain $DOMAIN_NAME $log_params --json $vm_json_file --setup &
	KFX_SETUP_PID=$!
}

STEP_REQUIRES_CONFIRMATION=0
mark_step() {
	if [ $STEP_REQUIRES_CONFIRMATION -eq 1 ]; then
		read -p "$1" resp
	else
		#echo "$1"
		return
	fi
}

run_fuzzer() {
	echo "Waiting for setup completion.."
	while pgrep kfx &>/dev/null; do continue; done
	echo "Done"

	mark_step "Start fuzzing"

	local results_dir="$SCRIPT_DIR/syscalls_results"
	mkdir -p $results_dir
	plot_file="$results_dir/results.$SYSTEM.$MODE"
	[ $APP_PARAM_BASELINE -eq 1 ] && plot_file="$plot_file.baseline"

	[ $DO_LOG -eq 1 ] && log_params="--logfile $LOGFILE"

	if [ $SYSTEM == "linux" ]; then
		if [ $MODE == "app" ]; then
			$AFL \
				-i $AFL_INPUT_DIR \
				-o $AFL_OUTPUT_DIR \
				-P $PLOT_INTERVAL_MSEC \
				-D $(($TIMEOUT_SEC * 1000)) \
				$LIN_APP_BIN $(generate_cmdline)

		else
			# Linux module
			$AFL \
				-i $AFL_INPUT_DIR \
				-o $AFL_OUTPUT_DIR \
				-P $PLOT_INTERVAL_MSEC \
				-m 500 -X -- \
				$KFX $DEBUG \
				$log_params \
				--domain $DOMAIN_NAME \
				--json $LIN_VM_JSON \
				--input @@ \
				--input-limit $FUZZ_SIZE \
				--address $FUZZ_ADDRESS
		fi

	elif [ $SYSTEM == "unikraft" ]; then
		local cloning_param=""
		[ $MODE == "no-cloning" ] && cloning_param="--no-cloning $UK_XL_CONFIG_GENERATED"

		$AFL \
			-i $AFL_INPUT_DIR \
			-o $AFL_OUTPUT_DIR \
			-P $PLOT_INTERVAL_MSEC \
			-m 1024 -X -t 10000 -- \
			$GDB $KFX $DEBUG \
			$log_params \
			--domain $DOMAIN_NAME \
			--json $UK_VM_JSON \
			--input @@ \
			--input-limit $FUZZ_SIZE \
			--address $FUZZ_ADDRESS \
			--duration $TIMEOUT_SEC \
			$cloning_param \
			--os Unikraft
	fi

	# process results
	python3 $DATA_EXTRACTOR_SCRIPT $AFL_OUTPUT_DIR/plot_data $plot_file
}

fuzz_linux_app() {
	if [ $DO_BUILD -eq 1 ]; then
		set -e
		make -C $LIN_APP_DIR -f Makefile.linux
		set +e
	fi

	run_fuzzer
}

fuzz_linux_module() {
	create_vm $LIN_XL_CONFIG

	kfx_setup $LIN_VM_JSON

	VM_IP="10.0.0.2"
	REMOTE="root@$VM_IP"

	mark_step "Insert module"

	local vm_not_ready=1
	while [ $vm_not_ready -ne 0 ]; do
		ping -c 1 -W 1 $VM_IP &>/dev/null
		vm_not_ready=$?
	done
	echo "VM is up, inserting module.."
	ssh $REMOTE insmod $LIN_MODULE &
	sleep 1

	FUZZ_ADDRESS=$(xl dmesg | grep "Kernel Fuzzer Test Module" | tail -n 1 | grep -o "Test1 [^ ]\+" | cut -d' ' -f2)
	FUZZ_SIZE=8
	echo "Fuzzing address: $FUZZ_ADDRESS"
	echo "Fuzzing size:    $FUZZ_SIZE"

	run_fuzzer
}

fuzz_linux() {
	fuzz_${SYSTEM}_${MODE}
}

send_trigger_for_harnessing() {
	local has_network=0
	if [ $has_network -eq 1 ]; then
		local vm_not_ready=1
		while [ $vm_not_ready -ne 0 ]; do
			ping -c 1 -W 1 $VM_IP &> /dev/null
			vm_not_ready=$?
		done
		echo "VM is up, sending trigger .."
		echo foo | nc -u $VM_IP 13
	else
		echo "VM is up, sending trigger ..."
		lastid=$(xl list | tail -n 1 | tr -s ' ' | cut -d' ' -f2)
		xenstore-write /local/domain/$lastid/data/trigger-harness done
	fi
}

fuzz_unikraft() {
	# build if required
	if [ $DO_BUILD -eq 1 ]; then
		set -e
		make -C $UK_APP_FUZZ -f Makefile.unikraft
		set +e
	fi

	FUZZ_ADDRESS=$(objdump -x $UK_APP_BIN | grep gCall | tr -s ' ' | tr '\t' ' ' | cut -d' ' -f1 | sed 's/\(.*\)/0x\1/g')
	FUZZ_SIZE=$(objdump -x $UK_APP_BIN | grep gCall | tr -s ' ' | tr '\t' ' ' | cut -d' ' -f5 | sed 's/\(.*\)/0x\1/g')
	echo "Fuzzing address: $FUZZ_ADDRESS"
	echo "Fuzzing size:    $FUZZ_SIZE"

	# generate xl config
	UK_XL_CONFIG_GENERATED="${UK_XL_CONFIG_TMPL%.tmpl}.generated"
	generate_config_file $UK_XL_CONFIG_TMPL $UK_XL_CONFIG_GENERATED

	mark_step "Create VM"
	create_vm $UK_XL_CONFIG_GENERATED
	sleep 1

	kfx_setup $UK_VM_JSON
	sleep 1
	send_trigger_for_harnessing

	mark_step "Run fuzzer"
	run_fuzzer
}

main() {
	# cleanup
	killall kfx &>/dev/null
	sleep 2
	/root/scripts/xen/destroy-domains.sh

	create_io_dirs

	# run the fuzzing session
	fuzz_$SYSTEM
}

main

