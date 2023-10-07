#!/bin/bash
 
kpoints="2 3 4 5 6 7 8 9 10"
 
basis_file=BASIS_SET
potential_file=POTENTIAL
template_file=template.inp
input_file=Si_bulk.inp
run_script=cp2k_runscript
 
 

for ii in $kpoints ; do
    work_dir=kpoints_${ii}
    if [ ! -d $work_dir ] ; then
        mkdir $work_dir
    else
        rm -r $work_dir/*
    fi
    sed -e "s/LT_kpoints/${ii} ${ii} ${ii}/g" \
        $template_file > $work_dir/$input_file
    cp $basis_file $work_dir
    cp $potential_file $work_dir
    cp $run_script $work_dir
done
