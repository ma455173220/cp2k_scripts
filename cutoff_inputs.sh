#!/bin/bash
 
cutoffs="50 100 150 200 250 300 350 400 450 500 550 600 650 700 750 800 850 900 950 1000 1200 1500 2000"
 
template_file=cp2k.inp
input_file=cp2k.inp
run_script=test
 
rel_cutoff=60
 
for ii in $cutoffs ; do
    work_dir=cutoff_${ii}Ry
    if [ ! -d $work_dir ] ; then
        mkdir $work_dir
    else
        rm -rf $work_dir/*
    fi
    sed -e "s/LT_cutoff/${ii}/g" \
        $template_file > $work_dir/$input_file
    cp $run_script $work_dir
done
