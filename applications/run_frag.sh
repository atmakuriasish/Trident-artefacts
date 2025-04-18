#!/bin/bash

footprints=(8634 8634 16123 16123 16611 16611 16984 16984 31863 31863 32776 32776 8952 8952 16987 16987 18407 18407) # MB
datasets=(Kronecker_25 DBG_Kronecker_25 Twitter DBG_Twitter Sd1_Arc DBG_Sd1_Arc)

#footprints=(520)
#datasets=(Kronecker_21)

offset=3072

NUMA_NODE=0 # EDIT THIS VALUE (NUMA NODE)
MAX_RAM=128856 # EDIT THIS VALUE (AMOUNT OF MEMORY ON NUMA NODE)

for i in ${!footprints[@]}
do
	footprint=${footprints[$i]}
	size=$(( footprint + offset ))

	cmd="numactl --membind $NUMA_NODE ../numactl/memhog $(( MAX_RAM - size ))M"
	echo $cmd
	screen -dm -S memhog $cmd
	pid=$(screen -ls | awk '/\.memhog\t/ {print strtonum($1)}')
	echo "sleeping..."
	sleep 30

	num_datasets=${#datasets[@]}
	if (( $i < $num_datasets )) ; then
		app=bfs
	elif (( $i < 2 * $num_datasets )) ; then
		app=sssp
	else
		app=pagerank
	fi

	d=$(( i % num_datasets ))
	dataset=${datasets[$d]}

	for t in {0..1}
	do
		cmd="sudo bash frag.sh $dataset $app $NUMA_NODE $t"
		echo $cmd
		$cmd
	done

	kill $pid
	echo ""
done
