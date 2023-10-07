#!/bin/bash
 
rel_cutoffs="10 20 30 40 50 60 70 80 90 100"
 
template_file=cp2k.inp
input_file=cp2k.inp
run_script=test
 
 
for ii in $rel_cutoffs ; do
    work_dir=rel_cutoff_${ii}Ry
    if [ ! -d $work_dir ] ; then
        mkdir $work_dir
    else
        rm -r $work_dir/*
    fi
    sed -e "s/LT_rel_cutoff/${ii}/g" \
        $template_file > $work_dir/$input_file
    cp $run_script $work_dir
done
