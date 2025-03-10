#!/bin.bash

VMIMAGE=trident

GUESTUSER=micro21ae
GUESTIP=192.168.123.149

PERF_EVENTS='cycles,dTLB-loads,dTLB-stores,dtlb_load_misses.stlb_hit,dtlb_load_misses.miss_causes_a_walk,dtlb_load_misses.walk_duration,dtlb_load_misses.walk_completed,dtlb_load_misses.walk_completed_4k,dtlb_load_misses.walk_completed_2m_4m,dtlb_load_misses.walk_completed_1g,dtlb_store_misses.stlb_hit,dtlb_store_misses.miss_causes_a_walk,dtlb_store_misses.walk_duration,dtlb_store_misses.walk_completed,dtlb_store_misses.walk_completed_4k,dtlb_store_misses.walk_completed_2m_4m,dtlb_store_misses.walk_completed_1g,page_walker_loads.dtlb_l1,page_walker_loads.dtlb_l2,page_walker_loads.dtlb_l3,page_walker_loads.dtlb_memory,page-faults,dtlb_load_misses.stlb_hit_4k,dtlb_load_misses.stlb_hit_2m,dtlb_store_misses.stlb_hit_4k,dtlb_store_misses.stlb_hit_2m'


# PERF_EVENTS='cycles,dtlb_load_misses.walk_duration,dtlb_store_misses.walk_duration'
#PERF_EVENTS='cycles,dtlb_load_misses.walk_active,dtlb_store_misses.walk_active'
#PERF_EVENTS='cycles,instructions'

PROFILE_PERF_EVENTS="yes" #no

FRAG_FILE_1=$ROOT/datasets/fragmentation/file-1
FRAG_FILE_2=$ROOT/datasets/fragmentation/file-2

# number of hugetlb pages
HUGETLB_2MB_PAGES=70000
HUGETLB_1GB_PAGES=140

# number of hugetlb pages
VM_HUGETLB_2MB_PAGES=80000
VM_HUGETLB_1GB_PAGES=160
