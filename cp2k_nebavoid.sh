#!/bin/bash
# NEB images with VASPKIT: 1) every numbered xyz image -> <NN>/POSCAR (cell from cp2k.inp);
# 2) after processing the POSCARs with atomkit, convert them back and merge all images into traj.xyz.
#
# Usage: cp2k_nebavoid.sh [1|xyz2poscar | 2|poscar2xyz]     (no argument: menu)

# Shared helpers (cp2k_common.sh: next to this script, else in PATH)
_lib="$(dirname "$(readlink -f "$0")")/cp2k_common.sh"
[ -f "$_lib" ] || _lib="$(command -v cp2k_common.sh)" || { echo "Error: cp2k_common.sh not found (keep it next to this script or in PATH)" >&2; exit 1; }
source "$_lib"

# Function to get lattice parameters
get_lattice_parameters() {
  if [ ! -f cp2k.inp ]; then
    echo "Error: The file 'cp2k.inp' does not exist."
    exit 1
  fi

  # Cell vectors of the &CELL section (A/B/C or ABC [+ ALPHA_BETA_GAMMA], units, comments, nested
  # &CELL_REF and &CELL_OPT are all handled by cp2k_inp.py), one " x y z" line per vector
  local cp2k_inp
  cp2k_inp=$(find_script cp2k_inp.py) || exit 1
  if ! lattice_parameter=$("$cp2k_inp" get-cell cp2k.inp --format vectors --fmt .16g | sed 's/^/ /'); then
    echo "Error: Could not extract lattice parameters (A/B/C or ABC) from the &CELL section of 'cp2k.inp'."
    exit 1
  fi
  if [ "$(printf '%s\n' "$lattice_parameter" | grep -c .)" -ne 3 ]; then
    echo "Error: Could not extract lattice parameters (A/B/C or ABC) from the &CELL section of 'cp2k.inp'."
    exit 1
  fi
}

# Numbered images are stored in two-digit, zero-based directories (00, 01, ...).
# xyz2neb.pl numbers the images from 0 (0.xyz ... N.xyz); image sets numbered from 1 are shifted by 1.
if ls *.xyz 2>/dev/null | grep -qE '^0+\.xyz$'; then
  image_offset=0
else
  image_offset=1
fi

# Function to process .xyz files and generate POSCAR
xyz_to_POSCAR() {
  echo "Starting conversion from .xyz to POSCAR files..."
  # Loop through all .xyz files in the current directory
  for file in *.xyz; do
    # Check if .xyz file is empty
    if [ ! -s "$file" ]; then
      echo "Warning: '$file' is empty and will be skipped."
      continue
    fi

    # Extract the prefix of the .xyz file
    prefix="${file%.xyz}"

    # Check if the prefix is a number
    if [[ $prefix =~ ^[0-9]+$ ]]; then
      # Convert the prefix to a two-digit, zero-based image number
      new_prefix=$(printf "%02d" $((10#$prefix - image_offset)))
    else
      # Use the prefix as is if it's not a number
      new_prefix="$prefix"
    fi

    # Extract the number of atoms from the first line of the .xyz file
    num_atoms=$(head -n 1 "$file")

    # Check if the directory with the new prefix name exists, if not, create it
    if [ ! -d "$new_prefix" ]; then
      mkdir "$new_prefix"
    fi

    # Remove the first two lines of the .xyz file and save the result in a temporary file
    tail -n +3 "$file" > "${file}.tmp"
    
    # Extract the first column from the temporary file and save it
    awk '{print $1}' "${file}.tmp" > "$new_prefix/${file%.xyz}_first_column.txt"
    
    # Remove the first column from the temporary file and save the result back to the target file
    awk '{$1=""; print $0}' "${file}.tmp" > "$new_prefix/${file%.xyz}.xyz"
    
    # Remove the temporary file
    rm "${file}.tmp"

    # Create the final POSCAR file
    {
      echo "Input file generated from $file"
      echo "1.0"
      printf "%s\n" "$lattice_parameter"
      echo "C"
      echo "$num_atoms"
      echo "Cartesian"
      cat "$new_prefix/${file%.xyz}.xyz"
    } > "$new_prefix/POSCAR"

    echo "POSCAR file created for $file in directory $new_prefix."

    # Remove the temporary xyz file
    rm "$new_prefix/${file%.xyz}.xyz"
  done
}

# Function to convert POSCAR files back to .xyz format
POSCAR_to_xyz() {
  echo "Starting conversion from POSCAR to .xyz files..."
  for file in *.xyz; do
    # Check if .xyz file is empty
    if [ ! -s "$file" ]; then
      echo "Warning: '$file' is empty and will be skipped."
      continue
    fi

    # Extract the prefix of the .xyz file
    prefix="${file%.xyz}"

    # Check if the prefix is a number
    if [[ $prefix =~ ^[0-9]+$ ]]; then
      # Convert the prefix to a two-digit, zero-based image number
      new_prefix=$(printf "%02d" $((10#$prefix - image_offset)))
    else
      # Skip this iteration if prefix is not a number
      echo "Warning: '$file' does not have a numeric prefix and will be skipped."
      continue
    fi

    # Check if the directory with the new prefix name exists
    if [ ! -d "$new_prefix" ]; then
      echo "Error: Directory '$new_prefix' does not exist."
      exit 1
    fi

    # Extract the number of atoms from the first line of the .xyz file
    num_atoms=$(head -n 1 "$file")

    # Run atomkit in a subshell, so a failure cannot leave us inside the image directory
    if ! ( cd "$new_prefix" && echo -e "412\n175 POSCAR\n175" | atomkit > /dev/null 2>&1 && mv POSCAR_REV.vasp POSCAR ); then
      echo "Error: atomkit failed in directory '$new_prefix'; nothing merged (image directories kept)."
      exit 1
    fi

    # Extract the first two lines from the ${file} and save it to the temporary file
    tmp_file="${file}.tmp"
    head -n 2 "${file}" > "$tmp_file"

    paste "$new_prefix/${file%.xyz}_first_column.txt" <(awk 'NR>=9 {print $1, $2, $3}' "$new_prefix/POSCAR") > "$file"

    # Append the content of the original file to the temporary file
    cat "$file" >> "$tmp_file"

    # Replace the original file with the temporary file
    mv "$tmp_file" "$file"

    echo ".xyz file created for $file from POSCAR in directory $new_prefix."
  done
}

# Function to merge all .xyz files with numeric prefixes into traj.xyz
merge_to_traj() {
  echo "Merging .xyz files with numeric prefixes into traj.xyz..."
  # Ensure the output file is empty
  > traj.xyz
  image_dirs=()

  # Loop through all .xyz files in numerical order and append to traj.xyz
  for file in $(ls *.xyz | sort -V); do
    # Extract the prefix of the .xyz file
    prefix="${file%.xyz}"
    
    # Check if the prefix is a number
    if [[ $prefix =~ ^[0-9]+$ ]]; then
      cat "$file" >> traj.xyz
      image_dirs+=("$(printf "%02d" $((10#$prefix - image_offset)))")
      # echo "" >> traj.xyz  # Add a newline between files for clarity
    else
      echo "Warning: '$file' does not have a numeric prefix and will be skipped."
      continue
    fi
  done

  # Remove the numbered image directories created by this script (not other subdirectories)
  for dir in "${image_dirs[@]}"; do
    rm -rf -- "$dir"
  done

  echo "All .xyz files with numeric prefixes have been merged into traj.xyz."
}

# Choose functionality (argument, or menu)
choice="${1:-}"
if [ -z "$choice" ]; then
  echo "Choose a function to run:"
  echo "1. Convert .xyz to POSCAR"
  echo "2. Convert POSCAR to .xyz"
  read -p "Enter your choice (1 or 2): " choice
fi

# Validate the choice and call the appropriate function
case $choice in
  1|xyz2poscar)
    get_lattice_parameters && xyz_to_POSCAR
    ;;
  2|poscar2xyz)
    POSCAR_to_xyz && merge_to_traj
    ;;
  -h|--help)
    show_help
    ;;
  *)
    echo "Invalid choice. Please enter 1 or 2."
    ;;
esac

