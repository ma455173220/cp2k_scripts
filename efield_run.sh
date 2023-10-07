#!/bin/bash

efield="0 2E-7 4E-7 6E-7 8E-7 10E-7 12E-7"

template_file=cp2k.inp
input_file=cp2k.inp
run_script=$1


for ii in $efield ; do
    work_dir=efield_${ii}
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

