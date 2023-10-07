#!/bin/bash
#Must have pymatgen installed!

if [ $1 ] ; then
        INPUT_FILE=$1
else
        echo -e "\033[31mERROR:\033[0m Missing file operand! Please identify the name of geometry file!"
        exit 1
fi

echo -e "$1\n100\n2\n27\n\n0\nq" | Multiwfn 1>>/dev/null

#INPUT_FILE=${1%.*}.cif
#OUTPUT_FILE=${1%.*}.POSCAR
#pmg structure --convert --filenames $INPUT_FILE $OUTPUT_FILE
echo "Done!"
