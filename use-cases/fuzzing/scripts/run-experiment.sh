#!/bin/bash

SCRIPT_DIR="$(dirname $0)"
FUZZ_SCRIPT=$SCRIPT_DIR/fuzz.sh
TIMEOUT_SEC=${2:-60}

run_unikraft() {
	$FUZZ_SCRIPT --timeout $TIMEOUT_SEC --unikraft no-cloning --baseline
	$FUZZ_SCRIPT --timeout $TIMEOUT_SEC --unikraft no-cloning
	$FUZZ_SCRIPT --timeout $TIMEOUT_SEC --unikraft cloning --baseline
	$FUZZ_SCRIPT --timeout $TIMEOUT_SEC --unikraft cloning
}

run_linux() {
	$FUZZ_SCRIPT --timeout $TIMEOUT_SEC --linux app --baseline
	$FUZZ_SCRIPT --timeout $TIMEOUT_SEC --linux app
	$FUZZ_SCRIPT --timeout $TIMEOUT_SEC --linux module
}

if [ "$1" = "unikraft" ]; then
	run_unikraft
elif [ "$1" = "linux" ]; then
	run_linux
fi

