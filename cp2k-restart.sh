#!/bin/bash

# Function to display error message and usage instructions
display_error_and_exit() {
    echo -e "\033[31mERROR:\033[0m $1" >&2
    echo -e "Format: cp2k-restart.sh restart_file input_file" >&2
    exit 1
}

# Abort without touching the target file
abort() {
    echo -e "\033[31mERROR:\033[0m $1" >&2
    echo "Nothing was changed in '$target_file'." >&2
    exit 1
}

warn() {
    echo -e "\033[33mWARNING:\033[0m $1" >&2
}

# Check if required arguments are provided
if [ $# -ne 2 ]; then
    display_error_and_exit "Missing file operand! Please identify the name of restart and target files."
fi

# Check if restart file exists
if [ ! -f "$1" ]; then
    display_error_and_exit "Restart file '$1' not found."
fi

# Check if target file exists
if [ ! -f "$2" ]; then
    display_error_and_exit "Target file '$2' not found."
fi

restart_file="$1"
target_file="$2"

# All edits are made on a copy; the target is only replaced (after writing a .bak) if every step succeeded
work_file=$(mktemp "${target_file}.tmp.XXXXXX") || display_error_and_exit "Cannot create a temporary file next to '$target_file'."
section_tmp=$(mktemp) || display_error_and_exit "Cannot create a temporary file."
trap 'rm -f "$work_file" "$section_tmp"' EXIT
cp "$target_file" "$work_file"

# Print the line numbers of the lines that consist of the given marker (e.g. "&CELL" or "&END CELL").
# Case-insensitive; leading/trailing whitespace and trailing "#"/"!" comments are ignored;
# commented-out lines (first non-space character "#" or "!") never match.
marker_lines() {
    awk -v m="$2" '
        { line = $0
          sub(/[#!].*$/, "", line)
          gsub(/^[ \t]+|[ \t\r]+$/, "", line)
          gsub(/[ \t]+/, " ", line)
          if (toupper(line) == toupper(m)) print NR }' "$1"
}

# Print the line numbers of the active (not commented-out) lines whose first word is the given keyword
keyword_lines() {
    awk -v k="$2" '
        { line = $0
          sub(/[#!].*$/, "", line)
          n = split(line, w, /[ \t]+/)
          first = (w[1] == "" ? w[2] : w[1])
          if (toupper(first) == toupper(k)) print NR }' "$1"
}

# Return exactly one line number for a marker, or abort if it is missing or ambiguous
unique_marker_line() {
    local file="$1" marker="$2" label="$3" lines count hint=""
    lines=$(marker_lines "$file" "$marker")
    count=$(printf '%s' "$lines" | grep -c .)
    if [ "$count" -eq 0 ]; then
        case "$marker" in "&END "*) hint=" (a bare '&END' has to be written as '$marker')" ;; esac
        abort "'$marker' not found in $label$hint."
    elif [ "$count" -gt 1 ]; then
        abort "'$marker' found $count times in $label (lines $(echo $lines | tr ' ' ',')); cannot tell which one to use."
    fi
    echo "$lines"
}

# Replace the lines start..end of the work file with the content of $section_tmp
splice_section() {
    local start="$1" end="$2"
    awk -v s="$start" -v e="$end" -v f="$section_tmp" '
        NR == s { while ((getline l < f) > 0) print l }
        NR >= s && NR <= e { next }
        { print }' "$work_file" > "${work_file}.new" && mv "${work_file}.new" "$work_file"
}

# Function to extract and replace sections
function extract_and_replace_section {
    local section="$1"
    local start_marker="$2"
    local end_marker="$3"
    local src_file="$4"
    local src_start_line src_end_line target_start_line target_end_line

    src_start_line=$(unique_marker_line "$src_file" "$start_marker" "restart file '$src_file'") || exit 1
    src_end_line=$(unique_marker_line "$src_file" "$end_marker" "restart file '$src_file'") || exit 1
    target_start_line=$(unique_marker_line "$work_file" "$start_marker" "target file '$target_file'") || exit 1
    target_end_line=$(unique_marker_line "$work_file" "$end_marker" "target file '$target_file'") || exit 1

    if [ "$src_start_line" -ge "$src_end_line" ] || [ "$target_start_line" -ge "$target_end_line" ]; then
        abort "'$start_marker' does not come before '$end_marker' (section $section)."
    fi

    # Extracting the section from the source file
    sed -n "${src_start_line},${src_end_line}p" "$src_file" > "$section_tmp"

    # Replacing the existing section of the target file with the new one
    splice_section "$target_start_line" "$target_end_line"
}

# Function to extract velocity from one file and replace it in another file
extract_replace_velocity() {
    local src_file="$1"

    if [ -z "$(marker_lines "$src_file" "&VELOCITY")" ]; then
        warn "No &VELOCITY section in '$src_file'; velocities not copied."
        return 0
    fi

    # Checking if the target file contains a velocity section
    if [ -n "$(marker_lines "$work_file" "&VELOCITY")" ]; then
        extract_and_replace_section "VELOCITY" "&VELOCITY" "&END VELOCITY" "$src_file"
    else
        # If the target file doesn't contain a velocity section, append the velocity at the end of COORD block
        local src_start_line src_end_line new_velocity_line_number
        src_start_line=$(unique_marker_line "$src_file" "&VELOCITY" "restart file '$src_file'") || exit 1
        src_end_line=$(unique_marker_line "$src_file" "&END VELOCITY" "restart file '$src_file'") || exit 1
        new_velocity_line_number=$(unique_marker_line "$work_file" "&END COORD" "target file '$target_file'") || exit 1

        # Extracting the section from the source file
        sed -n "${src_start_line},${src_end_line}p" "$src_file" > "$section_tmp"

        # Inserting the new section after the end of the COORD block
        awk -v n="$new_velocity_line_number" -v f="$section_tmp" '
            { print }
            NR == n { while ((getline l < f) > 0) print l }' "$work_file" > "${work_file}.new" && mv "${work_file}.new" "$work_file"
    fi
}

# Copy STEP_START_VAL from the restart file (replace it in the target, or add it after RMS_FORCE)
copy_step_start_val() {
    local src_file="$1" src_lines src_count target_lines target_count rms_lines rms_count src_step_start_val
    src_lines=$(keyword_lines "$src_file" "STEP_START_VAL")
    src_count=$(printf '%s' "$src_lines" | grep -c .)
    [ "$src_count" -eq 0 ] && return 0
    if [ "$src_count" -gt 1 ]; then
        # This happens when the restart file has e.g. both GEO_OPT and MD sections
        warn "STEP_START_VAL found $src_count times in '$src_file'; STEP_START_VAL not copied."
        return 0
    fi
    src_step_start_val=$(sed -n "${src_lines}p" "$src_file")

    target_lines=$(keyword_lines "$work_file" "STEP_START_VAL")
    target_count=$(printf '%s' "$target_lines" | grep -c .)
    if [ "$target_count" -eq 1 ]; then
        # Replacing the STEP_START_VAL in the target file if it already exists
        awk -v n="$target_lines" -v txt="$src_step_start_val" 'NR == n { print txt; next } { print }' \
            "$work_file" > "${work_file}.new" && mv "${work_file}.new" "$work_file"
    elif [ "$target_count" -gt 1 ]; then
        warn "STEP_START_VAL found $target_count times in '$target_file'; STEP_START_VAL not updated."
    else
        # If STEP_START_VAL doesn't exist in the target file, adding it after RMS_FORCE
        rms_lines=$(keyword_lines "$work_file" "RMS_FORCE")
        rms_count=$(printf '%s' "$rms_lines" | grep -c .)
        if [ "$rms_count" -eq 1 ]; then
            awk -v n="$rms_lines" -v txt="$src_step_start_val" '{ print } NR == n { print txt }' \
                "$work_file" > "${work_file}.new" && mv "${work_file}.new" "$work_file"
        else
            warn "No unique RMS_FORCE line in '$target_file' to put STEP_START_VAL after; please add '$(echo $src_step_start_val)' to the optimizer section yourself."
        fi
    fi
}

# RUN_TYPE of a file (upper case), ignoring commented-out lines
run_type() {
    awk '{ line = $0; sub(/[#!].*$/, "", line); n = split(line, w, /[ \t]+/)
           first = (w[1] == "" ? w[2] : w[1]); second = (w[1] == "" ? w[3] : w[2])
           if (toupper(first) == "RUN_TYPE") rt = toupper(second) }
         END { print rt }' "$1"
}

check_RUNTYPE_restart=$(run_type "$restart_file")
check_RUNTYPE_target=$(run_type "$target_file")
if [ "$check_RUNTYPE_restart" == "MD" ] && [ "$check_RUNTYPE_target" == "MD" ]; then
    extract_and_replace_section "CELL" "&CELL" "&END CELL" "$restart_file"
    extract_and_replace_section "COORD" "&COORD" "&END COORD" "$restart_file"
    extract_and_replace_section "MD" "&MD" "&END MD" "$restart_file"
    extract_replace_velocity "$restart_file"
elif [ "$check_RUNTYPE_restart" == "MD" ] && [ "$check_RUNTYPE_target" != "MD" ]; then
    extract_and_replace_section "CELL" "&CELL" "&END CELL" "$restart_file"
    extract_and_replace_section "COORD" "&COORD" "&END COORD" "$restart_file"
elif [ "$check_RUNTYPE_restart" != "MD" ] && [ "$check_RUNTYPE_target" == "MD" ]; then
    extract_and_replace_section "CELL" "&CELL" "&END CELL" "$restart_file"
    extract_and_replace_section "COORD" "&COORD" "&END COORD" "$restart_file"
elif [ "$check_RUNTYPE_restart" == "BAND" ] && [ "$check_RUNTYPE_target" == "BAND" ]; then
    extract_and_replace_section "BAND" "&BAND" "&END BAND" "$restart_file"
elif [ "$check_RUNTYPE_restart" != "MD" ] && [ "$check_RUNTYPE_target" == "BAND" ]; then
    extract_and_replace_section "CELL" "&CELL" "&END CELL" "$restart_file"
    extract_and_replace_section "COORD" "&COORD" "&END COORD" "$restart_file"
else
    extract_and_replace_section "CELL" "&CELL" "&END CELL" "$restart_file"
    extract_and_replace_section "COORD" "&COORD" "&END COORD" "$restart_file"
    copy_step_start_val "$restart_file"
fi

# Every step succeeded: keep a backup and replace the target
cp -p "$target_file" "${target_file}.bak" || abort "Cannot write backup '${target_file}.bak'."
cat "$work_file" > "$target_file"
echo "Done! (backup: ${target_file}.bak)"
