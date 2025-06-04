#!/bin/bash

#ALLOWED_PARTITIONS="gpu himem all"
ALLOWED_PARTITIONS="gpu"

# Get node => partition map
sinfo -N -h -o "%n %P" -t idle,mix,alloc | sort -u | while read -r node partitions; do
    # Split partition list
    IFS=',' read -ra part_list <<< "$partitions"

    # Find first matching allowed partition
    chosen_partition=""
    for p in "${part_list[@]}"; do
        for allowed in $ALLOWED_PARTITIONS; do
            if [[ "$p" == "$allowed" ]]; then
                chosen_partition="$p"
                break 2
            fi
        done
    done

    if [[ -n "$chosen_partition" ]]; then
        echo "Submitting job to node: $node on partition: $chosen_partition"
        sbatch --nodelist="$node" --partition="$chosen_partition" gpu-tester.sbatch
        #sbatch --nodelist="$node" --partition="$chosen_partition" per-node-job.sbatch
    else
        echo "Submitting job to node: $node (no partition specified)"
        sbatch --nodelist="$node" gpu-tester.sbatch
        #sbatch --nodelist="$node" per-node-job.sbatch
    fi
done
