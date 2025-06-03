# sandbox
A Box Full of Sand.

---

Comprehensive SLURM Post-Maintenance Cluster Validation Script for HPC Environments
1. Introduction
Purpose and Importance of Post-Maintenance Validation

Planned maintenance activities, particularly those involving a full power cycle and deep system updates, are critical events for any High-Performance Computing (HPC) cluster. These activities can encompass a wide range of changes, including operating system upgrades, updates to SLURM and HPC portal software, and crucial driver updates for components such as Nvidia GPUs, Infiniband interconnects, and storage systems, alongside BIOS and firmware updates. Such extensive modifications, while necessary for performance and security, introduce a significant risk of unforeseen issues.

A comprehensive validation script, executed immediately following these maintenance periods, serves as an essential "go/no-go" checklist. Its primary purpose is to systematically ensure that all critical HPC components are not only functional but also performing optimally before users are granted access to resume their workloads. This proactive approach is vital for minimizing potential downtime, preventing user frustration, and maintaining the integrity of research and computational processes. The validation process extends beyond merely checking for component uptime; it delves into the integrated system's behavior. A power cycle and deep system updates, as described, mean that even seemingly independent components like a shared filesystem or the network fabric could be subtly affected by changes in underlying drivers, kernel modules, or low-level configurations. A well-designed, comprehensive script is therefore instrumental in uncovering these cascading effects, rather than just isolated failures, providing a holistic assessment of cluster health.
Assumptions and Prerequisites for Script Execution

The successful execution of this validation script relies on several key assumptions regarding the cluster's state and configuration. Primarily, it is assumed that the SLURM control plane, encompassing the slurmctld and slurmd daemons, is operational and accessible from the designated job submission host. The script inherently depends on sbatch for job submission and management.

Furthermore, it is a prerequisite that all necessary benchmarking tools, such as Flexible I/O tester (fio), iperf3 for network performance, and the OSU Micro-Benchmarks for MPI communication analysis, are either pre-installed on the compute nodes or readily available for loading via the Lmod module system. The presence of cifs-utils for SMB mounts and nfs-common (or equivalent packages) for NFS mounts is also assumed. The executing user must possess the appropriate permissions to submit jobs, allocate resources, and perform read/write operations across all relevant shared filesystems (GPFS, SMB, NFS). Finally, familiarity with the cluster's specific partitions, Quality of Service (QoS) levels, and account names is essential for correctly configuring SLURM job directives.  

The user's request explicitly states that "all services/hosts were power cycled." This condition implies a cold boot scenario for the entire cluster. This context dictates that the validation script must implicitly test the automated startup sequence of critical services. If any service, such as GPFS, NFS, or SMB mounts, requires manual intervention to start or remount after the power cycle, the script's inability to utilize it would be a critical finding. This scenario would indicate a fundamental issue with the system's boot-time configuration or service dependencies, representing a higher-order problem than a mere performance bottleneck. The script, by attempting to use these services without prior manual setup, serves to validate that these services correctly initiate and function automatically post-reboot.
2. SLURM Core Functionality Validation
Scheduler Responsiveness and Basic Job Submission

The initial and most fundamental step in post-maintenance validation is to confirm that the SLURM control daemon (slurmctld) is active, responsive, and correctly accepting job submissions. This check is paramount, as the entire cluster's functionality, when managed by SLURM, hinges on the scheduler's ability to queue and dispatch jobs.  

A minimal, short-duration sbatch job is submitted to test this end-to-end job submission and execution pipeline. The script is designed to simply echo a message to its output file and then exit.

  ```
  #!/bin/bash -e
  #SBATCH --job-name=slurm_basic_test
  #SBATCH --nodes=1
  #SBATCH --ntasks=1
  #SBATCH --time=00:00:10
  #SBATCH --output=slurm_basic_test_%j.out
  #SBATCH --error=slurm_basic_test_%j.err
  
  echo "[$(date)] SLURM basic test job submitted and running on node $(hostname)!"
  ```

The script is submitted using sbatch slurm_basic_test.sh.

Following submission, verification involves using squeue -j <jobid>  to observe the job's state transitions from PENDING (PD) to RUNNING (R) and finally to COMPLETED (CD). Crucially, the generated output file (slurm_basic_test_*.out) must be inspected for the echoed message, confirming successful execution on a compute node.  

The inclusion of #!/bin/bash -e at the beginning of the script is a critical design choice for robust post-maintenance diagnostics. This directive instructs the shell to exit immediately if any command within the script returns a non-zero exit status, which typically signifies an error. This behavior is vital because it compels SLURM to mark the job as FAILED  in its accounting records, providing an unambiguous signal of a problem. Without this directive, a script might continue executing even after a critical internal command has failed, potentially masking the underlying issue and leading to a misleading COMPLETED job status. This could hinder automated monitoring and diagnosis, as a seemingly successful job might have encountered a significant internal fault.

Resource Allocation Verification (CPU, Memory, Nodes, Partitions)

Verifying resource allocation ensures that SLURM correctly interprets and assigns requested resources, including nodes, CPU cores, and memory. It also confirms that compute nodes are properly registered within their designated partitions. This step validates the scheduler's fundamental resource management capabilities.  

Jobs are submitted with varying resource configurations to test the scheduler's flexibility and accuracy. A multi-node job requesting specific CPU cores per task and memory per CPU serves as a comprehensive example.
  
  ```
  #!/bin/bash -e
  #SBATCH --job-name=slurm_resource_test
  #SBATCH --nodes=2
  #SBATCH --ntasks-per-node=4
  #SBATCH --cpus-per-task=2
  #SBATCH --mem-per-cpu=1G
  #SBATCH --time=00:00:30
  #SBATCH --partition=compute # Replace with your cluster's partition name
  #SBATCH --output=slurm_resource_test_%j.out
  #SBATCH --error=slurm_resource_test_%j.err
  
  echo "[$(date)] Allocated nodes: $SLURM_NODELIST"
  echo "[$(date)] Total CPUs allocated: $SLURM_NPROCS"
  echo "[$(date)] Tasks per node: $SLURM_TASKS_PER_NODE"
  echo "[$(date)] CPUs per task: $SLURM_CPUS_PER_TASK"
  echo "[$(date)] Memory per CPU: $SLURM_MEM_PER_CPU"
  
  # Run a dummy workload to verify CPU allocation
  srun stress-ng --cpu "$SLURM_CPUS_PER_TASK" --timeout 10s --metrics-brief
  ```

(Note: stress-ng may need to be installed or available via Lmod.)

Verification involves using scontrol show job <jobid>  or sacct -j <jobid> --format=ReqNodes,ReqCPUs,ReqMem,NodeList,State  to confirm that the allocated resources precisely match the requested values. The job output is inspected for the echoed SLURM_* environment variables and the stress-ng metrics, which should reflect the allocated CPU cores.  

The SLURM_NODELIST environment variable  is profoundly critical for dynamically targeting specific nodes within an allocation, especially for subsequent multi-node tests like iperf3. Its correct population and parsability after maintenance directly confirm the scheduler's ability to accurately identify, assign, and communicate with allocated compute nodes. If SLURM_NODELIST is malformed, empty, or cannot be correctly parsed by the script (e.g., using scontrol show hostnames or bash array expansion as shown in ), it indicates a deeper issue with SLURM's node awareness or internal network configuration, even if the nodes are physically online. This type of failure would preempt reliable multi-node testing, making its validation a prerequisite for network performance checks. This process validates the "programmability" of the SLURM environment itself, ensuring that the cluster can be effectively managed and utilized by complex, distributed applications.

QoS and Reservation Policy Compliance Checks

This validation step ensures that Quality of Service (QoS) policies and advanced reservations are correctly recognized and enforced by the SLURM scheduler. This is crucial for maintaining fair resource sharing, adherence to usage policies, and proper access to dedicated or reserved resources, all of which contribute to the cluster's operational integrity and user satisfaction.  

Jobs are submitted explicitly targeting specific QoS levels (e.g., short, long, debug ) and, if applicable, pre-defined reservations. This validates that the scheduler's policy engine is correctly configured post-maintenance.

  ```
  #!/bin/bash -e
  #SBATCH --job-name=slurm_qos_test
  #SBATCH --nodes=1
  #SBATCH --ntasks=1
  #SBATCH --time=00:00:20 # For 'short' QoS, if applicable
  #SBATCH --partition=shared # Example partition
  #SBATCH --qos=short # Example QoS [2, 3, 19]
  #SBATCH --reservation=maintenance_test # Example reservation [3, 17, 18]
  #SBATCH --output=slurm_qos_test_%j.out
  #SBATCH --error=slurm_qos_test_%j.err
  
  echo "[$(date)] QoS/Reservation test job running on $(hostname)."
  sleep 5 # Allow scheduler to process [20]
  ```

Verification involves using scontrol show job <jobid>  and sacct -j <jobid> --format=QOS,Reservation,State,Reason  to confirm that the job was submitted and processed under the correct QoS and/or reservation. A critical aspect of this check is to look for FAILED or PENDING states accompanied by specific Reason messages, such as "ReqNodeNotAvail, Reserved for maintenance" , which would indicate an incorrect or lingering reservation.  

Maintenance periods frequently involve the use of SLURM reservations to take nodes offline. A comprehensive post-maintenance check on QoS and reservations is therefore not just a policy compliance verification, but a critical operational check to ensure that these temporary configurations are correctly released or re-applied. If this transition is incomplete or flawed, user jobs might encounter unexpected PENDING states with misleading reasons, or run with incorrect priorities or resource limits. This could severely impact user productivity and trust in the system. This validation step confirms that the cluster is ready for normal operational loads and adheres to its defined resource management policies.
Job Output, Error Handling, and Exit Code Monitoring

Ensuring that all standard output and error streams from jobs are correctly captured, and that job termination statuses (exit codes) are accurately reported by SLURM, is foundational for effective debugging, performance analysis, and automated monitoring of job health.  

The test design includes scenarios for normal completion, intentional non-zero exit codes, and memory exhaustion to trigger an Out-Of-Memory (OOM) kill.

For standard output and error redirection, the following SLURM directives are used:

    #SBATCH --output=myjob_%j.out   

#SBATCH --error=myjob_%j.err  

For email notifications on job status changes:

    #SBATCH --mail-type=BEGIN,END,FAIL,TIME_LIMIT   

#SBATCH --mail-user=admin@example.com  

An in-script example for logging and testing exit codes:

```
echo "[$(date)] Starting output and error test."
# Simulate a successful command
echo "[INFO] This is a standard output message."
# Simulate a command that fails
false |
| { echo " Intentional command failure detected." >&2; exit 1; } # Redirect to stderr
echo "[$(date)] Test finished successfully (this line should not be reached if previous command failed)."
```

For testing OOM conditions, a separate job is submitted with a very low memory request (e.g., #SBATCH --mem=100M) and instructed to run a program that attempts to allocate significantly more memory (e.g., a Python script allocating a large array).

Verification involves checking the myjob_*.out and myjob_*.err files for complete and correctly separated messages. For the exit code test, sacct -j <jobid> --format=State,ExitCode  is used to verify the job state is FAILED and the ExitCode is 1:0 (exit code 1, no signal). For OOM tests, sacct is confirmed to report State=OUT_OF_MEMORY , and any partial output captured before termination is reviewed.  

The research material reveals a critical aspect: sbatch --output may not capture all system output, particularly when a job encounters an Out-Of-Memory (OOM) issue, potentially truncating logs before the error occurred. This represents a significant diagnostic blind spot for post-maintenance validation, as memory issues are common after system updates. This observation implies that relying solely on standard output redirection might be insufficient for comprehensive diagnostics in all failure scenarios. To address this, a robust validation script explicitly checks sacct for the OUT_OF_MEMORY state. This provides a definitive indicator of the failure type, even if the primary log file is incomplete. Furthermore, for critical sections of the validation script where early termination is a concern, employing tee to write to both file and standard output simultaneously, or using stdbuf -oL to ensure line-buffered output, can maximize the amount of diagnostic information captured before an abrupt crash. This proactive logging strategy goes beyond basic output directives and provides a deeper layer of diagnostic capability.  

3. Shared Filesystem Accessibility and Integrity Tests
GPFS Filesystem Mount Verification and Basic I/O Operations

GPFS (IBM Spectrum Scale) is a cornerstone of many HPC environments, providing high-performance parallel access to data. Following maintenance, verifying its mount status, accessibility, and basic read/write functionality is crucial to ensure data availability and integrity for compute jobs.  

The test for mount status involves using df -hT | grep gpfs. This command lists filesystem disk space usage, including the type, and filtering for "gpfs" confirms its presence.  

Regarding integrity checks, while the provided information mentions mmfileid  to identify files on damaged disk blocks and mmlssnapshot  to verify snapshot completeness, it does not provide direct, general-purpose GPFS filesystem integrity check commands (analogous to fsck for other filesystems). For a truly comprehensive integrity check, one might need to consult IBM Spectrum Scale documentation for deeper, vendor-specific tools. For the purpose of this script, basic I/O operations serve as a primary indicator of operational integrity.  

Basic I/O operations involve performing simple file creation, writing, reading, and deletion on a designated GPFS path. This verifies fundamental read/write permissions and underlying data path functionality.

  ```
  GPFS_TEST_DIR="/gpfs/fs1/test_validation_$(date +%s)" # Adjust /gpfs/fs1 to your GPFS mount
  echo "[$(date)] Testing GPFS mount: $GPFS_TEST_DIR"
  mkdir -p "$GPFS_TEST_DIR" |
  | { echo " Failed to create GPFS test directory." >&2; exit 1; }
  touch "$GPFS_TEST_DIR/gpfs_test_file.txt" |
  | { echo " Failed to create file on GPFS." >&2; exit 1; }
  echo "GPFS write test data: $(date)" > "$GPFS_TEST_DIR/gpfs_test_file.txt" |
  | { echo " Failed to write to file on GPFS." >&2; exit 1; }
  echo "[INFO] Content of GPFS test file:"
  cat "$GPFS_TEST_DIR/gpfs_test_file.txt" |
  | { echo " Failed to read file from GPFS." >&2; exit 1; }
  rm "$GPFS_TEST_DIR/gpfs_test_file.txt" |
  | { echo " Failed to remove file from GPFS." >&2; exit 1; }
  rmdir "$GPFS_TEST_DIR" |
  | { echo " Failed to remove GPFS test directory." >&2; exit 1; }
  echo "[$(date)] GPFS basic I/O test PASSED."
  ```

Verification is performed by checking the exit codes ($?) of each command and reviewing the output messages. Successful execution of all commands indicates basic GPFS accessibility and read/write functionality.

The available information provides high-level concepts for GPFS integrity, such as metadata consistency and snapshot validation, but it lacks specific, executable commands for a general "filesystem integrity check" or basic read/write tests directly within GPFS, beyond snapshot verification. This represents a gap for a truly comprehensive automated script. Consequently, for the purposes of this script, reliance is placed on successful basic file operations and later, performance benchmarks (fio, dd) on the GPFS mount point. This approach implies that a comprehensive GPFS integrity check after maintenance might necessitate deeper, vendor-specific diagnostics (e.g., mmfsck if available and safe for production environments, or other mm commands not detailed here) beyond what the current information provides. The interpretation of "integrity" for this script is thus primarily tied to the successful execution of I/O operations.  

SMB Mount Accessibility and Read/Write Performance Tests

SMB/CIFS mounts are frequently utilized in HPC environments for integration with Windows-based systems, administrative access, or specific datasets. Validating their accessibility and performance after maintenance is crucial to ensure that all necessary data paths are functional and performant.  

Mount status verification involves using mount -t cifs  or df -hT | grep cifs, which confirms the mount point is active. Basic I/O operations are then performed to confirm permissions and fundamental functionality.

```
SMB_TEST_DIR="/mnt/smb_share/test_validation_$(date +%s)" # Adjust /mnt/smb_share to your SMB mount
echo "[$(date)] Testing SMB mount: $SMB_TEST_DIR"
mkdir -p "$SMB_TEST_DIR" |
| { echo " Failed to create SMB test directory." >&2; exit 1; }
touch "$SMB_TEST_DIR/smb_test_file.txt" |
| { echo " Failed to create file on SMB." >&2; exit 1; }
echo "SMB write test data: $(date)" > "$SMB_TEST_DIR/smb_test_file.txt" |
| { echo " Failed to write to file on SMB." >&2; exit 1; }
echo "[INFO] Content of SMB test file:"
cat "$SMB_TEST_DIR/smb_test_file.txt" |
| { echo " Failed to read file from SMB." >&2; exit 1; }
rm "$SMB_TEST_DIR/smb_test_file.txt" |
| { echo " Failed to remove file from SMB." >&2; exit 1; }
rmdir "$SMB_TEST_DIR" |
| { echo " Failed to remove SMB test directory." >&2; exit 1; }
echo "[$(date)] SMB basic I/O test PASSED."
```

For performance testing, dd or fio can be used on the SMB mount point.

    Example dd write: time dd if=/dev/zero of=$SMB_TEST_DIR/dd_testfile.bin bs=1M count=1024 conv=fdatasync   

Example dd read: sync; echo 3 | sudo tee /proc/sys/vm/drop_caches; time dd if=$SMB_TEST_DIR/dd_testfile.bin of=/dev/null bs=1M count=1024  

Verification involves checking mount output, confirming file existence, and analyzing dd/fio performance metrics.

The provided information highlights that cifs-utils is a prerequisite for SMB mounts. After maintenance, it is crucial to ensure that this package is installed and functional, and that any necessary credentials (which might be stored in a hidden file ) are correctly accessible. A failure at this stage could indicate a missing package, corrupted credentials, or underlying network issues, each requiring a distinct diagnostic approach from a purely performance-related problem. This emphasizes the need to validate the foundational software components before assessing performance.  

NFS Mount Accessibility and Read/Write Performance Tests

NFS mounts are ubiquitous in HPC environments, providing shared access to home directories and project spaces. Validating their accessibility and performance after maintenance is paramount for user productivity and data consistency.  

Mount status is checked using mount -v | grep nfs  or df -hT | grep nfs. Additionally, nfsstat -m  can provide detailed version information (NFSv3 vs NFSv4.x). Basic I/O operations are then performed on the NFS path.  

```
NFS_TEST_DIR="/mnt/nfs_share/test_validation_$(date +%s)" # Adjust /mnt/nfs_share to your NFS mount
echo "[$(date)] Testing NFS mount: $NFS_TEST_DIR"
mkdir -p "$NFS_TEST_DIR" |
| { echo " Failed to create NFS test directory." >&2; exit 1; }
touch "$NFS_TEST_DIR/nfs_test_file.txt" |
| { echo " Failed to create file on NFS." >&2; exit 1; }
echo "NFS write test data: $(date)" > "$NFS_TEST_DIR/nfs_test_file.txt" |
| { echo " Failed to write to file on NFS." >&2; exit 1; }
echo "[INFO] Content of NFS test file:"
cat "$NFS_TEST_DIR/nfs_test_file.txt" |
| { echo " Failed to read file from NFS." >&2; exit 1; }
rm "$NFS_TEST_DIR/nfs_test_file.txt" |
| { echo " Failed to remove file from NFS." >&2; exit 1; }
rmdir "$NFS_TEST_DIR" |
| { echo " Failed to remove NFS test directory." >&2; exit 1; }
echo "[$(date)] NFS basic I/O test PASSED."
```

Performance testing uses dd or fio on the NFS mount point, similar to SMB tests.

Verification involves checking mount or nfsstat output, confirming successful file operations, and analyzing performance metrics.

NFS versions (NFSv3 vs NFSv4.x) have distinct port requirements and behaviors. After maintenance, it is essential to confirm that the correct NFS version is mounted and that associated services (such as portmap for NFSv3 ) are running. Incorrect version negotiation or issues with firewall configurations  can lead to subtle performance problems or intermittent access, which a simple mount check might overlook. This detailed verification ensures that the NFS service is not only mounted but also operating optimally according to its configured protocol.  

| Filesystem Type | Mount Point Example | Status Check Command | Basic Write Test Command | Basic Read Test Command | Cleanup Command | Expected Output/Success Indicator                                 |
|-----------------|---------------------|----------------------|--------------------------|-------------------------|-----------------|-------------------------------------------------------------------|
| GPFS            | /gpfs/fs1           | `df -hT \            | grep gpfs`               | echo "data" > file.txt  | cat file.txt    | rm file.txt                                                       |
| SMB             | /mnt/smb_share      | mount -t cifs        | echo "data" > file.txt   | cat file.txt            | rm file.txt     | Mount listed, data written/read successfully                      |
| NFS             | /mnt/nfs_share      | nfsstat -m           | echo "data" > file.txt   | cat file.txt            | rm file.txt     | Mount listed with correct version, data written/read successfully |

4. Lmod Module System Verification
Module Availability and Loading Functionality Tests

Lmod is a critical component for managing software environments in HPC clusters. Following maintenance, new software versions or configuration changes might affect module paths or dependencies. This section verifies the Lmod system's integrity and functionality.  

The tests include:

    Listing all available modules: module avail.   

Searching for specific critical modules (e.g., compilers, MPI libraries): module avail intel , module spider openmpi.  
Loading and unloading a common module: module load gcc/11.3.0 , module list , module unload gcc.  
Testing module swapping: module swap gcc intel.  
Testing module purge and module reset to ensure environment cleanup and default restoration.  

Verification involves checking the command output for expected module lists, successful loading/unloading messages, and correct environment variable changes (e.g., which mpicc after loading an MPI module).

The hierarchical nature of Lmod  implies that a problem with a base module, such as a compiler, can prevent dependent modules (e.g., MPI libraries built with that compiler) from being available or loading correctly. This represents a subtle but critical failure mode after maintenance, where underlying library updates might inadvertently break module dependencies. The module spider command  is particularly useful for diagnosing such issues, as it reveals modules that are not currently loadable but could be available if their dependencies were met. This capability is key to identifying breaks in the module hierarchy that might not be immediately apparent through a simple module avail command.  

Environment Consistency and Path Validation

Beyond merely loading modules, it is essential to ensure that the Lmod system correctly modifies the user's environment, specifically PATH and LD_LIBRARY_PATH, and that the installed binaries are indeed accessible and executable.

After loading a module, verification involves checking key environment variables and attempting to execute a simple command provided by that module.

    Example: module load anaconda3/2024.2 followed by which python and python --version.   

Example: module load openmpi followed by which mpirun.  

The output of which commands and version checks serves as verification.

A common issue after maintenance is that while module files may exist and appear to load successfully, the underlying binaries or libraries they point to might be missing or corrupted due to incomplete updates or filesystem issues. Simply loading a module only modifies environment variables; it does not guarantee the existence or executability of the software it references. Therefore, validating the executability of the software provided by the module (e.g., which python, python --version) is the true test of end-to-end functionality. This confirms that the module loads, the environment is correctly set, and the software itself is present and operational.

| Test Category     | Lmod Command                       | Purpose/What it Checks                                                 | Expected Output/Success Indicator                |
|-------------------|------------------------------------|------------------------------------------------------------------------|--------------------------------------------------|
| Availability      | module avail                       | Lists all modules currently loadable                                   | List of available modules                        |
| Availability      | module spider <package-name>       | Searches all possible modules, including those with unmet dependencies | Detailed description, versions, and dependencies |
| Loading           | module load <package-name/version> | Loads specified module into current environment                        | No error, module list shows loaded module        |
| Environment Check | module list                        | Lists all currently loaded modules                                     | Accurate list of loaded modules                  |
| Unloading         | module unload <package-name>       | Unloads specified module from environment                              | No error, module list no longer shows module     |
| Swapping          | module swap <old-pkg> <new-pkg>    | Unloads one module and loads another                                   | No error, module list shows new package          |
| Cleanup           | module purge                       | Unloads all modules                                                    | Empty module list (except sticky modules)        |
| Environment Check | which <tool-from-module>           | Verifies path to executable after module load                          | Correct path to tool's binary                    |
| Environment Check | <tool-from-module> --version       | Verifies the loaded software is executable and correct version         | Tool's version information                       |

5. Inter-Node Network Performance Benchmarking
MPI Latency and Bandwidth Tests (OSU Benchmarks)

Message Passing Interface (MPI) is the backbone of parallel computing in HPC environments. After maintenance, it is vital to ensure that the high-speed interconnect (e.g., InfiniBand, ROCE ) is fully functional and optimized for MPI communication. The OSU Micro-Benchmarks are industry standards for precisely measuring MPI performance metrics such as latency and bandwidth.  

The testing procedure involves compiling and running osu_latency and osu_bw across multiple nodes.

    Compilation: If not using pre-compiled binaries , compilation steps typically involve: source compiler-select intel-oneapi (or equivalent for other compilers), followed by mpiicx -o osu_latency osu_latency.c.   

SLURM Script Example:

  ```
  #!/bin/bash -e
  #SBATCH --job-name=osu_mpi_test
  #SBATCH --nodes=2
  #SBATCH --ntasks-per-node=1 # For point-to-point tests
  #SBATCH --time=00:05:00
  #SBATCH --partition=compute # Replace with your cluster's partition name [20, 42]
  #SBATCH --exclusive # To ensure no interference from other jobs [20]
  #SBATCH --output=osu_mpi_test_%j.out
  #SBATCH --error=osu_mpi_test_%j.err
  
  module purge [42]
  module load <appropriate_mpi_module> # e.g., mpich-aocc/4.0.3 [42] or openmpi [10, 21]
  
  echo "[$(date)] Running OSU Latency Test (Point-to-Point)"
  srun./osu_latency # [20, 42]
  
  echo "[$(date)] Running OSU Bandwidth Test (Point-to-Point)"
  srun./osu_bw # [20, 42]
  
  # Optional: Test with different FI_PROVIDER settings to compare interconnect vs TCP
  # echo "[$(date)] Running OSU Latency Test (TCP fallback)"
  # mpirun -np 2 -ppn 1 -genv FI_PROVIDER="tcp;ofi_rxm"./osu_latency [42]
  # echo "[$(date)] Running OSU Bandwidth Test (TCP fallback)"
  # mpirun -np 2 -ppn 1 -genv FI_PROVIDER="tcp;ofi_rxm"./osu_bw [42]
  ```

Verification involves analyzing the output for latency (in microseconds or milliseconds) and bandwidth (in MB/s or GB/s) values. These results should be compared against pre-maintenance baseline performance data or expected values for the specific interconnect technology in use.  

The choice between srun and mpirun for launching MPI jobs is significant. srun is often preferred as it integrates directly with SLURM's resource allocation and implicitly provides the necessary MPI environment. However, mpirun might be necessary if the application was compiled with a specific MPI implementation that does not fully integrate with srun or if specific MPI runtime parameters are required. After maintenance, ensuring the correct MPI environment is loaded  and that srun correctly sets up the communication fabric (e.g., InfiniBand/ROCE ) is paramount. Comparing performance with different FI_PROVIDER settings (e.g., verbs;ofi_rxm for RDMA vs. tcp;ofi_rxm for standard TCP ) allows for direct verification of the high-speed fabric's efficacy, indicating whether maintenance activities have impacted the low-latency communication path.  

General Network Throughput Measurement (iperf3)

iperf3 is a widely recognized tool for measuring raw TCP/UDP bandwidth between two hosts. It complements MPI tests by providing a general network health check that is independent of specific MPI libraries. This is crucial for validating basic network connectivity and throughput after maintenance.  

The test involves setting up iperf3 in client-server mode between two allocated nodes.

  ```
  #!/bin/bash -e
  #SBATCH --job-name=iperf3_test
  #SBATCH --nodes=2
  #SBATCH --ntasks-per-node=1
  #SBATCH --time=00:02:00
  #SBATCH --partition=compute # Replace with your cluster's partition name
  #SBATCH --exclusive
  #SBATCH --output=iperf3_test_%j.out
  #SBATCH --error=iperf3_test_%j.err
  
  # Parse SLURM_NODELIST to get hostnames for client and server
  NODES=($(scontrol show hostnames "$SLURM_NODELIST")) # [16]
  SERVER_NODE="${NODES}"
  CLIENT_NODE="${NODES}"
  
  echo "[$(date)] Starting iperf3 server on $SERVER_NODE"
  # Run iperf3 server in the background on the first allocated node
  # --no-kill and --wait=0 are crucial for the server to persist
  srun --nodes=1 --ntasks=1 --exclusive -w "$SERVER_NODE" --job-name=iperf_server --output=iperf_server_%j.out --error=iperf_server_%j.err --no-kill --wait=0 iperf3 -s -D &
  SERVER_PID=$!
  sleep 5 # Give server time to start
  
  echo "[$(date)] Starting iperf3 client on $CLIENT_NODE, connecting to $SERVER_NODE"
  # Run iperf3 client on the second allocated node
  srun --nodes=1 --ntasks=1 --exclusive -w "$CLIENT_NODE" --job-name=iperf_client --output=iperf_client_%j.out --error=iperf_client_%j.err iperf3 -c "$SERVER_NODE" -t 30 -P 8
  
  echo "[$(date)] Killing iperf3 server (PID: $SERVER_PID)"
  kill "$SERVER_PID" # Clean up the background server
  wait "$SERVER_PID" 2>/dev/null # Wait for the server to terminate
  echo "[$(date)] iperf3 test completed."
  ```

Verification involves analyzing the iperf3 output for reported bandwidth values.

Dynamically parsing SLURM_NODELIST  within the sbatch script to assign iperf3 server and client roles is a sophisticated validation of SLURM's node allocation and environment variable propagation. If SLURM_NODELIST is malformed or not correctly parsed after a power cycle, the iperf3 test cannot be set up, indicating a fundamental SLURM issue before network performance itself. This process tests the "programmability" of the cluster environment, confirming that SLURM can correctly allocate resources and that the script can interpret this information for multi-node operations. This constitutes a higher-order validation of the entire SLURM-managed environment.  

| Test Type                 | Tool        | Key sbatch Directives                                   | Execution Command                                  | What it Measures                              | Expected Output/Success Indicator                               |
|---------------------------|-------------|---------------------------------------------------------|----------------------------------------------------|-----------------------------------------------|-----------------------------------------------------------------|
| MPI Latency               | osu_latency | --nodes=2, --ntasks-per-node=1, --exclusive             | srun./osu_latency                                  | Point-to-point message latency (µs)           | Low latency values (e.g., < 10 µs for InfiniBand)               |
| MPI Bandwidth             | osu_bw      | --nodes=2, --ntasks-per-node=1, --exclusive             | srun./osu_bw                                       | Point-to-point message bandwidth (MB/s, GB/s) | High bandwidth values (e.g., near theoretical interconnect max) |
| General TCP/UDP Bandwidth | iperf3      | --nodes=2, --ntasks-per-node=1 (for client/server pair) | iperf3 -s (server), iperf3 -c <server_ip> (client) | TCP/UDP throughput (Gbits/s)                  | High throughput values (e.g., near network interface max)       |

6. Disk I/O Performance Benchmarking
Sequential Read/Write Throughput Tests (fio, dd)

Disk I/O speed is a critical factor for application performance, particularly for workloads that are I/O-bound. After maintenance, new drivers or firmware updates  could affect local disk performance, while shared filesystem performance depends on both disk and network capabilities.

The tests utilize fio for detailed, configurable benchmarks  and dd for quick, basic checks.  

  ```
  TEST_DIR="/scratch/local/test_io_$(date +%s)" # Use local scratch or a shared filesystem mount
  mkdir -p "$TEST_DIR" |
  
  | { echo " Failed to create test directory for FIO." >&2; exit 1; }
  echo "[$(date)] Running FIO Sequential Write Throughput test on $TEST_DIR"
  sudo fio --name=write_throughput --directory="$TEST_DIR" --numjobs=16 --size=10G --time_based --runtime=5m --ioengine=libaio --direct=1 --bs=1M --iodepth=64 --rw=write --group_reporting=1 |
  | { echo " FIO sequential write test failed." >&2; exit 1; }
  ```
  
  ```
  echo "[$(date)] Running FIO Sequential Read Throughput test on $TEST_DIR"
  sudo fio --name=read_throughput --directory="$TEST_DIR" --numjobs=16 --size=10G --time_based --runtime=5m --ioengine=libaio --direct=1 --bs=1M --iodepth=64 --rw=read --group_reporting=1 |
  
  | { echo " FIO sequential read test failed." >&2; exit 1; }
  ```
  
  ```
  echo "[$(date)] Running DD Sequential Write test on $TEST_DIR"
  sync; time sh -c "dd if=/dev/zero of=\"$TEST_DIR/dd_write_test.bin\" bs=1M count=1024 conv=fdatasync; sync" |
  
  | { echo " DD sequential write test failed." >&2; exit 1; }
  ```
  
  ```
  echo "[$(date)] Running DD Sequential Read test on $TEST_DIR"
  sync; echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null; time dd if="$TEST_DIR/dd_write_test.bin" of=/dev/null bs=1M count=1024 |
  
  | { echo " DD sequential read test failed." >&2; exit 1; }
  ```

Verification involves analyzing fio output for aggregate bandwidth. For dd, the time output is recorded to calculate MB/s.  

The distinction between dd and fio is crucial for accurate performance assessment. While dd is simple to use, its results can be misleading due to Linux's disk write caching. fio, on the other hand, provides more accurate and comprehensive results by allowing control over parameters such as queue depth, I/O engine, and direct I/O, which bypasses the operating system's cache. After maintenance, relying solely on dd might provide a false sense of security if the underlying disk performance is degraded but masked by a healthy cache. A comprehensive script must prioritize fio for reliable metrics, using dd only for quick sanity checks, and then only with explicit cache flushing.  

Random Read/Write IOPS Tests (fio)

Input/Output Operations Per Second (IOPS) are critical performance metrics for databases and applications characterized by many small, random I/O operations. These tests assess the disk's ability to handle high concurrency and random access patterns, which are often more sensitive to storage subsystem health.

The tests utilize fio with random I/O patterns and high queue depths.

```
echo "[$(date)] Running FIO Random Write IOPS test on $TEST_DIR"
sudo fio --name=write_iops --directory="$TEST_DIR" --size=10G --time_based --runtime=5m --ioengine=libaio --direct=1 --bs=4K --iodepth=256 --rw=randwrite --group_reporting=1 |

| { echo " FIO random write IOPS test failed." >&2; exit 1; }
```

```
echo "[$(date)] Running FIO Random Read IOPS test on $TEST_DIR"
sudo fio --name=read_iops --directory="$TEST_DIR" --size=10G --time_based --runtime=5m --ioengine=libaio --direct=1 --bs=4K --iodepth=256 --rw=randread --group_reporting=1 |

| { echo " FIO random read IOPS test failed." >&2; exit 1; }
```

Verification involves analyzing fio output for IOPS metrics.

Random I/O performance is often more sensitive to the health of the disk subsystem (e.g., controllers, RAID configurations, underlying storage hardware) than sequential I/O. A degradation in random IOPS after maintenance, even if sequential throughput remains acceptable, can indicate issues with storage drivers, firmware, or even physical disk health. This provides a deeper diagnostic layer than bandwidth tests alone, as it can uncover subtle problems with the storage subsystem that sequential tests might miss, implying a need for more in-depth hardware-level diagnostics.

| Test Type                   | Tool | Key Parameters                                     | Execution Command                                         | What it Measures                                                    | Expected Output/Success Indicator       |
|-----------------------------|------|----------------------------------------------------|-----------------------------------------------------------|---------------------------------------------------------------------|-----------------------------------------|
| Sequential Write Throughput | fio  | --bs=1M, --iodepth=64, --rw=write, --direct=1      | sudo fio --name=write_throughput --directory=$TEST_DIR... | MB/s                                                                | High bandwidth (e.g., > 500 MB/s)       |
| Sequential Read Throughput  | fio  | --bs=1M, --iodepth=64, --rw=read, --direct=1       | sudo fio --name=read_throughput --directory=$TEST_DIR...  | MB/s                                                                | High bandwidth (e.g., > 500 MB/s)       |
| Random Write IOPS           | fio  | --bs=4K, --iodepth=256, --rw=randwrite, --direct=1 | sudo fio --name=write_iops --directory=$TEST_DIR...       | IOPS                                                                | High IOPS (e.g., > 50,000 IOPS for SSD) |
| Random Read IOPS            | fio  | --bs=4K, --iodepth=256, --rw=randread, --direct=1  | sudo fio --name=read_iops --directory=$TEST_DIR...        | IOPS                                                                | High IOPS (e.g., > 50,000 IOPS for SSD) |
| Sequential Write (basic)    | dd   | bs=1M, count=1024, conv=fdatasync                  | sync; time sh -c 'dd if=/dev/zero of=file...; sync'       | MB/s                                                                | Time output, calculated speed           |
| Sequential Read (basic)     | dd   | bs=1M, count=1024                                  | `sync; echo 3 \                                           | sudo tee /proc/sys/vm/drop_caches; time dd if=file of=/dev/null...` | MB/s                                    |

7. Comprehensive Validation Script Design and Execution
Overall Script Structure, Modularity, and Flow

A comprehensive validation script requires a well-organized structure to ensure readability, maintainability, and efficient execution. The script should begin with #!/bin/bash -e  to ensure immediate termination upon any non-zero exit status, which is crucial for reliable failure detection.  

SLURM directives are defined at the script's outset, specifying the job name, output and error file paths, time limit, number of nodes, tasks, and memory requirements. This ensures that SLURM correctly allocates resources and manages the job's lifecycle.  

Environment setup is critical; module purge  is executed first to ensure a clean environment, followed by loading necessary modules such as compilers, MPI libraries, and benchmarking tools like fio.  

Each distinct test section (e.g., SLURM basic functionality, GPFS, NFS, SMB, Lmod, Network, Disk I/O) is encapsulated within its own bash function (e.g., test_slurm_basic(), test_gpfs()). This modular approach significantly improves readability, simplifies debugging, and allows administrators to easily comment out or re-run specific tests if initial failures are detected, aiding in rapid diagnostics.

Flow control is managed using if/else statements or && (logical AND) operators to ensure sequential execution and dependency satisfaction (e.g., a filesystem I/O test should only proceed if the mount verification is successful).

Robust cleanup for temporary files and directories is implemented, ideally within a trap command. This ensures that even if a test fails midway and the script terminates unexpectedly, the environment is left clean, preventing resource exhaustion or interference with subsequent runs. The trap command is a critical best practice for a post-maintenance script, as failures are an expected part of the validation process.  

Robust Error Handling, Logging, and Reporting Mechanisms

Effective error handling and comprehensive logging are paramount for a validation script. The set -e directive (from #!/bin/bash -e ) ensures immediate exit on any non-zero command status. For specific commands where a failure is anticipated but not critical enough to halt the entire script, || true or if command; then... else... fi constructs can be used.  

Logging involves redirecting stdout and stderr to separate files using #SBATCH --output and #SBATCH --error directives. Clear echo statements with prefixes like [INFO], , and are used to indicate progress and results. The date and hostname are logged for each step  to provide context. Crucially, command exit codes ($?) are captured and explicitly logged to provide granular detail on success or failure.  

For reporting, the script summarizes results at its conclusion (e.g., "All SLURM tests PASSED", "NFS mount FAILED"). Consideration is given to writing a separate summary file that can be easily parsed or emailed for quick review. Post-execution, sacct  and scontrol show job  are invaluable for inspecting detailed job information and exit codes for deeper analysis.  

The sacct command's ability to retrieve detailed job information, including ExitCode, State, and resource consumption metrics like MaxRSS, MaxDiskRead, and MaxDiskWrite , is a powerful post-mortem diagnostic tool. The script should explicitly advise the administrator on how to use sacct to review the validation job's performance and identify the root cause of any failures, particularly for Out-Of-Memory (OOM) or time limit issues. This transforms raw log data into actionable intelligence, allowing for a more precise and efficient troubleshooting process.  

Execution Instructions and Monitoring Best Practices

The validation script is submitted to the SLURM scheduler using the sbatch command: sbatch validation_script.sh.  

Monitoring the job's progress and status is essential.

    squeue -u <username> or squeue --me provides a high-level overview of job status.   

scontrol show job <jobid> offers detailed real-time information about a running job.  
tail -f <output_file> allows for live monitoring of the job's standard output.  
sacct -j <jobid> is used for comprehensive post-completion analysis, retrieving historical job data.  

Several best practices should be adhered to during execution:

    The script should always be submitted from a stable login node.   

Avoid running squeue or sacct commands in tight loops within scripts, as this can overload the slurmctld daemon and impact scheduler responsiveness for all users.  
Specify walltime generously but not excessively to allow for test completion without premature termination, while also avoiding unnecessarily long queue times.  
Request appropriate resources to prevent jobs from remaining in a pending state for too long or being killed due to OOM errors.  

The warning against frequent squeue/sacct calls in loops  is a critical operational consideration. While these commands are useful for monitoring, their overuse can stress the slurmctld and the accounting database. This emphasizes the need for a balanced approach: sacct is best utilized for post-mortem analysis, and squeue should be used sparingly for high-level status checks. Detailed progress should primarily be gleaned from the script's own well-structured output. This approach ensures that the validation process itself does not inadvertently degrade the cluster's performance, maintaining overall system health.

| Command           | Purpose/What it Checks                              | Key Options/Arguments                                              | Expected Output/Information Provided                                             | Usage Context             |
|-------------------|-----------------------------------------------------|--------------------------------------------------------------------|----------------------------------------------------------------------------------|---------------------------|
| sbatch            | Submits the batch script to SLURM                   | validation_script.sh                                               | Job ID assigned                                                                  | Submission                |
| squeue            | Displays running and pending jobs                   | -u <username>, --me, -j <jobid>, --states=PD                       | Job ID, State (PD, R, CG, CD), Time, Nodes                                       | Real-time monitoring      |
| scontrol show job | Shows detailed information about a specific job     | <jobid>, -dd                                                       | Job state, allocated nodes, requested resources, exit code (for active jobs)     | Real-time troubleshooting |
| sacct             | Queries SLURM accounting database for past jobs     | -j <jobid>, --format=<fields>, --starttime=<date>, --state=<state> | Job ID, JobName, MaxRSS, Elapsed, NodeList, State, ExitCode (for completed jobs) | Post-completion analysis  |
| tail -f           | Monitors live output of a running job's output file | <output_file_name>                                                 | Real-time log messages from the script                                           | Real-time monitoring      |

8. Conclusion and Future Recommendations
Summary of Validation Successes and Identified Areas

The comprehensive SLURM post-maintenance cluster validation script serves as a vital tool for assessing the health and readiness of an HPC environment after a power cycle and system updates. Through systematic testing, the script provides a clear summary of the outcome for each critical component: SLURM core functionality, shared filesystems (GPFS, SMB, NFS), the Lmod module system, inter-node network performance, and disk I/O performance.

Successful execution across all sections indicates that the cluster's fundamental services are operational, resource allocation is accurate, data paths are accessible, software environments are consistent, and both network and disk I/O are performing within expected parameters. Conversely, any failures or degraded performance identified by the script highlight specific areas requiring immediate administrative attention. For instance, an OUT_OF_MEMORY job state  would point to memory configuration issues, while degraded network bandwidth  could indicate problems with interconnect drivers. This detailed reporting allows for a targeted and efficient troubleshooting process, providing a high-level assessment of the cluster's readiness for production workloads.  

Ongoing Cluster Health Monitoring and Maintenance Strategies

The cyclical nature of cluster maintenance, with multiple planned periods throughout the year , implies that this comprehensive validation script should not be a one-off diagnostic tool. Instead, it should be integrated into a continuous monitoring and proactive maintenance strategy.

It is recommended to incorporate these validation tests into a routine health check suite, ideally automated to run periodically or after any significant configuration changes. Establishing automated alerts for critical failures, such as email notifications for FAIL or OUT_OF_MEMORY job states , ensures that administrators are immediately informed of any deviations from expected behavior. Maintaining a robust baseline of performance data for all tested metrics (e.g., disk throughput, network latency) is crucial. This baseline allows for direct comparison of post-maintenance results, enabling the detection of subtle performance degradations that might otherwise go unnoticed. Regular review of SLURM configurations and Lmod module dependencies is also advised, particularly after major system updates, to prevent unforeseen conflicts or broken software stacks.  

The broader implication is a shift from reactive troubleshooting to proactive health management. By leveraging this validation script as a foundational component of a larger operational framework, the cluster can transition towards continuous operational excellence. The script then becomes a key diagnostic element within a proactive monitoring pipeline, contributing to the overall stability, reliability, and performance of the HPC environment.
