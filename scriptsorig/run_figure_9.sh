#!/bin/bash

BENCHMARKS="pr cc bc cg"

# BENCHMARKS="xsbench gups svm redis btree graph500 memcached canneal"
#CONFIGS="2MBTHP TRIDENT" #HAWKEYE
# -- Better to re-use 2MBTHP from Figure-1
CONFIGS="HAWKEYE"
# -- For HAWKEYE, boot system with HawkEye and uncomment the following line
#CONFIGS="HAWKEYE"

SCRIPTS=$(dirname `readlink -f "$0"`)
ROOT="$(dirname "$SCRIPTS")"
source $SCRIPTS/common.sh
source $SCRIPTS/configs.sh

for BENCHMARK in $BENCHMARKS; do
	for CONFIG in $CONFIGS; do
		cleanup_system_configs
		setup_4kb_configs
		drop_caches
		prepare_args
		prepare_system_configs
		prepare_paths
		launch_workload
	done
done
