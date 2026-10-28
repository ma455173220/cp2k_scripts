#!/bin/bash
# cp2k_common.sh -- shared helpers for the cp2k_scripts bash scripts.
#
# This file is sourced, not run. Scripts locate it like this (next to the running script, then PATH):
#
#   _lib="$(dirname "$(readlink -f "$0")")/cp2k_common.sh"
#   [ -f "$_lib" ] || _lib="$(command -v cp2k_common.sh)" \
#       || { echo "Error: cp2k_common.sh not found (keep it next to this script or in PATH)" >&2; exit 1; }
#   source "$_lib"
#
# It only defines variables and functions; it is safe under "set -euo pipefail".

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    echo "cp2k_common.sh is a library of shell functions; source it from a script instead of running it." >&2
    exit 1
fi

# ---------------------------------------------------------------- colours / messages
RED='\033[31m'
GREEN='\033[1;32m'
ORANGE='\033[1;33m'
NC='\033[0m'

die()  { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }
warn() { echo -e "${ORANGE}Warning:${NC} $*" >&2; }
info() { echo -e "${GREEN}$*${NC}"; }

# show_help -- print the leading comment block of the running script (its usage text)
show_help() {
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$(readlink -f "$0")"
}

# confirm "question" [Y|N]  -- ask a yes/no question; Enter gives the default (N if not given).
# Returns 0 for yes. Without a terminal on stdin an empty answer is read, i.e. the default.
confirm() {
    local question="$1" default="${2:-N}" answer=""
    read -r -p "$question" answer || true
    [ -z "$answer" ] && answer="$default"
    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------- batch scheduler
# Detect the batch scheduler (PBS on Gadi, Slurm on Setonix): prints pbs, slurm or none
detect_scheduler() {
    if command -v qsub >/dev/null 2>&1; then
        echo "pbs"
    elif command -v sbatch >/dev/null 2>&1; then
        echo "slurm"
    else
        echo "none"
    fi
}

# Print the submit command for the detected scheduler (PBS: /opt/pbs/default/bin/qsub if present).
# Returns 1 (and prints nothing) if neither qsub nor sbatch is available.
submit_cmd() {
    case "$(detect_scheduler)" in
        pbs)
            if [ -x /opt/pbs/default/bin/qsub ]; then
                echo "/opt/pbs/default/bin/qsub"
            else
                echo "qsub"
            fi
            ;;
        slurm) echo "sbatch" ;;
        *) return 1 ;;
    esac
}

# submit_in_dir DIR SCRIPT [SUBMIT_CMD]
# Submit SCRIPT inside DIR (in a subshell, so the caller never changes directory).
# The scheduler's output (the job id) is printed; the return status is the submit command's.
submit_in_dir() {
    local dir="$1" script="$2" cmd="${3:-}"
    if [ -z "$cmd" ]; then
        cmd=$(submit_cmd) || { echo "Neither qsub nor sbatch found, cannot submit $dir/$script" >&2; return 1; }
    fi
    if [ ! -d "$dir" ]; then
        echo "Directory $dir does not exist, not submitted" >&2
        return 1
    fi
    ( cd "$dir" && $cmd "$script" )
}

# ---------------------------------------------------------------- helper scripts
# find_script NAME [OLD_PATH] -- locate a helper script: next to the running script, then in PATH,
# then OLD_PATH (the old Gadi location). Prints the path, or an error and returns 1.
find_script() {
    local self_dir
    self_dir="$(dirname "$(readlink -f "$0")")"
    if [ -x "$self_dir/$1" ]; then
        echo "$self_dir/$1"
    elif command -v "$1" >/dev/null 2>&1; then
        command -v "$1"
    elif [ -n "${2:-}" ] && [ -x "$2" ]; then
        echo "$2"
    else
        echo -e "${ORANGE}Error: cannot find $1 (searched $self_dir, PATH${2:+ and $2})${NC}" >&2
        return 1
    fi
}

# ---------------------------------------------------------------- CP2K output files
# latest_out DIR -- newest *.out file in DIR (prints nothing and returns 1 if there is none)
latest_out() {
    local f
    f=$(ls -t "${1:-.}"/*.out 2>/dev/null | head -1)
    [ -n "$f" ] || return 1
    echo "$f"
}

# cp2k_finished OUT -- true if the run finished ("PROGRAM ENDED AT" present)
cp2k_finished() {
    grep -q "PROGRAM ENDED AT" "$1" 2>/dev/null
}

# cp2k_energy OUT -- last "ENERGY| Total FORCE_EVAL ..." value (Hartree)
cp2k_energy() {
    grep -e 'ENERGY| Total FORCE_EVAL' "$1" 2>/dev/null | tail -1 | awk '{print $NF}'
}

# cp2k_walltime OUT -- total wall time in seconds (last field of the "CP2K   1 ..." timing line)
cp2k_walltime() {
    grep -E '^ CP2K +1 ' "$1" 2>/dev/null | tail -1 | awk '{print $NF}'
}

# cp2k_inp_py -- path of the cp2k_inp.py helper (next to the running script, then PATH)
cp2k_inp_py() {
    find_script cp2k_inp.py
}
