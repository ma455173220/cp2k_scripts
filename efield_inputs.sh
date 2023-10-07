#!/bin/bash
 
efield="0 2E-7 4E-7 6E-7 8E-7 10E-7 12E-7"
 
template_file=cp2k.inp
input_file=cp2k.inp
run_script=$1
 
 
for ii in $efield ; do
    work_dir=efield_${ii}
    if [ ! -d $work_dir ] ; then
        mkdir $work_dir
    else
        rm -rf $work_dir/*
    fi
    sed -e "s/LT_EFIELD/${ii}/g" \
        $template_file > $work_dir/$input_file
    cp $run_script $work_dir
done
