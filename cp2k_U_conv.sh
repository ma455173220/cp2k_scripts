#!/bin/bash

##Input parameters
input_file=cp2k.inp   #Template file of present system      
output_file=cp2k.out                                        
restart_file="cp2k-1.restart"
run_script=NBT                                              
plot_file="U.txt"                                                            

U_values=$(seq 1 0.5 6) #Considered U range and step

prepare_input_files() {
    for ii in $U_values ; do
        work_dir=U_${ii}
        if [ ! -d $work_dir ] ; then
            mkdir $work_dir
        else 
            echo "Directory '$work_dir' already exists. Do you want to delete existing files? (y/n)"
            read response
            if [ "$response" == "Y" ] || [ "$response" == "y" ]; then
                rm -r $work_dir/*
            else
                echo "Skipping deletion of existing files in '$work_dir'."
                continue  
            fi
        fi

        sed -e "s/LT_U/${ii}/g" $input_file > $work_dir/$input_file
        cp $run_script $work_dir

    done
}

# Detect the batch scheduler (PBS on Gadi, Slurm on Setonix)
detect_scheduler() {
    if command -v qsub >/dev/null 2>&1; then
        echo "pbs"
    elif command -v sbatch >/dev/null 2>&1; then
        echo "slurm"
    else
        echo "none"
    fi
}

run_input_files() {
    case "$(detect_scheduler)" in
        pbs)
            submit_cmd="qsub"
            [ -x /opt/pbs/default/bin/qsub ] && submit_cmd="/opt/pbs/default/bin/qsub"
            ;;
        slurm) submit_cmd="sbatch" ;;
        *) echo "Neither qsub nor sbatch found, cannot submit jobs."; exit 1 ;;
    esac
    for ii in $U_values ; do
        work_dir=U_${ii}
        if [ ! -d $work_dir ] ; then
            echo "$work_dir not exist!"
            exit
        else
            cd $work_dir
            $submit_cmd $run_script
            echo "$work_dir: job submitted!"
            cd ..
        fi
    done
}

# Print the lengths |A| |B| |C| (in Angstrom) of the &CELL section of a CP2K input/restart file.
# Handles A/B/C vectors (any orientation) and ABC; prints an error message instead if neither is found.
cell_lengths() {
    awk '
        { line = $0; sub(/[#!].*$/, "", line); gsub(/^[ \t]+|[ \t\r]+$/, "", line); gsub(/[ \t]+/, " ", line)
          if (line == "") next
          u = toupper(line)
          if (!inside) { if (u == "&CELL") inside = 1; next }
          if (u ~ /^&END/) { if (depth == 0) exit; depth--; next }
          if (u ~ /^&/) { depth++; next }           # skip nested sections such as &CELL_REF
          if (depth > 0) next
          n = split(line, w, " "); k = toupper(w[1]); i = 2; scale = 1
          if (w[2] ~ /^\[/) { if (tolower(w[2]) == "[bohr]") scale = 0.529177210903; i = 3 }
          if (k == "A" || k == "B" || k == "C") len[k] = scale * sqrt(w[i]^2 + w[i+1]^2 + w[i+2]^2)
          if (k == "ABC") { len["A"] = scale * w[i]; len["B"] = scale * w[i+1]; len["C"] = scale * w[i+2] }
        }
        END {
          if (!inside) { print "ERROR: no &CELL section"; exit }
          if (len["A"] == "" || len["B"] == "" || len["C"] == "") { print "ERROR: no A/B/C or ABC lines in &CELL"; exit }
          if (len["A"] + 0 <= 0 || len["B"] + 0 <= 0 || len["C"] + 0 <= 0) { print "ERROR: zero or non-numeric cell length (variables like ${a} are not supported)"; exit }
          printf "%.10f %.10f %.10f\n", len["A"], len["B"], len["C"]
        }' "$1"
}

analysis() {
    echo "# U vs lattice parameters" > $plot_file
    echo "# Date: $(date)" >> $plot_file
    echo "# PWD: $PWD" >> $plot_file
    echo -e "#  U  |   A   |   B   |   C   |   delta_A(%)   |   delta_B(%)   |   delta_C(%)" >> $plot_file
    for ii in $U_values ; do
        work_dir=U_${ii}
        check_job=$(grep "PROGRAM ENDED AT" $work_dir/$output_file)
        ref_cell=""; new_cell=""
        if [ -n "$check_job" ]; then
            ref_cell=$(cell_lengths $work_dir/$input_file)
            new_cell=$(cell_lengths $work_dir/$restart_file 2>/dev/null)
            for cell_check in "$work_dir/$input_file:$ref_cell" "$work_dir/$restart_file:$new_cell"; do
                case "${cell_check#*:}" in
                    ""|ERROR*) echo "Warning: ${cell_check%%:*}: ${cell_check#*:}" >&2; check_job="" ;;
                esac
            done
        fi
        if [ -n "$check_job" ]; then
            # Lattice constants are the lengths of the cell vectors (correct for non-orthogonal cells too)
            read A_ref B_ref C_ref <<< "$ref_cell"
            read A_value B_value C_value <<< "$new_cell"
            delta_A=$(echo "scale=6; (($A_value - $A_ref) / $A_ref) * 100" | bc)
            delta_B=$(echo "scale=6; (($B_value - $B_ref) / $B_ref) * 100" | bc)
            delta_C=$(echo "scale=6; (($C_value - $C_ref) / $C_ref) * 100" | bc)
            printf "%3.2f %11.6f %11.6f %11.6f %11.6f %11.6f %11.6f" \
                $ii $A_value $B_value $C_value $delta_A $delta_B $delta_C >> $plot_file
        else
            printf "%3.2f      N/A         N/A         N/A         N/A         N/A         N/A" $ii >> $plot_file
        fi
        printf "\n" >> $plot_file
    done
    echo "If finished normally, now check $plot_file"
}


echo "Choose an option:"
echo "1. Prepare input files"
echo "2. Run input files"
echo "3. Analysis"
read -p "Enter your choice (1/2/3): " choice

case $choice in
    1)
        prepare_input_files
        ;;
    2)
        run_input_files
        ;;
    3)
        analysis
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

