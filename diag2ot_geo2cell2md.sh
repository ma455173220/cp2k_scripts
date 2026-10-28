#!/bin/bash
# Switch a CP2K input to OT / DIAGONALIZATION (replaces &SCF) or to GEO_OPT / CELL_OPT / MD
# (RUN_TYPE and &MOTION), using the templates of Multiwfn. The input is edited in place (backup: .bak).
#
# Usage: diag2ot_geo2cell2md.sh target_file [ot|diag|geo|cell|md]   (or 1-5; no choice: menu)

# Function to display error message and usage instructions
display_error_and_exit() {
    echo -e "\033[31mERROR:\033[0m $1"
    echo -e "Format: ./diag2ot_geo2cell2md.sh target_file [ot|diag|geo|cell|md]"
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

# Shared helpers (cp2k_common.sh: next to this script, else in PATH)
_lib="$(dirname "$(readlink -f "$0")")/cp2k_common.sh"
[ -f "$_lib" ] || _lib="$(command -v cp2k_common.sh)" || { echo "Error: cp2k_common.sh not found (keep it next to this script or in PATH)" >&2; exit 1; }
source "$_lib"
cp2k_inp=$(find_script cp2k_inp.py) || exit 1

# Function to extract and replace sections: the section (DFT/SCF for &SCF, the top-level &MOTION) of the
# source file replaces the same section of the target file. cp2k_inp.py parses the input properly
# (case-insensitive, comments, bare &END, nesting) and fails without changing anything if the section
# is missing or not unique in either file.
function extract_and_replace_section {
    local section="$1"
    local start_marker="$2"
    local end_marker="$3"
    local src_file="$4"
    local target_file="$5"
    local path

    case "$start_marker" in
        "&SCF")    path="DFT/SCF" ;;
        "&MOTION") path="/MOTION" ;;
        *)         path="${start_marker#&}" ;;
    esac
    "$cp2k_inp" replace-section "$src_file" "$target_file" "$path" -o "${target_file}.new" \
        && mv "${target_file}.new" "$target_file"
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


# Select function type (second argument, or menu)
case "$(echo "${2:-}" | tr '[:upper:]' '[:lower:]')" in
    1|ot) function_choice=1 ;;
    2|diag|diagonalization) function_choice=2 ;;
    3|geo|geo_opt) function_choice=3 ;;
    4|cell|cell_opt) function_choice=4 ;;
    5|md) function_choice=5 ;;
    "")
        echo "Please select a function type:"
        echo "1. OT"
        echo "2. DIAGONALIZATION"
        echo "3. GEO_OPT"
        echo "4. CELL_OPT"
        echo "5. MD"

        read function_choice
        ;;
    *) display_error_and_exit "Unknown function type '$2' (ot, diag, geo, cell or md)." ;;
esac

Multiwfn_run $1
