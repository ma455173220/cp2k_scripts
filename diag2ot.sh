#!/bin/bash

# Define color codes
GREEN='\033[1;32m'
ORANGE='\033[1;33m'

# Function to display error message and usage instructions
display_error_and_exit() {
    echo -e "\033[31mERROR:\033[0m $1"
    echo -e "Format: ./diag2ot.sh target_file"
    exit 1
}

# Check if source file exists
if [ ! -f "$1" ]; then
    display_error_and_exit "Target file '$1' not found."
fi

# Function to extract and replace sections
function extract_and_replace_section {
    local section="$1"
    local start_marker="$2"
    local end_marker="$3"
    local src_file="$4"
    local target_file="$5"

    local src_start_line=$(grep -n "${start_marker}\$" "$src_file" | grep -v "#" | head -1 | awk -F ':' '{print $1}')
    local src_end_line=$(grep -n "${end_marker}\$" "$src_file" | grep -v "#" | tail -1 | awk -F ':' '{print $1}')

    local target_start_line=$(grep -n "${start_marker}\$" "$target_file" | grep -v "#" | head -1 | awk -F ':' '{print $1}')
    local target_end_line=$(grep -n "${end_marker}\$" "$target_file" | grep -v "#" | tail -1 | awk -F ':' '{print $1}')

    # Extracting the section from the source file
    sed -n "${src_start_line},${src_end_line}p" "$src_file" > tmp_${section}

    # Deleting the existing section from the target file
    sed -i "${target_start_line},${target_end_line}d" "$target_file"

    # Inserting the new section from the temporary file into the target file
    new_line_number=$(expr "${target_start_line}" - 1)
    sed -i "${new_line_number}r tmp_${section}" "$target_file"

    # Removing the temporary file
    rm "tmp_${section}"
}

# Set a function
function Multiwfn_run (){

	if [ $function_choice -eq 1 ]
	then
		Multiwfn_function_choice=4
	else
		Multiwfn_function_choice=" "
	fi

	# Run Multiwfn 
	echo -e "${GREEN}Function starts..."
	echo -e "${GREEN}Running Multiwfn..."
	echo -e "$1\ncp2k\ntemp.inp\n$Multiwfn_function_choice\n0\nq" | Multiwfn 1>>/dev/null

    extract_and_replace_section "SCF" "&SCF" "&END SCF" "temp.inp" $1

	rm temp.inp
	echo -e "${GREEN}Done!"

}


# Select function type
echo "Please select a function type:"
echo "1. OT"
echo "2. DIAGONALIZATION"

read function_choice

case $function_choice in
	1 | 2)
		Multiwfn_run $1
		;;
	*)
		echo "Invalid option selected."
		;;
esac
