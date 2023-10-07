#!/bin/bash
 
eps_schwarz="2 3 4 5 6 7 8"
 
#basis_file=GTH_BASIS_SETS
#potential_file=POTENTIAL
template_file=template.inp
input_file=Si_bulk.inp
run_script=cp2k_runscript
 
#rel_cutoff=80
 
for ii in $eps_schwarz ; do
    work_dir=eps_schwarz_${ii}
    if [ ! -d $work_dir ] ; then
        mkdir $work_dir
    else
        rm -r $work_dir/*
    fi
    sed -e "s/LT_eps_schwarz/1E-${ii}/g" \
        $template_file > $work_dir/$input_file
#    cp $basis_file $work_dir
#    cp $potential_file $work_dir
    cp $run_script $work_dir
done
