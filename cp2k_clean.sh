#!/bin/bash

# Set the list of filenames to delete, common large VASP files
LARGE_FILES=(
    "*.wfn" "*.cub" "*.cube"
)

# Traverse the current directory and all subdirectories, deleting specified large files
for file in "${LARGE_FILES[@]}"; do
    find . -type f -name "$file" -exec rm -v {} +
done

echo "Cleanup completed."
