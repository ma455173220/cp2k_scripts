#!/bin/bash
#Must have pymatgen installed!

if [ -z "$1" ] ; then
                echo -e "\033[31mERROR:\033[0m Missing file operand! Please identify the name of input structure"
                        exit 1
fi

INPUT_FILE=$1
OUTPUT_FILE=${1%.*}.POSCAR
pmg structure --convert --filenames $INPUT_FILE $OUTPUT_FILE
echo "Done!"
