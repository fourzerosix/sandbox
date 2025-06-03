#!/bin/bash
#SBATCH --job-name=H0L@-@M!G0$
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
#SBATCH --time=00:01:00

LOG_FILE="/data/scratch/belljs/logs/hola-amigos.txt"

echo "[$(date)] Hello from node $(hostname) in partition $SLURM_JOB_PARTITION" >> "$LOG_FILE"
