#!/bin/bash

# Base parameters
BASE_NCPUS=48
BASE_MEM=190
JOBNAME="cp2k.inp"
RUNSCRIPT_NAME="cp2k_runscript"

# Detect the batch scheduler (PBS on Gadi, Slurm on Setonix)
detect_scheduler() {
    if command -v qsub >/dev/null 2>&1; then
        echo "pbs"
    elif command -v sbatch >/dev/null 2>&1; then
        echo "slurm"
    else
        echo "none"
    fi
}

# Loop to create folders for different numbers of nodes
for NODE in {1..10}; do
    # Calculate ncpus and mem for the corresponding number of nodes
    NCPUS=$((BASE_NCPUS * NODE))
    MEM=$((BASE_MEM * NODE))GB

    # Create new folder, if it exists clear it
    FOLDER_NAME="node_${NODE}"
    if [ -d "$FOLDER_NAME" ]; then
        rm -rf $FOLDER_NAME/*
    else
        mkdir -p $FOLDER_NAME
    fi

    # Copy cp2k.inp and cp2k_runscript to the new folder
    cp $JOBNAME $FOLDER_NAME/
    cp $RUNSCRIPT_NAME $FOLDER_NAME/

    # Modify the cp2k_runscript parameters in the new folder
    sed -i "s/^#PBS -l ncpus=.*/#PBS -l ncpus=$NCPUS/" $FOLDER_NAME/$RUNSCRIPT_NAME
    sed -i "s/^#PBS -l mem=.*/#PBS -l mem=$MEM/" $FOLDER_NAME/$RUNSCRIPT_NAME
    # Slurm runscript: only the node count is changed (--ntasks-per-node and --mem are per node)
    sed -i "s/^#SBATCH --nodes=.*/#SBATCH --nodes=$NODE/" $FOLDER_NAME/$RUNSCRIPT_NAME
    # Make the runscript read ${JOBNAME%.inp}.inp and write ${JOBNAME%.inp}.out (read by cp2k_node_test_time.py)
    sed -i "s/^JOBNAME=.*/JOBNAME=\"${JOBNAME%.inp}\"/" $FOLDER_NAME/$RUNSCRIPT_NAME
    sed -i "s/^OUT_NAME=.*/OUT_NAME=\"${JOBNAME%.inp}\"/" $FOLDER_NAME/$RUNSCRIPT_NAME

    echo "Created folder $FOLDER_NAME with ncpus=$NCPUS and mem=$MEM"
done

if grep -q "^#SBATCH --ntasks=" $RUNSCRIPT_NAME; then
    echo "Warning: $RUNSCRIPT_NAME sets #SBATCH --ntasks (total tasks), which was not changed; use --ntasks-per-node instead"
fi

# Ask if the user wants to submit the jobs
read -p "Do you want to submit the jobs? (y/n): " SUBMIT_JOBS
if [ "$SUBMIT_JOBS" == "y" ]; then
    case "$(detect_scheduler)" in
        pbs)   SUBMIT_CMD="qsub" ;;
        slurm) SUBMIT_CMD="sbatch" ;;
        *)     echo "Neither qsub nor sbatch found, jobs not submitted."; exit 1 ;;
    esac
    for NODE in {1..10}; do
        FOLDER_NAME="node_${NODE}"
        cd $FOLDER_NAME
        $SUBMIT_CMD $RUNSCRIPT_NAME
        cd ..
        echo "Submitted job in folder $FOLDER_NAME"
    done
fi
