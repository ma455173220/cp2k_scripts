#!/bin/bash

# Convert a geometry file (CP2K input, xyz, ...) with Multiwfn.
# Usage: cp2k2cif.sh geometry_file [poscar|cif|pdb|xyz]   (or 1-4; no format: menu)

if [ "$1" ]; then
    input_file="$1"
else
    echo -e "\033[31mERROR:\033[0m Missing file operand! Please identify the name of the geometry file!"
    exit 1
fi

if [ -n "$2" ]; then
    output_format_choice=$(echo "$2" | tr '[:upper:]' '[:lower:]')
else
    echo -e "Choose the format of the output file:\n1. POSCAR \n2. cif \n3. pdb\n4. xyz"
    read -p "Enter your choice: " output_format_choice
fi

case $output_format_choice in
    1|poscar|vasp)
        output_format=27
        ;;
    2|cif)
        output_format=33
        ;;
    3|pdb)
        output_format=1
        ;;
    4|xyz)
        output_format=2
        ;;
    *)
        echo -e "\033[31mERROR:\033[0m Invalid choice!"
        exit 1
        ;;
esac

echo -e "$input_file\n100\n2\n$output_format\n\n0\nq" | Multiwfn 1>>/dev/null

echo "Done!"
