#!/bin/bash
 
kpoints="2 3 4 5 6 7 8 9 10"

input_file=Si_bulk.inp
output_file=Si_bulk.out
run_script=cp2k_runscript
 

module load cp2k/7.1.0

for ii in $kpoints ; do
    work_dir=kpoints_${ii}
    if [ ! -d $work_dir ] ; then
            echo "$work_dir not exist!"
            exit
    else
            cd $work_dir
            /opt/pbs/default/bin/qsub $run_script
            echo "$work_dir: job submitted!"
#           cp2k.psmp -o Si_bulk.out -i $input_file & 
            cd ..
    fi
done
