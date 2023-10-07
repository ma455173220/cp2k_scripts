#!/bin/bash
### $1: neighdist.dat    $2: cp2k_outputfile ###
first_neigh=`seq 1 4`
second_neigh=`seq 5 16`
third_neigh=`seq 17 28`
fourth_neigh=`seq 29 34`
fifth_neigh=`seq 35 46`


output_file="hyperfine.ssv"
if [ -a $output_file ] ; then
	rm -rf $output_file
fi

echo -e "Atom index\tHyperfine (MHz)" >> $output_file
echo -e "===========================================================" >> $output_file
echo -e "First shell:" >> $output_file 
echo -e "-----------------------------------------------------------" >> $output_file
for i in $first_neigh ; do
	i=`expr $i + 1`
	atom_index=`sed -n "${i}p" $1 | awk -F ' ' '{print $2}'`
	atom_hyperfine=`grep "\s${atom_index} Si" $2 | tail -1 | awk -F ' ' '{print $NF}'`
	echo -e "  $atom_index\t$atom_hyperfine" >> $output_file
done
echo -e "===========================================================" >> $output_file


echo -e "Second shell:" >> $output_file
echo -e "-----------------------------------------------------------" >> $output_file
for i in $second_neigh ; do
	i=`expr $i + 1`
        atom_index=`sed -n "${i}p" $1 | awk -F ' ' '{print $2}'`
        atom_hyperfine=`grep "\s${atom_index} Si" $2 | tail -1 | awk -F ' ' '{print $NF}'`
        echo -e "  $atom_index\t$atom_hyperfine" >> $output_file
done
echo -e "===========================================================" >> $output_file

echo -e "Third shell:" >> $output_file
echo -e "-----------------------------------------------------------" >> $output_file
for i in $third_neigh ; do
	i=`expr $i + 1`
        atom_index=`sed -n "${i}p" $1 | awk -F ' ' '{print $2}'`
        atom_hyperfine=`grep "\s${atom_index} Si" $2 | tail -1 | awk -F ' ' '{print $NF}'`
        echo -e "  $atom_index\t$atom_hyperfine" >> $output_file
done
echo -e "===========================================================" >> $output_file

echo -e "Fourth shell:" >> $output_file
echo -e "-----------------------------------------------------------" >> $output_file
for i in $fourth_neigh ; do
	i=`expr $i + 1`
        atom_index=`sed -n "${i}p" $1 | awk -F ' ' '{print $2}'`
        atom_hyperfine=`grep "\s${atom_index} Si" $2 | tail -1 | awk -F ' ' '{print $NF}'`
        echo -e "  $atom_index\t$atom_hyperfine" >> $output_file
done
echo -e "===========================================================" >> $output_file

echo -e "Fifth shell:" >> $output_file
echo -e "-----------------------------------------------------------" >> $output_file
for i in $fifth_neigh ; do
	i=`expr $i + 1`
        atom_index=`sed -n "${i}p" $1 | awk -F ' ' '{print $2}'`
        atom_hyperfine=`grep "\s${atom_index} Si" $2 | tail -1 | awk -F ' ' '{print $NF}'`
        echo -e "  $atom_index\t$atom_hyperfine" >> $output_file
done
echo -e "===========================================================" >> $output_file


