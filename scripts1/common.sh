#!/bin/bash

# --- set of common functions and variables used across all experiments
MEMCACHED_ARGS=" "
CANNEAL_ARGS=" 1 150000 2000 $ROOT/datasets/canneal_small 7500 "
XSBENCH_ARGS=" -s XL -t 24 -l 800000000"
GRAPH500_ARGS=" -s 26 -e 30"
SVM_ARGS="-s 6 -n 36 $ROOT/datasets/kdd12"
GUPS_ARGS=" 32 5000000 1024"
GAPBS_ARGS=" -g 25 -n 20 -i 20"
GRAPHIT_ARGS=" /mydata/PCC-artefacts/data/Kronecker_25/ 0 0"
#GAPBFS_ARGS=" -g 28 -n 20 -i 20"
BC_ARGS=" -g 29 -n 2 -i 2"

# always run on socket-0
DATA_NODE=0
CPU_NODE=0

THHP_MONITOR_PID=0  # Global PID variable
MEM_MONITOR_PID=0  # Global PID variable
sstart_ts=0         # Global timestamp


COUT="/dev/null"
drop_caches()
{
	echo "Dropping caches for config: $CONFIG"
	echo 3 |  sudo tee /proc/sys/vm/drop_caches > $COUT
}

fragment_memory()
{
	if [[ $CONFIG = *F* ]]; then
                echo "Fragmenting memory for config: $CONFIG"
                if [ ! -e $FRAG_FILE_1 ] || [ ! -e $FRAG_FILE_2 ]; then
                        echo "***FRAGMENTATION FILES MISSING***"
                        exit
                fi
                echo -e "Reading first file"
                $ROOT/bin/numactl -c $CPU_NODE -m $DATA_NODE cat $FRAG_FILE_1 > $COUT &
                PID_1=$!
                echo -e "Reading second file"
                $ROOT/bin/numactl -c $CPU_NODE -m $DATA_NODE cat $FRAG_FILE_2 > $COUT &
                PID_2=$!
                echo "Waiting for files to load in memory: PID1: $PID_1 PID2: $PID_2"
                wait $PID_1
                wait $PID_2
                echo -e "Launching client to fragment memory...."
                # --- Run for 10 minutes
                $ROOT/bin/numactl -c $CPU_NODE -m $DATA_NODE python $SCRIPTS/fragment.py $FRAG_FILE_1 $FRAG_FILE_2 600 36 > $COUT
        else
		drop_caches
        fi
}

prepare_paths()
{
        BENCHPATH=$ROOT"/bin/$BENCHMARK"
        INTERFERENCEPATH=$ROOT"/bin/bench_stream"
        PERF=$ROOT"/bin/perf"
        NUMACTL=$ROOT"/bin/numactl"
        if [ ! -e $BENCHPATH ]; then
            echo "Benchmark binary is missing: $BENCHPATH"
            exit
        fi
        if [ ! -e $PERF ]; then
            echo "Perf binary is missing: $PERF "
            exit
        fi
        if [ ! -e $NUMACTL ]; then
            echo "numactl is missing: $NUMACTL"
            exit
        fi
        # where to put the output file (based on CONFIG)
        DATADIR=$ROOT"/evaluation/$BENCHMARK"
        RUNDIR=$DATADIR/$(hostname)-$BENCHMARK--$CONFIG--$(date +"%Y%m%d-%H%M%S")
        mkdir -p $RUNDIR
        if [ $? -ne 0 ]; then
                echo "Error creating output directory: $RUNDIR"
        fi
        OUTFILE=$RUNDIR/perflog-$BENCHMARK-$(hostname)-$CONFIG.dat
        LOGFILE=$RUNDIR/runlog-$BENCHMARK-$(hostname)-$CONFIG.log
}

prepare_args()
{
        BENCH_ARGS=""
        if [ $BENCHMARK = "canneal" ]; then
                BENCH_ARGS=$CANNEAL_ARGS
        elif [ $BENCHMARK = "gups" ]; then
                BENCH_ARGS=$GUPS_ARGS 
        elif [ $BENCHMARK = "memcached" ]; then
                BENCH_ARGS=$MEMCACHED_ARGS 
        elif [ $BENCHMARK = "xsbench" ]; then
                BENCH_ARGS=$XSBENCH_ARGS
        elif [ $BENCHMARK = "graph500" ]; then
                BENCH_ARGS=$GRAPH500_ARGS
        elif [ $BENCHMARK = "svm" ]; then
                BENCH_ARGS=$SVM_ARGS
        elif [ $BENCHMARK = "bc" ]; then
                BENCH_ARGS=$BC_ARGS
        #Asish : added bfs and sssp
        elif [ $BENCHMARK = "pr" ] || [ $BENCHMARK = "cc" ]; then 
                BENCH_ARGS=$GAPBS_ARGS
        elif [ $BENCHMARK = "bfs" ] || [ $BENCHMARK = "sssp" ] || [ $BENCHMARK = "pgr" ]; then
                BENCH_ARGS=$GRAPHIT_ARGS
        fi
}

setup_trident_configs()
{
        THP="always"
        echo $THP |  sudo tee /sys/kernel/mm/transparent_hugepage/enabled > $COUT 2>&1
        echo 1 |  sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/defrag > $COUT 2>&1
        echo 1 |  sudo tee /sys/kernel/mm/transparent_hugepage/enabled_pmd > $COUT 2>&1
        echo 1 |  sudo tee /sys/kernel/mm/transparent_hugepage/enabled_pud > $COUT 2>&1
        echo 1 |  sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/khugepaged_collapse_pmd > $COUT 2>&1
        echo 1 |  sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/khugepaged_collapse_pud > $COUT 2>&1
        echo 1 |  sudo tee /proc/sys/vm/compaction_smart > $COUT 2>&1
        echo 5 |  sudo tee /proc/sys/vm/smart_compaction_retries > $COUT 2>&1
        echo 2097152 |  sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/pages_to_scan > $COUT 2>&1
	echo 0 | sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/collapse_via_hypercall > $COUT 2>&1
	echo 0 | sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/max_cpu > $COUT 2>&1
}

setup_trident_nosmart_configs()
{
	setup_trident_configs
        echo 0 |  sudo tee /proc/sys/vm/compaction_smart > $COUT 2>&1
        echo 1 |  sudo tee /proc/sys/vm/smart_compaction_retries > $COUT 2>&1
}

setup_trident_1gbonly_configs()
{
	setup_trident_configs
        echo 0 |  sudo tee /sys/kernel/mm/transparent_hugepage/enabled_pmd > $COUT 2>&1
        echo 0 |  sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/khugepaged_collapse_pmd > $COUT 2>&1
}

setup_tridentpv_configs()
{
	setup_trident_configs
	echo 1 | sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/collapse_via_hypercall > $COUT 2>&1
	echo 10 | sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/max_cpu > $COUT 2>&1
}

setup_2mbthp_configs()
{
        THP="always"
        echo $THP |  sudo tee /sys/kernel/mm/transparent_hugepage/enabled > $COUT 2>&1 
        echo never |  sudo tee /sys/kernel/mm/transparent_hugepage/enabled_1gb > $COUT 2>&1
        echo 1 |  sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/defrag > $COUT 2>&1
        echo 1 |  sudo tee /sys/kernel/mm/transparent_hugepage/enabled_pmd > $COUT 2>&1
        echo 0 |  sudo tee /sys/kernel/mm/transparent_hugepage/enabled_pud > $COUT 2>&1
        echo 1 |  sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/khugepaged_collapse_pmd > $COUT 2>&1
        echo 0 |  sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/khugepaged_collapse_pud > $COUT 2>&1
        echo 0 |  sudo tee /proc/sys/vm/compaction_smart > $COUT 2>&1
        #echo 5 |  sudo tee /proc/sys/vm/smart_compaction_retries
        echo 4096 |  sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/pages_to_scan > $COUT 2>&1
}

setup_4kb_configs()
{
        THP="never"
        echo $THP |  sudo tee /sys/kernel/mm/transparent_hugepage/enabled > $COUT 2>&1
        echo $THP |  sudo tee /sys/kernel/mm/transparent_hugepage/enabled_1gb > $COUT 2>&1
        echo 0 |  sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/defrag > $COUT 2>&1
        echo 0 |  sudo tee /sys/kernel/mm/transparent_hugepage/enabled_pmd > $COUT 2>&1
        echo 0 |  sudo tee /sys/kernel/mm/transparent_hugepage/enabled_pud > $COUT 2>&1
        echo 0 |  sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/khugepaged_collapse_pmd > $COUT 2>&1
        echo 0 |  sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/khugepaged_collapse_pud > $COUT 2>&1
        echo 0 |  sudo tee /proc/sys/vm/compaction_smart > $COUT 2>&1
        #echo 5 |  sudo tee /proc/sys/vm/smart_compaction_retries
        echo 4096 |  sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/pages_to_scan > $COUT 2>&1
}

adjust_hugetlb_pages()
{
	if [ -z $BENCHMARK ]; then
		return
	elif [ $BENCHMARK = "graph500" ]; then
		HUGETLB_2MB_PAGES=40000
		HUGETLB_1GB_PAGES=80
	elif [ $BENCHMARK = "memcached" ]; then
		HUGETLB_2MB_PAGES=15000
		HUGETLB_1GB_PAGES=30
	fi
}

MBSYSCTL='/sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages'
GBSYSCTL='/sys/devices/system/node/node0/hugepages/hugepages-1048576kB/nr_hugepages'
prepare_system_configs()
{
	adjust_hugetlb_pages
        # --- reserve/drain HUGETLB Pool
	if [[ $CONFIG = *2MBHUGE* ]]; then
		echo $HUGETLB_2MB_PAGES | sudo tee $MBSYSCTL > $COUT 2>&1
	elif [[ $CONFIG = *1GBHUGE* ]]; then
		echo $HUGETLB_1GB_PAGES | sudo tee $GBSYSCTL > $COUT 2>&1
	fi
	# reserve hugetlb pages
        $ROOT/bin/numactl -m $DATA_NODE echo $NR_HUGETLB_PAGES |
		sudo tee /proc/sys/vm/nr_hugepages_mempolicy > $COUT 2>&1
        if [[ $CONFIG = *2MB* ]]; then
                setup_2mbthp_configs
        elif [[ $CONFIG = *HAWKEYE* ]]; then
                setup_2mbthp_configs
        elif [[ $CONFIG = *1GBHUGE* ]]; then
                setup_2mbthp_configs #leave 2MB THP on even when 1GB HUGETLB is enabled
        elif [ $CONFIG = "TRIDENT" ]; then
                setup_trident_configs
        elif [[ $CONFIG = *TRIDENT-NC* ]]; then # TRIDENT with no smart compaction
                setup_trident_nosmart_configs
        elif [[ $CONFIG = *TRIDENT-1G* ]]; then # TRIDENT with 1GB pages only
                setup_trident_1gbonly_configs
        elif [[ $CONFIG = *TRIDENT*PV* ]]; then # Paravirtualized TRIDENT
		setup_tridentpv_configs
        else
                setup_4kb_configs
        fi
        echo "Configuration: $CONFIG completed."
}

cleanup_system_configs()
{
        # --- Drain HUGETLB Pool
	echo 0 | sudo tee $MBSYSCTL > $COUT 2>&1
	echo 0 | sudo tee $GBSYSCTL > $COUT 2>&1
	echo 0 | sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/max_cpu > $COUT 2>&1
}

# # Add these functions to your script
# start_hugepage_monitor() {
#     local log_file="$RUNDIR/hugepages_ts.log"
#     echo "timestamp,allocated_2mb,free_2mb,allocated_1gb,free_1gb" > "$log_file"
    
#     # Determine which hugepages to monitor based on config
#     local monitor_2mb=0
#     local monitor_1gb=0
    
#     [[ $CONFIG = *2MB* ]] && monitor_2mb=1
#     [[ $CONFIG = *1GB* ]] && monitor_1gb=1

#     while true; do
#         local ts=$(date +%s)
#         local mb_alloc=0
#         local mb_free=0
#         local gb_alloc=0 
#         local gb_free=0
        
#         if [ $monitor_2mb -eq 1 ]; then
#             mb_alloc=$(cat $MBSYSCTL)
#             mb_free=$(cat ${MBSYSCTL/nr_hugepages/free_hugepages})
#         fi
        
#         if [ $monitor_1gb -eq 1 ]; then
#             gb_alloc=$(cat $GBSYSCTL)
#             gb_free=$(cat ${GBSYSCTL/nr_hugepages/free_hugepages})
#         fi
        
#         echo "$ts,$mb_alloc,$mb_free,$gb_alloc,$gb_free" >> "$log_file"
#         sleep 5
#     done
# }

# # Add these functions to your script
# start_hhugepage_monitor() {
#     local log_file="$RUNDIR/hhugepages_ts.log"
#     echo "timestamp,allocated_2mb,free_2mb,allocated_1gb,free_1gb" > "$log_file"
    
#     # Determine which hugepages to monitor based on config
#     local monitor_2mb=0
#     local monitor_1gb=0
    
#     [[ $CONFIG = *2MB* ]] && monitor_2mb=1
#     [[ $CONFIG = *1GB* ]] && monitor_1gb=1

#     while true; do
#         local ts=$(date +%s)
#         local mb_alloc=0
#         local mb_free=0
#         local gb_alloc=0 
#         local gb_free=0
        
#         if [ $monitor_2mb -eq 1 ]; then
#             mb_alloc=$(cat $MBSYSCTL)
#             mb_free=$(cat ${MBSYSCTL/nr_hugepages/free_hugepages})
#         fi
        
#         if [ $monitor_1gb -eq 1 ]; then
#             gb_alloc=$(cat $GBSYSCTL)
#             gb_free=$(cat ${GBSYSCTL/nr_hugepages/free_hugepages})
#         fi
        
#         echo "$ts,$mb_alloc,$mb_free,$gb_alloc,$gb_free" >> "$log_file"
#         sleep 5
#     done
# }

# plot_hugepages() {
#     local log_file="$RUNDIR/hugepages_ts.log"
#     local plot_script="$RUNDIR/plot_hugepages.gnuplot"
    
#     # Generate gnuplot script
#     cat <<EOF > "$plot_script"
# set terminal pngcairo enhanced font "arial,10" size 1200,600
# set output '$RUNDIR/hugepages_timeseries.png'
# set title "Hugepage Allocation Time Series (Config: $CONFIG)"
# set xlabel "Time (seconds since start)"
# set ylabel "Number of Pages"
# set grid

# set datafile separator comma
# set key outside right top

# plot "$log_file" using (\$1 - $start_ts):2 with lines title '2MB Allocated', \
#      "" using (\$1 - $start_ts):3 with lines title '2MB Free', \
#      "" using (\$1 - $start_ts):4 with lines title '1GB Allocated', \
#      "" using (\$1 - $start_ts):5 with lines title '1GB Free'
# EOF

#     # Execute plot if gnuplot is available
#     if command -v gnuplot &> /dev/null; then
#         gnuplot "$plot_script"
#     else
#         echo "Gnuplot not found. Install with: sudo apt install gnuplot"
#     fi
# }

get_1gb_page_counters() 
{
    local vmstat_file="/proc/vmstat"
    if [[ ! -f "$vmstat_file" ]]; then
        echo "ERROR: /proc/vmstat not found. Are you running as root?" >&2
        return 1
    fi

    # Initialize counters
    declare -g thhp_fault_alloc=0
    declare -g thhp_collapse_alloc=0
    declare -g thhp_zero_page_alloc=0

    # Use awk for efficient parsing
    while read -r key value; do
        case "$key" in
            thhp_fault_alloc)
                thhp_fault_alloc=$value
                ;;
            thhp_collapse_alloc)
                thhp_collapse_alloc=$value
                ;;
            thhp_zero_page_alloc)
                thhp_zero_page_alloc=$value
                ;;
        esac
    done < <(awk '/^thhp_(fault_alloc|collapse_alloc|zero_page_alloc)/ {print $1, $2}' "$vmstat_file")
}

# Add to your existing script
get_thhp_stats() {
    local vmstat_file="/proc/vmstat"
    if [[ ! -f "$vmstat_file" ]]; then
        echo "ERROR: /proc/vmstat not found." >&2
        return 1
    fi

    declare -g thhp_fault_alloc=0
    declare -g thhp_collapse_alloc=0
    declare -g thhp_zero_page_alloc=0

    # Extract THP stats using awk
    while read -r key value; do
        case "$key" in
            thhp_fault_alloc)
                thhp_fault_alloc=$value
                ;;
            thhp_collapse_alloc)
                thhp_collapse_alloc=$value
                ;;
            thhp_zero_page_alloc)
                thhp_zero_page_alloc=$value
                ;;
        esac
    done < <(awk '/^thhp_(fault_alloc|collapse_alloc|zero_page_alloc)/ {print $1, $2}' "$vmstat_file")
}

monitor_thhp() {
    local log_file="$RUNDIR/thhp_ts.log"
    echo "timestamp,thhp_fault_alloc,thhp_collapse_alloc,thhp_zero_page_alloc" > "$log_file"

    while true; do
        get_thhp_stats
        echo "$(date +%s),$thhp_fault_alloc,$thhp_collapse_alloc,$thhp_zero_page_alloc" >> "$log_file"
        sleep 5
    done
}

# Add to your existing script
get_thp_stats() {
    local vmstat_file="/proc/vmstat"
    if [[ ! -f "$vmstat_file" ]]; then
        echo "ERROR: /proc/vmstat not found." >&2
        return 1
    fi

    declare -g thp_fault_alloc=0
    declare -g thp_collapse_alloc=0
    declare -g thp_split=0
    declare -g thp_zero_page_alloc=0

    # Extract THP stats using awk
    while read -r key value; do
        case "$key" in
            thp_fault_alloc)
                thp_fault_alloc=$value
                ;;
            thp_collapse_alloc)
                thp_collapse_alloc=$value
                ;;
            thp_split)
                thp_split=$value
                ;;
            thp_zero_page_alloc)
                thp_zero_page_alloc=$value
                ;;
        esac
    done < <(awk '/^thp_(fault_alloc|collapse_alloc|split|zero_page_alloc)/ {print $1, $2}' "$vmstat_file")
}

monitor_thp() {
    local log_file="$RUNDIR/thp_ts.log"
    echo "timestamp,thp_fault_alloc,thp_collapse_alloc,thp_split,thp_zero_page_alloc" > "$log_file"

    while true; do
        get_thp_stats
        echo "$(date +%s),$thp_fault_alloc,$thp_collapse_alloc,$thp_split,$thp_zero_page_alloc" >> "$log_file"
        sleep 5
    done
}

plot_thp() {
    local log_file="$RUNDIR/thp_ts.log"
    local plot_script="$RUNDIR/plot_thp.gnuplot"

    cat <<EOF > "$plot_script"
set terminal pngcairo enhanced font "arial,10" size 1200,600
set output '$RUNDIR/thp_timeseries.png'
set title "THP Metrics (Config: $CONFIG)"
set xlabel "Time (seconds since start)"
set ylabel "Count"
set grid
set datafile separator comma
set key outside right top

plot "$log_file" using (\$1 - $start_ts):2 with lines title 'Fault Alloc', \
     "" using (\$1 - $start_ts):3 with lines title 'Collapse Alloc', \
     "" using (\$1 - $start_ts):4 with lines title 'Splits', \
     "" using (\$1 - $start_ts):5 with lines title 'Zero Page Alloc'
EOF

    if command -v gnuplot &> /dev/null; then
        gnuplot "$plot_script"
    else
        echo "Install gnuplot: sudo apt install gnuplot"
    fi
}

# Add these functions to common.sh
start_memory_monitor() {
    local output_dir="$1"
    local log_file="$output_dir/memory_usage.csv"
    
    # Create header if file doesn't exist
    [ ! -f "$log_file" ] && echo "timestamp,total_mb,free_mb,available_mb,buffers_mb,cached_mb,sreclaimable_mb,shmem_mb,used_mb" > "$log_file"
    
    while true; do
        # Get memory metrics as integers (matches Python's //1024)
        local total=$(grep -w 'MemTotal' /proc/meminfo | awk '{print int($2/1024)}')
        local free=$(grep -w 'MemFree' /proc/meminfo | awk '{print int($2/1024)}')
        local available=$(grep -w 'MemAvailable' /proc/meminfo | awk '{print int($2/1024)}')
        local buffers=$(grep -w 'Buffers' /proc/meminfo | awk '{print int($2/1024)}')
        local cached=$(grep -w 'Cached' /proc/meminfo | awk '{print int($2/1024)}')
        local sreclaimable=$(grep -w 'SReclaimable' /proc/meminfo | awk '{print int($2/1024)}')
        local shmem=$(grep -w 'Shmem' /proc/meminfo | awk '{print int($2/1024)}')
        
        # Calculate used memory exactly like Python version
        local used=$(( total - free - buffers - cached - sreclaimable + shmem ))
        
        # Append to CSV with integer values
        printf "%s,%d,%d,%d,%d,%d,%d,%d,%d\n" \
            $(date +%s) "$total" "$free" "$available" "$buffers" "$cached" "$sreclaimable" "$shmem" "$used" >> "$log_file"
        
        sleep 5
    done
}


launch_workload()
{
        # --- clean up exisiting state/processes
        rm /tmp/alloctest-bench.ready &>$COUT
        rm /tmp/alloctest-bench.done &> $COUT
	echo -1 | sudo tee /proc/sys/kernel/perf_event_paranoid > $COUT
        
        #new way
        CMD_PREFIX=$NUMACTL
        if [[ $CONFIG = *HUGE* ]]; then
        CMD_PREFIX="hugectl --heap $NUMACTL"
        fi
        CMD_PREFIX+=" -C $CPU_NODE --membind $DATA_NODE"

        # Build the perf command with all events and output file
        PERF_CMD="perf stat -x, -o $OUTFILE -e $PERF_EVENTS --"
        INTERNAL_PERF_CMD="perf stat -p %d -B -v -o $OUTFILE -e instructions:u -e cycles:u -e L1-dcache-loads:u -e L1-dcache-load-misses:u -e L1-dcache-stores:u -e LLC-loads:u -e LLC-load-misses:u -e LLC-stores:u -e LLC-store-misses:u -e dTLB-loads:u -e dTLB-stores:u -e page-faults:u -e dtlb_load_misses.stlb_hit:u -e dtlb_load_misses.miss_causes_a_walk:u -e dtlb_load_misses.walk_completed:u -e dtlb_load_misses.walk_completed_1g:u -e dtlb_load_misses.walk_completed_2m_4m:u -e dtlb_load_misses.walk_completed_4k:u -e dtlb_store_misses.stlb_hit:u -e dtlb_store_misses.miss_causes_a_walk:u -e dtlb_store_misses.walk_completed:u -e dtlb_store_misses.walk_completed_1g:u -e dtlb_store_misses.walk_completed_2m_4m:u -e dtlb_store_misses.walk_completed_4k:u -e dtlb_load_misses.walk_duration:u -e dtlb_store_misses.walk_duration:u -e dtlb_load_misses.stlb_hit_4k:u -e dtlb_load_misses.stlb_hit_2m:u -e dtlb_store_misses.stlb_hit_4k:u -e dtlb_store_misses.stlb_hit_2m:u -e page_walker_loads.dtlb_l1:u -e page_walker_loads.dtlb_l2:u -e page_walker_loads.dtlb_l3:u -e page_walker_loads.dtlb_memory:u"

        # Construct the full launch command
        LAUNCH_CMD="$CMD_PREFIX $BENCHPATH $BENCH_ARGS"
        REDIRECT=$LOGFILE

        echo $LAUNCH_CMD "$INTERNAL_PERF_CMD"
        touch $OUTFILE
        cat /proc/vmstat | egrep 'migrate|th' >> $RUNDIR/vmstat
        sleep 1

        # 1GB counters Before launching the application
        if [ $CONFIG = "TRIDENT" ]; then
                monitor_thhp &
                THHP_MONITOR_PID=$!
                sstart_ts=$(date +%s)
        fi

        # start_hugepage_monitor &
        # MONITOR_PID=$!
        # start_ts=$(date +%s)

        # Start THP monitoring
        monitor_thp &
        THP_MONITOR_PID=$!
        start_ts=$(date +%s)

        # Start memory monitoring
        start_memory_monitor "$RUNDIR" &
        MEM_MONITOR_PID=$!

        # Run the command with output redirection
        $LAUNCH_CMD "$INTERNAL_PERF_CMD" > $REDIRECT 2>&1 &
        BENCHMARK_PID=$!


        #old way
        # CMD_PREFIX=$NUMACTL
        # if [[ $CONFIG = *HUGE* ]]; then
        #         #CMD_PREFIX=" LD_PRELOAD=libhugetlbfs.so HUGETLB_MORECORE=2M $NUMACTL"
        #         CMD_PREFIX=" hugectl --heap $NUMACTL"
        # fi
        # CMD_PREFIX+=" -C $CPU_NODE --membind $DATA_NODE"
        # LAUNCH_CMD="$CMD_PREFIX $BENCHPATH $BENCH_ARGS"
        # REDIRECT=$LOGFILE
        # echo $LAUNCH_CMD
        # touch $OUTFILE
        # cat /proc/vmstat | egrep 'migrate|th' >> $RUNDIR/vmstat
        # sleep 1
        # $LAUNCH_CMD > $REDIRECT 2>&1 &
        # #start perf from the beginning
        # BENCHMARK_PID=$!
        # if [ $PROFILE_PERF_EVENTS = "yes" ]; then
	# 	$PERF stat -x, -o $OUTFILE --append -e $PERF_EVENTS -p $BENCHMARK_PID &
	# 	PERF_PID=$!
	# fi
        #$LAUNCH_CMD &
        # BENCHMARK_PID=$!
        if [ $CONFIG = "HAWKEYE" ]; then
                sleep 1
                $ROOT/bin/notify_hawkeye -p $BENCHMARK_PID > $COUT 2>&1
                echo "Added PID: $BENCHMARK_PID to HawkEye Scan List..."        
        fi
        SECONDS=0
        echo -e "\e[0mWaiting for benchmark: $BENCHMARK_PID to be ready"
        while [ ! -f /tmp/alloctest-bench.ready ]; do
                sleep 0.1
        done
        INIT_DURATION=$SECONDS
        if [ $CONFIG = "2MBR" ] || [ $CONFIG = "1GBTR" ]; then
                echo "Launching Interference on NODE: 0 ..."
                $ROOT/bin/numactl -c 0 -m 0 $INTERFERENCEPATH > $COUT 2>&1 &
        fi
        echo -e "Initialization Time (seconds): $INIT_DURATION"
        SECONDS=0
	# if [ $PROFILE_PERF_EVENTS = "yes" ]; then
	# 	$PERF stat -x, -o $OUTFILE --append -e $PERF_EVENTS -p $BENCHMARK_PID &
	# 	PERF_PID=$!
	# fi
        echo -e "\e[0mWaiting for benchmark to be done"
        while [ ! -f /tmp/alloctest-bench.done ]; do
                sleep 0.1
        done
        DURATION=$SECONDS
        echo "****success****" >> $OUTFILE
        echo -e "Execution Time (seconds): $DURATION" >> $OUTFILE
        echo -e "Execution Time (seconds): $DURATION"
        echo -e "Initialization Time (seconds): $INIT_DURATION\n" >> $OUTFILE
	# if [ $PROFILE_PERF_EVENTS = "yes" ]; then
	# 	kill -INT $PERF_PID &> $COUT
	# 	wait $PERF_PID
	# fi
        cat /proc/vmstat | egrep 'migrate|th' >> $RUNDIR/vmstat

        if [ $CONFIG = "TRIDENT" ]; then
                kill $THHP_MONITOR_PID
                wait $THHP_MONITOR_PID 2>/dev/null
        fi
                # # 1GB counters After application finishes
                # get_1gb_page_counters
                # allocated_1gb=$(( 
                # thhp_fault_alloc - initial_fault +
                # thhp_collapse_alloc - initial_collapse +
                # thhp_zero_page_alloc - initial_zero
                # ))

                # # Calculate differences
                # fault_diff=$((thhp_fault_alloc - initial_fault))
                # collapse_diff=$((thhp_collapse_alloc - initial_collapse))
                # zero_diff=$((thhp_zero_page_alloc - initial_zero))

                # # Write to output file
                # mkdir -p "$ROOT/report"
                # gb_output_file="$ROOT/report/${BENCHMARK}_1gb_stats.txt"
                # echo "Total 1GB pages allocated: $allocated_1gb" > "$gb_output_file"
                # echo "Breakdown:" >> "$gb_output_file"
                # echo " - Fault allocations: $fault_diff" >> "$gb_output_file"
                # echo " - Collapse allocations: $collapse_diff" >> "$gb_output_file"
                # echo " - Zero page allocations: $zero_diff" >> "$gb_output_file"
        # fi
        wait $BENCHMARK_PID 2>$COUT
        # kill $MONITOR_PID  # Stop monitoring
        # wait $MONITOR_PID 2>/dev/null

        # # Generate plot
        # plot_hugepages

        # Stop monitoring after workload completes
        kill $MEM_MONITOR_PID
        wait $MEM_MONITOR_PID 2>/dev/null

        kill $THP_MONITOR_PID
        wait $THP_MONITOR_PID 2>/dev/null

        # Generate plot
        #plot_thp
}

reserve_kvm_hugetlb_pages()
{
	cleanup_system_configs
	if [[ $CONFIG = *2MBHUGE* ]]; then
		echo $VM_HUGETLB_2MB_PAGES | sudo tee $MBSYSCTL > $COUT 2>&1
	elif [[ $CONFIG = *1GBHUGE* ]]; then
		echo $VM_HUGETLB_1GB_PAGES | sudo tee $GBSYSCTL > $COUT 2>&1
	fi
}

copy_vm_config()
{
	VMXML=$ROOT/vmconfigs/4KB.xml # -- same XML works for 2MBTHP and HAWKEYE as well
	if [[ $CONFIG = *2MBHUGE* ]]; then
		VMXML=$ROOT/vmconfigs/2MBHUGE.xml
	elif [[ $CONFIG = *1GBHUGE* ]]; then
		VMXML=$ROOT/vmconfigs/1GBHUGE.xml
	elif [[ $CONFIG = *HAWKEYE* ]]; then
		VMXML=$ROOT/vmconfigs/HAWKEYE.xml
	fi
	sudo service libvirtd stop
	sudo cp $VMXML /etc/libvirt/qemu/$VMIMAGE.xml
	sudo service libvirtd start
	echo "VM configuration updated..."
}

shutdown_kvm_vm()
{
	echo "Shutting down VM..."
	ssh $GUESTUSER@$GUESTIP 'sudo shutdown now' > $COUT
	sleep 10
	virsh destroy $VMIMAGE > $COUT 2>&1
	sleep 1
	echo "VM stopped..."
}

boot_kvm_vm()
{
	virsh start $VMIMAGE > $COUT
	if [ $? -ne 0 ]; then
		echo "error starting vm. Exiting."
		exit
	fi
	echo "VM started....waiting 150 seconds to log in"
	sleep 150
}

prepare_kvm_vm()
{
	shutdown_kvm_vm
	copy_vm_config
	reserve_kvm_hugetlb_pages
	boot_kvm_vm
}
