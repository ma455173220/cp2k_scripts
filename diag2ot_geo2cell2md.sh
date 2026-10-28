#!/bin/bash

# Function to display error message and usage instructions
display_error_and_exit() {
    echo -e "\033[31mERROR:\033[0m $1"
    echo -e "Format: ./diag2ot_geo2cell2md.sh target_file"
    exit 1
}

# Check if source file exists
if [ ! -f "$1" ]; then
    display_error_and_exit "Target file '$1' not found."
fi

# Check that Multiwfn is available before anything is changed
if ! command -v Multiwfn >/dev/null 2>&1; then
    display_error_and_exit "Multiwfn not found in PATH (load or install it first)."
fi

# Print the line numbers of the lines that consist of the given marker (e.g. "&SCF" or "&END SCF").
# Case-insensitive; whitespace and trailing "#"/"!" comments are ignored; commented-out lines never match.
marker_lines() {
    awk -v m="$2" '
        { line = $0
          sub(/[#!].*$/, "", line)
          gsub(/^[ \t]+|[ \t\r]+$/, "", line)
          gsub(/[ \t]+/, " ", line)
          if (toupper(line) == toupper(m)) print NR }' "$1"
}

# Exactly one line number for a marker, otherwise an error message (and non-zero status)
unique_marker_line() {
    local lines count
    lines=$(marker_lines "$1" "$2")
    count=$(printf '%s' "$lines" | grep -c .)
    if [ "$count" -ne 1 ]; then
        echo -e "\033[31mERROR:\033[0m '$2' found $count times in '$1' (expected exactly once); '$1' was not changed." >&2
        return 1
    fi
    echo "$lines"
}

# Function to extract and replace sections
function extract_and_replace_section {
    local section="$1"
    local start_marker="$2"
    local end_marker="$3"
    local src_file="$4"
    local target_file="$5"
    local src_start_line src_end_line target_start_line target_end_line

    src_start_line=$(unique_marker_line "$src_file" "$start_marker") || return 1
    src_end_line=$(unique_marker_line "$src_file" "$end_marker") || return 1
    target_start_line=$(unique_marker_line "$target_file" "$start_marker") || return 1
    target_end_line=$(unique_marker_line "$target_file" "$end_marker") || return 1

    # Extracting the section from the source file
    sed -n "${src_start_line},${src_end_line}p" "$src_file" > tmp_${section}

    # Replacing the existing section of the target file with the new one
    awk -v s="$target_start_line" -v e="$target_end_line" -v f="tmp_${section}" '
        NR == s { while ((getline l < f) > 0) print l }
        NR >= s && NR <= e { next }
        { print }' "$target_file" > "${target_file}.new" && mv "${target_file}.new" "$target_file"

    # Removing the temporary file
    rm "tmp_${section}"
}

# Set a function
function Multiwfn_run (){
    local Multiwfn_function_choice section start_marker end_marker

    # Back up the input before it is modified (restored if anything below fails)
    cp -p "$1" "$1.bak"

    case "$function_choice" in
        1)
            Multiwfn_function_choice="4"
            section="SCF"
            start_marker="&SCF"
            end_marker="&END SCF"
            ;;
        2)
            Multiwfn_function_choice=$'\n'
            section="SCF"
            start_marker="&SCF"
            end_marker="&END SCF"
            ;;
        3)
            Multiwfn_function_choice="-1\n3"
            section="OPT"
            start_marker="&MOTION"
            end_marker="&END MOTION"
            sed -i 's/\(RUN_TYPE\).*/\1 GEO_OPT/' "$1"
            sed -i '/STRESS_TENSOR/d' "$1"
            ;;
        4)
            Multiwfn_function_choice="-1\n4"
            section="OPT"
            start_marker="&MOTION"
            end_marker="&END MOTION"
            sed -i 's/\(RUN_TYPE\).*/\1 CELL_OPT/' "$1"
            # Only add STRESS_TENSOR if there is no active one already (a repeated keyword is a CP2K input error)
            if ! grep -qiE '^[[:space:]]*STRESS_TENSOR' "$1"; then
                sed -i '/&END FORCE_EVAL/i STRESS_TENSOR ANALYTICAL #Compute full stress tensor analytically' "$1"
            fi
            ;;
        5)
            Multiwfn_function_choice="-1\n6\n10\n2"
            section="MD"
            start_marker="&MOTION"
            end_marker="&END MOTION"
            sed -i 's/\(RUN_TYPE\).*/\1 MD/' "$1"
            sed -i '/STRESS_TENSOR/d' "$1"
            ;;
        *)
            echo "Invalid choice"
            exit 1
            ;;
    esac


	# Run Multiwfn 
	rm -f temp.inp
	echo -e "$1\ncp2k\ntemp.inp\n$Multiwfn_function_choice\n0\nq" | Multiwfn 1>>/dev/null
	if [ ! -s temp.inp ]; then
	    mv "$1.bak" "$1"
	    display_error_and_exit "Multiwfn did not produce temp.inp; '$1' was not changed."
	fi

    if ! extract_and_replace_section "$section" "$start_marker" "$end_marker" "temp.inp" "$1"; then
        mv "$1.bak" "$1"
        rm -f temp.inp
        exit 1
    fi

	rm temp.inp
	echo "Done! (backup: $1.bak)"
}


# Select function type
echo "Please select a function type:"
echo "1. OT"
echo "2. DIAGONALIZATION"
echo "3. GEO_OPT"
echo "4. CELL_OPT"
echo "5. MD"

read function_choice

Multiwfn_run $1
