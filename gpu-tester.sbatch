#!/bin/bash -e
#SBATCH --job-name=gpu_test
#SBATCH --output=gpu_test_%j.out
#SBATCH --error=gpu_test_%j.err
#SBATCH --ntasks=1
#SBATCH --time=00:05:00
#SBATCH --mem=1G
#SBATCH --partition=gpu
#SBATCH --gres=gpu:2

echo "Starting GPU test on node $(hostname)..."
echo "Requested GRES: $SLURM_GPUS" 
echo "Requested GRES (specific): $SLURM_GPUS_ON_NODE"

# Load CUDA or relevant GPU driver modules
ml cuda

# Run a simple GPU command (e.g., nvidia-smi)
nvidia-smi

# You might also want to run a simple CUDA example program here
# For example, if you have a compiled 'vectorAdd' from CUDA samples:
# ./vectorAdd

echo "GPU test finished."
