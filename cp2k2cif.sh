#!/bin/bash

if [ $1 ] ; then
	input_file=$1
else
	echo -e "\033[31mERROR:\033[0m Missing file operand! Please identify the name of geometry file!"
	exit 1
fi

echo -e "Choose the format of the output file:\n1.pdb\n2.xyz\n3.cif"
read output_format_choice

if [ $output_format_choice != 3 ] ; then
	echo -e "$1\n100\n2\n$output_format_choice\n\n0\nq" | Multiwfn 1>>/dev/null
else
	echo -e "$1\n100\n2\n33\n\n0\nq" | Multiwfn 1>>/dev/null
fi

