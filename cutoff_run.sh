#!/bin/bash

cutoffs="50 100 150 200 250 300 350 400 450 500 550 600 650 700 750 800 850 900 950 1000 1200 1500 2000"

template_file=cp2k.inp
input_file=cp2k.inp
run_script=test

for ii in $cutoffs ; do
    work_dir=cutoff_${ii}Ry
    if [ ! -d $work_dir ] ; then
	    echo "$work_dir not exist!"
	    exit
    else
	    cd $work_dir
	    /opt/pbs/default/bin/qsub $run_script
	    echo "$work_dir: job submitted!"
#	    cp2k.psmp -o Si_bulk.out -i $input_file & 
	    cd ..
    fi
done

