#!/bin/bash

# Function to get lattice parameters
get_lattice_parameters() {
  if ! grep -q '&CELL' cp2k.inp; then
    echo "Error: The file 'cp2k.inp' does not contain '&CELL'."
    exit 1
  fi
  
  lattice_parameter=$(grep -A 3 '&CELL' cp2k.inp | tail -3 | awk '{$1=""; print $0}')
  
  if [ -z "$lattice_parameter" ]; then
    echo "Error: Could not extract lattice parameters."
    exit 1
  fi
}

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
      # Convert the prefix to a two-digit number and subtract 1
      new_prefix=$(printf "%02d" $((10#$prefix - 1)))
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
      # Convert the prefix to a two-digit number and subtract 1
      new_prefix=$(printf "%02d" $((10#$prefix - 1)))
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

    cd "$new_prefix" && echo -e "412\n175 POSCAR\n175" | atomkit > /dev/null 2>&1 && mv POSCAR_REV.vasp POSCAR && cd ..

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

  # Loop through all .xyz files in numerical order and append to traj.xyz
  for file in $(ls *.xyz | sort -V); do
    # Extract the prefix of the .xyz file
    prefix="${file%.xyz}"
    
    # Check if the prefix is a number
    if [[ $prefix =~ ^[0-9]+$ ]]; then
      cat "$file" >> traj.xyz
      # echo "" >> traj.xyz  # Add a newline between files for clarity
    else
      echo "Warning: '$file' does not have a numeric prefix and will be skipped."
      continue
    fi
  done

  # Remove the directories
  rm -rf */

  echo "All .xyz files with numeric prefixes have been merged into traj.xyz."
}

# Choose functionality
echo "Choose a function to run:"
echo "1. Convert .xyz to POSCAR"
echo "2. Convert POSCAR to .xyz"
read -p "Enter your choice (1 or 2): " choice

# Validate the choice and call the appropriate function
case $choice in
  1)
    get_lattice_parameters && xyz_to_POSCAR
    ;;
  2)
    POSCAR_to_xyz && merge_to_traj
    ;;
  *)
    echo "Invalid choice. Please enter 1 or 2."
    ;;
esac

