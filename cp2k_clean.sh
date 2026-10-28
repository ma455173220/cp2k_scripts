#!/bin/bash

# Delete large CP2K files (wavefunctions and cube files) in the current directory and all subdirectories.
# Usage: cp2k_clean.sh [-y] [-n]
#   -y  delete without asking for confirmation
#   -n  dry run: only list what would be deleted
# Note: this also deletes the *-RESTART.wfn files needed to restart a calculation.

# Set the list of filenames to delete, common large CP2K files (wavefunctions and cube files)
LARGE_FILES=(
    "*.wfn" "*.cub" "*.cube"
)

ASSUME_YES=0
DRY_RUN=0
while getopts ":ynh" opt; do
    case "$opt" in
        y) ASSUME_YES=1 ;;
        n) DRY_RUN=1 ;;
        h) sed -n '3,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Usage: $0 [-y] [-n]"; exit 1 ;;
    esac
done

# Collect the matching files first
find_args=()
for file in "${LARGE_FILES[@]}"; do
    [ ${#find_args[@]} -gt 0 ] && find_args+=(-o)
    find_args+=(-name "$file")
done
mapfile -d '' files < <(find . -type f \( "${find_args[@]}" \) -print0)

if [ ${#files[@]} -eq 0 ]; then
    echo "No ${LARGE_FILES[*]} files found."
    exit 0
fi

total_bytes=$(printf '%s\0' "${files[@]}" | du -cb --files0-from=- | tail -1 | cut -f1)
printf '%s\n' "${files[@]}"
echo "${#files[@]} file(s), $(numfmt --to=iec --suffix=B "$total_bytes" 2>/dev/null || echo "$total_bytes bytes") in total (including any *RESTART.wfn)."

if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run (-n): nothing deleted."
    exit 0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
    read -p "Delete these files? [y/N] " answer
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        echo "Nothing deleted."
        exit 0
    fi
fi

printf '%s\0' "${files[@]}" | xargs -0 rm -v --

echo "Cleanup completed."
