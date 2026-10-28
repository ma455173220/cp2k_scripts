#!/bin/bash
# Extract one frame of a CP2K trajectory (<project>-pos-1.xyz) as a cif file (via Multiwfn).
# The cell is that of the same step in <project>-1.cell if that file exists (CELL_OPT/NPT runs),
# otherwise the &CELL of <project>.inp. Output: tmp.cif
#
# Usage: xyz2cif.sh file-pos-1.xyz [frame]     (frame = the "i =" step number; asked if not given)

# Shared helpers (cp2k_common.sh: next to this script, else in PATH)
_lib="$(dirname "$(readlink -f "$0")")/cp2k_common.sh"
[ -f "$_lib" ] || _lib="$(command -v cp2k_common.sh)" || { echo "Error: cp2k_common.sh not found (keep it next to this script or in PATH)" >&2; exit 1; }
source "$_lib"

if [ -z "$1" ] ; then
        echo -e "\033[31mERROR:\033[0m Missing file operand! Please identify the name of restart file!"
	echo -e "Format: xyz2cif.sh file-pos-1.xyz [frame]"
        exit 1
fi

cp2k_inp=$(find_script cp2k_inp.py) || exit 1

if [ -n "$2" ] ; then
	geometry_number=$2
else
	echo -e "Input the geometry you want to extract:"
	read geometry_number 
fi


line_number_xyz_file=`grep -n " ${geometry_number}," $1 | tail -1 | awk -F ':' '{print $1}'`
if [ -z "$line_number_xyz_file" ] ; then
	echo -e "\033[31mERROR:\033[0m Frame i = ${geometry_number} not found in $1"
	exit 1
fi
coord_top_line_number_xyz_file=`expr ${line_number_xyz_file} - 1`
number_of_atoms=`sed -n "${coord_top_line_number_xyz_file}p" $1 | sed s/[[:space:]]//g` 
coord_bottom_line_number_xyz_file=`expr ${coord_top_line_number_xyz_file} + ${number_of_atoms} + 1`

sed -n "${coord_top_line_number_xyz_file},${coord_bottom_line_number_xyz_file}p" $1 > tmp_coord.xyz

project_name=`echo $1 | awk -F "-pos" '{print $1}'`
input_file_name=${project_name}.inp
cell_file_name=${project_name}-1.cell

# Cell of this frame: from the .cell file (same step) if present, else from the input
if [ -f "$cell_file_name" ] ; then
	echo "Cell of step $geometry_number taken from $cell_file_name"
	"$cp2k_inp" get-cell "$cell_file_name" --step "$geometry_number" --format cp2k > tmp_cell || exit 1
else
	"$cp2k_inp" get-cell "$input_file_name" --format cp2k > tmp_cell || exit 1
fi

echo -e "tmp_coord.xyz\ncp2k\ntmp.inp\n0\nq" | Multiwfn 1>>/dev/null
if [ ! -s tmp.inp ] ; then
	echo -e "\033[31mERROR:\033[0m Multiwfn did not produce tmp.inp"
	rm -f tmp_cell tmp_coord.xyz
	exit 1
fi

# Put the cell into the input written by Multiwfn
"$cp2k_inp" replace-section tmp_cell tmp.inp CELL -i || exit 1

echo -e "tmp.inp\n100\n2\n33\n\n0\nq" | Multiwfn 1>>/dev/null


rm tmp_cell tmp_coord.xyz 
echo "Done!"

