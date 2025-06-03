#!/bin/bash -e
#SBATCH --job-name=slurm_resource_test
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=1G
#SBATCH --time=00:00:30
#SBATCH --partition=all
#SBATCH --output=slurm_resource_test_%j.out
#SBATCH --error=slurm_resource_test_%j.err

ml stress-ng

echo "[$(date)] Allocated nodes: $SLURM_NODELIST"
echo "[$(date)] Total CPUs allocated: $SLURM_NPROCS"
echo "[$(date)] Tasks per node: $SLURM_TASKS_PER_NODE"
echo "[$(date)] CPUs per task: $SLURM_CPUS_PER_TASK"
echo "[$(date)] Memory per CPU: $SLURM_MEM_PER_CPU"

# Run a dummy workload to verify CPU allocation
srun stress-ng --cpu "$SLURM_CPUS_PER_TASK" --timeout 10s --metrics-brief
