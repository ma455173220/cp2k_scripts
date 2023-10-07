#!/bin/bash

if [ -z "$1" ] ; then
        echo -e "\033[31mERROR:\033[0m Missing file operand! Please identify the name of restart file!"
	echo -e "Format: xyz2cif.sh file-pos-1.xyz"
        exit 1
fi

echo -e "Input the geometry you want to extract:"
read geometry_number 


line_number_xyz_file=`grep -n " ${geometry_number}," $1 | tail -1 | awk -F ':' '{print $1}'`
coord_top_line_number_xyz_file=`expr ${line_number_xyz_file} - 1`
number_of_atoms=`sed -n "${coord_top_line_number_xyz_file}p" $1 | sed s/[[:space:]]//g` 
coord_bottom_line_number_xyz_file=`expr ${coord_top_line_number_xyz_file} + ${number_of_atoms} + 1`

sed -n "${coord_top_line_number_xyz_file},${coord_bottom_line_number_xyz_file}p" $1 > tmp_coord.xyz

project_name=`echo $1 | awk -F "-pos" '{print $1}'`
input_file_name=${project_name}.inp

cell_top_line_number=`grep -n "&CELL\$" ${input_file_name} | grep -v "#" | head -1 | awk -F ':' '{print $1}'`
cell_bottom_line_number=`grep -n "CELL\$" ${input_file_name} | grep -v "#" | tail -1 | awk -F ':' '{print $1}'`
sed -n "${cell_top_line_number},${cell_bottom_line_number}p" ${input_file_name} > tmp_cell

echo -e "tmp_coord.xyz\ncp2k\ntmp.inp\n0\nq" | Multiwfn 1>>/dev/null

target_cell_top_line_number=`grep -n "&CELL\$" tmp.inp | grep -v "#" | head -1 | awk -F ':' '{print $1}'`
target_cell_bottom_line_number=`grep -n "CELL\$" tmp.inp | grep -v "#" | tail -1 | awk -F ':' '{print $1}'`

sed -i "${target_cell_top_line_number},${target_cell_bottom_line_number}d" tmp.inp
new_cell_line_number=`expr ${target_cell_top_line_number} - 1`
sed -i "${new_cell_line_number}r tmp_cell" tmp.inp

echo -e "tmp.inp\n100\n2\n33\n\n0\nq" | Multiwfn 1>>/dev/null


rm tmp_cell tmp_coord.xyz 
echo "Done!"

