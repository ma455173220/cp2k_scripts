#!/bin/bash
 
rel_cutoffs="10 20 30 40 50 60 70 80 90 100"
 
input_file=cp2k.inp
output_file=cp2k.out
run_script=test
 

for ii in $rel_cutoffs ; do
    work_dir=rel_cutoff_${ii}Ry
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
