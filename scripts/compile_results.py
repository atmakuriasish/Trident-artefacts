#!/usr/bin/python3

import sys
import os
import csv
import shutil

benchmarks = dict()
curr_bench = ""
curr_config = ""
summary = []
avg_summary = []
benchmarks = []

# --- all workload configurations
configs = ['4KB', '2MBTHP', '2MBHUGE', '1GBHUGE', 'TRIDENT', 'TRIDENT-1G', \
          'TRIDENT-NC', 'HAWKEYE', '2MBTHP-F', 'TRIDENT-F', 'TRIDENT-1G-F', \
          'TRIDENT-NC-F', 'HAWKEYE-F', '4KB-4KB', '2MBTHP-2MBTHP', '1GBHUGE-1GBHUGE', \
          'TRIDENT-TRIDENT', 'HAWKEYE-HAWKEYE', '2MBTHP-2MBTHP-F', 'TRIDENT-TRIDENT-F', \
          'TRIDENTPV-TRIDENTPV-F']
pretty_configs = ['4KB', '2MB-THP', '2MB-HUGE', '1GB-HUGE', 'Trident', 'Trident-1G', \
          'Trident-NC', 'HawkEye', '2MB-THP', 'Trident', 'Trident-1G', 'Trident-NC', \
          'HawkEye', '4KB+4KB', '2MB+2MB', '1GB+1GB', 'Trident+Trident', 'HawkEye+HawkEye', \
          '2MB+2MB', 'Trident+Trident', 'TridentPV+TridentPV']

# --- all workloads
# workloads = ['xsbench', 'gups', 'svm', 'redis', 'btree', 'graph500', 'memcached', \
#           'canneal', 'pr', 'cc', 'bc', 'cg', 'bfs', 'sssp'] #Asish: added bfs and sssp
# --- workloads used in final evaluation
# main_workloads = ['xsbench', 'gups', 'svm', 'redis', 'btree', 'graph500', \
#           'memcached', 'canneal']
workloads = ['pgr','bfs', 'sssp']
main_workloads = ['pgr', 'bfs', 'sssp']

fig1_configs = ['4KB', '2MBTHP', '2MBHUGE', '1GBHUGE']
fig2_configs = ['4KB-4KB', '2MBTHP-2MBTHP', '1GBHUGE-1GBHUGE']
fig7_configs = ['TRIDENT-F', 'TRIDENT-NC-F']
fig9_configs = ['2MBTHP', 'TRIDENT', 'HAWKEYE']
# fig9_configs = ['2MBTHP', 'HAWKEYE', 'TRIDENT']
fig10_configs = fig9_configs
fig11a_configs = ['2MBTHP', 'TRIDENT-1G', 'TRIDENT-NC', 'TRIDENT'] 
fig11b_configs = ['2MBTHP-F', 'TRIDENT-1G-F', 'TRIDENT-NC-F', 'TRIDENT-F']
fig12_configs = ['2MBTHP-2MBTHP', 'HAWKEYE-HAWKEYE', 'TRIDENT-TRIDENT']
fig13_configs = ['2MBTHP-2MBTHP-F', 'TRIDENT-TRIDENT-F', 'TRIDENTPV-TRIDENTPV-F']

def get_time_from_log(line):
    exec_time = int(line[line.find(":")+2:])
    return exec_time

def open_file(src, op):
    try:
        fd = open(src, op)
        if fd is None:
            raise ("Failed")
        return fd
    except:
        return None

def update_workload_config(log):
    global curr_bench, curr_config

    for bench in workloads:
        if bench in log:
            curr_bench = bench
            break

    config = ''
    for tmp in configs:
        search_name = '--' + tmp + '--'
        if search_name in log:
            config = tmp
            break

    curr_config = config
    benchmarks.append(curr_bench)

def record_output(time, pwc, copy):
    if time == -1:
        return

    output = {}
    output['bench'] = curr_bench
    output['config'] = curr_config
    output['time'] = time
    output['pwc'] = pwc
    output['copy'] = copy
    #print(output)
    summary.append(output)

def process_perf_log(path):
    fd = open_file(path, "r")
    if fd is None:
        return

    if 'vmstat' in path:
        copy0 = copy1 = -1
        for line in fd:
            if 'pgmigrate_success' in line:
                if copy0 == -1:
                    copy0 = int(line.split()[1])
                else:
                    copy1 = int(line.split()[1])
        fd.close()
        return (copy1 - copy0)

    exec_time = cycles = loads = stores = -1
    for line in fd:
        if 'Execution Time (seconds)' in line:
            exec_time = get_time_from_log(line)
        if ',cycles' in line:
            cycles = float(line.split(',')[0])
        if ',dtlb_load_misses.walk_duration' in line:
            loads = float(line.split(',')[0])
        if ',dtlb_store_misses.walk_duration' in line:
            stores = float(line.split(',')[0])
        # if ',dtlb_load_misses.walk_active' in line:
        #     loads = float(line.split(',')[0])
        # if ',dtlb_store_misses.walk_active' in line:
        #     stores = float(line.split(',')[0])
    fd.close()

    pwc = round((((loads + stores) * 100)/cycles), 2)
    if exec_time == -1 or curr_config == '':
        return (-1, -1)

    return (exec_time, pwc)
    #record_output(exec_time, pwc, 0)
    #output = {}
    #output['bench'] = curr_bench
    #output['config'] = curr_config
    #output['time'] = exec_time
    #output['pwc'] = round((((loads + stores) * 100)/cycles), 2)
    #print(output)
    #summary.append(output)

def process_perf_log_new(path, measurements):
    fd = open_file(path, "r")
    if fd is None:
        return

    if 'vmstat' in path:
        # Existing vmstat handling
        copy0 = copy1 = -1
        for line in fd:
            if 'pgmigrate_success' in line:
                if copy0 == -1:
                    copy0 = int(line.split()[1])
                else:
                    copy1 = int(line.split()[1])
        fd.close()
        return (copy1 - copy0)
    else:
        # Initialize all metrics
        metric_vals = {
            "dTLBloads": 0,
            "dTLBstores": 0,
            "dtlb_load_misses.stlb_hit": 0,
            "dtlb_load_misses.miss_causes_a_walk": 0,
            "dtlb_load_misses.walk_duration": 0,
            "dtlb_load_misses.walk_completed": 0,
            "dtlb_load_misses.walk_completed_4k": 0,
            "dtlb_load_misses.walk_completed_2m_4m": 0,
            "dtlb_load_misses.walk_completed_1g": 0,
            "dtlb_store_misses.stlb_hit": 0,
            "dtlb_store_misses.miss_causes_a_walk": 0,
            "dtlb_store_misses.walk_duration": 0,
            "dtlb_store_misses.walk_completed": 0,
            "dtlb_store_misses.walk_completed_4k": 0,
            "dtlb_store_misses.walk_completed_2m_4m": 0,
            "dtlb_store_misses.walk_completed_1g": 0,
            "pagefaults": 0,
            "cycles": 0,
            "dtlb_load_misses.stlb_hit_4k": 0,
            "dtlb_load_misses.stlb_hit_2m": 0,
            "dtlb_store_misses.stlb_hit_4k": 0,
            "dtlb_store_misses.stlb_hit_2m": 0,
            "page_walker_loads.dtlb_l1": 0,
            "page_walker_loads.dtlb_l2": 0,
            "page_walker_loads.dtlb_l3": 0,
            "page_walker_loads.dtlb_memory": 0,
            "exec_time": 0
        }

        # Parse log file
        for line in fd:
            # Handle execution time separately
            if 'Execution Time (seconds)' in line:
                metric_vals["exec_time"] = get_time_from_log(line)
                continue
                    
            # Skip header lines
            if line.startswith('#'):
                continue

            # Split and parse perf counters
            parts = line.strip().split(',')
            if len(parts) < 3:  # Ensure we have at least 3 parts
                continue

            # Extract event name and value
            event_name = parts[2].strip()
            value = float(parts[0])
            
            # Map to our metric names
            if event_name in metric_vals:
                metric_vals[event_name] = value
            elif event_name == 'page-faults':
                metric_vals["pagefaults"] = value
            elif event_name == 'dTLB-loads':
                metric_vals["dTLBloads"] = value
            elif event_name == 'dTLB-stores':
                metric_vals["dTLBstores"] = value
            elif event_name == 'L1-dcache-load-misses':
                metric_vals["L1dcacheloadmisses"] = value
            elif event_name == 'L1-dcache-loads':
                metric_vals["L1dcacheloads"] = value
            elif event_name == 'L1-dcache-stores':
                metric_vals["L1dcachestores"] = value
            elif event_name == 'LLC-load-misses':
                metric_vals["LLCloadmisses"] = value
            elif event_name == 'LLC-loads':
                metric_vals["LLCloads"] = value
            elif event_name == 'LLC-store-misses':
                metric_vals["LLCstoremisses"] = value
            elif event_name == 'LLC-stores':
                metric_vals["LLCstores"] = value

        fd.close()
        cycles = metric_vals["cycles"]

        #cache events
        l1_ld_misses = metric_vals["L1dcacheloadmisses"]
        l1_lds = metric_vals["L1dcacheloads"]
        l1_st_misses = 0 #metric_vals["L1dcachestoremisses"]
        l1_sts = metric_vals["L1dcachestores"]
        l1_misses = l1_ld_misses + l1_st_misses
        l1_refs = l1_lds + l1_sts

        llc_ld_misses = metric_vals["LLCloadmisses"]
        llc_lds = metric_vals["LLCloads"]
        llc_st_misses = metric_vals["LLCstoremisses"]
        llc_sts = metric_vals["LLCstores"]
        llc_misses = llc_ld_misses + llc_st_misses
        llc_refs = llc_lds + llc_sts

        measurements.write("CACHE:\n")
        measurements.write("L1 Miss Rate: " + str(l1_misses*100.0/l1_refs) + "\n")
        measurements.write("LLC Miss Rate: " + str(llc_misses*100.0/llc_refs) + "\n")
        measurements.write("L3 Miss: " + str(llc_misses*100.0/l1_refs) + "\n")

        measurements.write("\n")

        #tlb_ld_misses = metric_vals["dTLBloadmisses"]
        tlb_lds = metric_vals["dTLBloads"]
        #tlb_st_misses = metric_vals["dTLBstoremisses"]
        if metric_vals["dTLBstores"] > 0:
            tlb_sts = metric_vals["dTLBstores"]
        else:
            tlb_sts = 0
        tlb_refs = tlb_lds + tlb_sts
        tlb_ld_stlb = metric_vals["dtlb_load_misses.stlb_hit"]
        tlb_ld_walks = metric_vals["dtlb_load_misses.miss_causes_a_walk"]
        tlb_ld_walk_cycles = metric_vals["dtlb_load_misses.walk_duration"]
        tlb_ld_walk_completed = metric_vals["dtlb_load_misses.walk_completed"]
        tlb_ld_walk_completed_4k = metric_vals["dtlb_load_misses.walk_completed_4k"]
        tlb_ld_walk_completed_2m = metric_vals["dtlb_load_misses.walk_completed_2m_4m"]
        tlb_ld_walk_completed_1g = metric_vals["dtlb_load_misses.walk_completed_1g"]
        tlb_st_stlb = metric_vals["dtlb_store_misses.stlb_hit"]
        tlb_st_walks = metric_vals["dtlb_store_misses.miss_causes_a_walk"]
        tlb_st_walk_cycles = metric_vals["dtlb_store_misses.walk_duration"]
        tlb_st_walk_completed = metric_vals["dtlb_store_misses.walk_completed"]
        tlb_st_walk_completed_4k = metric_vals["dtlb_store_misses.walk_completed_4k"]
        tlb_st_walk_completed_2m = metric_vals["dtlb_store_misses.walk_completed_2m_4m"]
        tlb_st_walk_completed_1g = metric_vals["dtlb_store_misses.walk_completed_1g"]
        page_faults = metric_vals["pagefaults"]
        tlb_stlb = tlb_ld_stlb + tlb_st_stlb
        tlb_walks = tlb_ld_walks + tlb_st_walks
        tlb_misses = tlb_stlb + tlb_walks
        tlb_walk_cycles = tlb_ld_walk_cycles + tlb_st_walk_cycles
        tlb_walk_completed = tlb_ld_walk_completed + tlb_st_walk_completed
        tlb_walk_completed_4k = tlb_ld_walk_completed_4k + tlb_st_walk_completed_4k
        tlb_walk_completed_2m = tlb_ld_walk_completed_2m + tlb_st_walk_completed_2m
        tlb_walk_completed_1g = tlb_ld_walk_completed_1g + tlb_st_walk_completed_1g
        tlb_walk_completed_tot = tlb_walk_completed_4k + tlb_walk_completed_2m + tlb_walk_completed_1g
        tlb_miss_rate = tlb_misses*100.0/tlb_refs if (tlb_refs > 0) else 0

        tlb_ld_stlb_4k = metric_vals["dtlb_load_misses.stlb_hit_4k"]
        tlb_ld_stlb_2m = metric_vals["dtlb_load_misses.stlb_hit_2m"]
        tlb_st_stlb_4k = metric_vals["dtlb_store_misses.stlb_hit_4k"]
        tlb_st_stlb_2m = metric_vals["dtlb_store_misses.stlb_hit_2m"]
        tlb_stlb_4k = tlb_ld_stlb_4k + tlb_st_stlb_4k
        tlb_stlb_2m = tlb_ld_stlb_2m + tlb_st_stlb_2m
        walker_loads_l1 = metric_vals["page_walker_loads.dtlb_l1"]
        walker_loads_l2 = metric_vals["page_walker_loads.dtlb_l2"]
        walker_loads_l3 = metric_vals["page_walker_loads.dtlb_l3"]
        walker_loads_mem = metric_vals["page_walker_loads.dtlb_memory"]
        measurements.write("4KB STLB Hit: " + str(tlb_stlb_4k*100.0/tlb_stlb) + "\n")
        measurements.write("2MB STLB Hit: " + str(tlb_stlb_2m*100.0/tlb_stlb) + "\n")
        measurements.write("Page Walker L1 Loads: " + str(walker_loads_l1*100.0/tlb_walks) + "\n")
        measurements.write("Page Walker L2 Loads: " + str(walker_loads_l2*100.0/tlb_walks) + "\n")
        measurements.write("Page Walker L3 Loads: " + str(walker_loads_l3*100.0/tlb_walks) + "\n")
        measurements.write("Page Walker Mem Loads: " + str(walker_loads_mem*100.0/tlb_walks) + "\n")
        measurements.write("\n")

        measurements.write("TLB:\n")
        measurements.write("TLB Miss Rate: " + str(tlb_miss_rate) + "\n")
        if (tlb_walks > 0):
            measurements.write("STLB Miss Rate: " + str(tlb_walks*100.0/(tlb_walks+tlb_stlb)) + "\n")
            measurements.write("Page Fault Rate: " + str(page_faults*100.0/tlb_walks) + "\n")
        if (tlb_refs > 0):
            measurements.write("Percent of TLB Accesses with PT Walks: " + str(tlb_walks*100.0/tlb_refs) + "\n")
            measurements.write("Percent of TLB Accesses with Completed PT Walks: " + str(tlb_walk_completed*100.0/tlb_refs) + "\n")
            measurements.write("Percent of TLB Accesses with Page Faults: " + str(page_faults*100.0/tlb_refs) + "\n")
        measurements.write("Percent of Cycles Spent on PT Walks: " + str(tlb_walk_cycles*100.0/cycles) + "\n")
        measurements.write("Average Cycles Spent on PT Walk: " + str(tlb_walk_cycles*100.0/tlb_walk_completed) + "\n")
        if (tlb_walk_completed_tot > 0):
            measurements.write("4KB Page Table Walks: " + str(tlb_walk_completed_4k*100.0/tlb_walk_completed_tot) + "\n")
            measurements.write("2MB/4MB Page Table Walks: " + str(tlb_walk_completed_2m*100.0/tlb_walk_completed_tot) + "\n")
            measurements.write("1GB Page Table Walks: " + str(tlb_walk_completed_1g*100.0/tlb_walk_completed_tot) + "\n")
        measurements.write("\n")
    measurements.close()


 
def traverse_benchmark(path):
    # --- process THP and NON-THP configs separately
    for root,dir,files in os.walk(path):
        time = pwc = copy = -1
        for filename in files:
            log = os.path.join(root, filename)
            update_workload_config(log)
            if 'vmstat' in log:
                copy = process_perf_log(log)
            else:
                (time, pwc) = process_perf_log(log)
                if 'perflog' in log:
                    output_file = os.path.join(out_dir, f"{curr_bench}_{curr_config}_measurements.txt")
                    with open(output_file, 'w') as measurements:
                        process_perf_log_new(log, measurements)

            record_output(time, pwc, copy)

def pretty(name):
    if name in configs:
        index = configs.index(name)
        return pretty_configs[index]
    return name

def dump_workload_config_average(output, bench, config, fd, fd2, absolute):
    time = count = pwc = copy = 0
    for result in output:
        if result['bench'] == bench and result['config'] == config:
            time += result['time']
            pwc += result['pwc']
            copy += int(result['copy'])
            line = '%s\t%s\t%d\t%0.2f\t%d\n' % (bench, pretty(config), result['time'], result['pwc'], result['pwc'])
            fd2.write(line)
            count += 1

    if count == 0:
        return

    if absolute:
            time = int (time / count)
            pwc = float (pwc / count)
            copy = int (copy / count)
            line = '%s\t%s\t%d\t%0.2f\t%d\n' % (bench, pretty(config), time, pwc, copy)
            fd.write(line)
            output = {}
            output['bench'] = bench
            output['config'] = config
            output['time'] = time
            output['pwc'] = pwc
            output['copy'] = copy
            avg_summary.append(output)

def process_all_runs(fd, fd2, output, absolute):
    global benchmarks, configs, curr_bench
    benchmarks = list(dict.fromkeys(benchmarks))

    if absolute:
        fd.write('Workload\tConfiguration\tTime\tPWC\n')
        fd2.write('Workload\tConfiguration\tTime\tPWC\n')
    else:
        fd.write('Workload\tConfiguration\tTime\n')
    for bench in workloads:
        curr_bench = bench
        for config in configs:
            dump_workload_config_average(output, bench, config, fd, fd2, absolute)
    #Asish: added prints for debugging
    #print(summary)
    #print(avg_summary)

def gen_csv_common(dst, benchs, confs, baseline, metric):
    out_fd = open(dst, mode = 'w')
    writer = csv.writer(out_fd, delimiter='\t', quoting=csv.QUOTE_MINIMAL)
    denominator = 1000000.0

    for workload in benchs:
        for exp in avg_summary:
            if exp['bench'] == workload and exp['config'] == baseline:
                denominator = exp[metric]

        for config in confs:
            for exp in avg_summary:
                if exp['bench'] == workload and exp['config'] == config:
                    if denominator == 0:
                        val = 'XXX'
                    else:
                        if metric == 'time':
                            val = round(1 / (exp[metric] / denominator), 2)
                        else:
                            val = round(exp[metric] / denominator, 2)
                    writer.writerow([workload, pretty_configs[configs.index(config)], val])

def gen_fig1_csv(root):
    out_csv = os.path.join(root, 'report/figure-1a.csv')
    gen_csv_common(out_csv, workloads, fig1_configs, '4KB', 'pwc')
    out_csv = os.path.join(root, 'report/figure-1b.csv')
    gen_csv_common(out_csv, workloads, fig1_configs, '4KB', 'time')

def gen_fig2_csv(root):
    out_csv = os.path.join(root, 'report/figure-2a.csv')
    gen_csv_common(out_csv, workloads, fig2_configs, '4KB-4KB', 'pwc')
    out_csv = os.path.join(root, 'report/figure-2b.csv')
    gen_csv_common(out_csv, workloads, fig2_configs, '4KB-4KB', 'time')

def gen_fig9_csv(root):
    out_csv = os.path.join(root, 'report/figure-9a.csv')
    gen_csv_common(out_csv, main_workloads, fig9_configs, '2MBTHP', 'time')
    out_csv = os.path.join(root, 'report/figure-9b.csv')
    gen_csv_common(out_csv, main_workloads, fig9_configs, '2MBTHP', 'pwc')

def gen_fig10_csv(root):
    out_csv = os.path.join(root, 'report/figure-10a.csv')
    gen_csv_common(out_csv, main_workloads, fig10_configs, '2MBTHP-F', 'time')
    out_csv = os.path.join(root, 'report/figure-10b.csv')
    gen_csv_common(out_csv, main_workloads, fig10_configs, '2MBTHP-F', 'pwc')

def gen_fig11_csv(root):
    out_csv = os.path.join(root, 'report/figure-11a.csv')
    gen_csv_common(out_csv, main_workloads, fig11a_configs, '2MBTHP', 'time')
    out_csv = os.path.join(root, 'report/figure-11b.csv')
    gen_csv_common(out_csv, main_workloads, fig11b_configs, '2MBTHP-F', 'time')

def gen_fig12_csv(root):
    out_csv = os.path.join(root, 'report/figure-12.csv')
    gen_csv_common(out_csv, main_workloads, fig12_configs, '2MBTHP-2MBTHP', 'time')

def gen_fig7_csv(root):
    out_csv = os.path.join(root, 'report/figure-7.csv')
    gen_csv_common(out_csv, main_workloads, fig7_configs, 'TRIDENT-NC', 'copy')


def gen_report(root):
    gen_fig1_csv(root)
    # gen_fig2_csv(root)
    gen_fig9_csv(root)
    # gen_fig10_csv(root)
    # gen_fig11_csv(root)
    # gen_fig12_csv(root)
    # gen_fig7_csv(root)

if __name__=="__main__":
    global root, datadir, out_dir
    summary = []
    avg_summary = []
    root = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    datadir = os.path.join(root, "evaluation/")
    out_dir = os.path.join(root, "report/")
    if not os.path.exists(out_dir):
        os.makedirs(out_dir)

    for benchmark in workloads:
        path = os.path.join(datadir, benchmark)
        traverse_benchmark(path)

    avg_src = os.path.join(out_dir, "avg.csv")
    all_src = os.path.join(out_dir, "all.csv")


    #print(avg_src)
    #print(all_src)
    fd_avg = open_file(avg_src, "w")
    fd_all = open_file(all_src, "w")
    if fd_avg is None or fd_all is None:
        print("ERROR creating output files")
        sys.exit()

    # --- process normalized data
    process_all_runs(fd_avg, fd_all, summary, True)
    fd_avg.close()
    fd_all.close()

    gen_report(root)

