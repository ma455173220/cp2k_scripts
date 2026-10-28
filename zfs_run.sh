#!/bin/bash
# Zero-field splitting: for every N in the list create HOMO-LUMO-N with the job script and links to the
# first N+9 cp2k-WFN* files of the parent directory, then submit it. Collect the results with zfs_analyze.sh.
#
# Usage: zfs_run.sh [-n "1 2 3 ..."] [-j o2]
#   -n LIST   values of N (default: 1 2 3 4 5 6 7 8 9 10 12 15 20)
#   -j FILE   job script copied into and submitted in each directory (default o2)

# Shared helpers (cp2k_common.sh: next to this script, else in PATH)
_lib="$(dirname "$(readlink -f "$0")")/cp2k_common.sh"
[ -f "$_lib" ] || _lib="$(command -v cp2k_common.sh)" || { echo "Error: cp2k_common.sh not found (keep it next to this script or in PATH)" >&2; exit 1; }
source "$_lib"

dir_num="1 2 3 4 5 6 7 8 9 10 12 15 20"
job_script="o2"

while getopts ":n:j:h" opt; do
	case "$opt" in
		n) dir_num="$OPTARG" ;;
		j) job_script="$OPTARG" ;;
		h) show_help; exit 0 ;;
		*) echo "Unknown option or missing value: -$OPTARG (see -h)"; exit 1 ;;
	esac
done

if ! submit_command=$(submit_cmd) ; then
	echo "Warning: neither qsub nor sbatch found, jobs will not be submitted."
	submit_command="echo Not submitted:"
fi

for i in $dir_num ; do

	if [ -d HOMO-LUMO-$i ] ; then
		read -p "Directory 'HOMO-LUMO-$i' already exists. Delete it and recreate? [y/N] " response
		if [ "$response" == "Y" ] || [ "$response" == "y" ]; then
			rm -rf HOMO-LUMO-$i
		else
			echo "Skipping 'HOMO-LUMO-$i' (not recreated, not submitted)."
			continue
		fi
	fi

	mkdir HOMO-LUMO-$i
	cp "./$job_script" HOMO-LUMO-$i
	(
	cd HOMO-LUMO-$i || exit 1
	num_add=`expr $i + 9`
	#ln -s ../cp2k-WFN*`eval echo {00001..000${num_add}}`* . 
	for ii in `eval echo {00001..000${num_add}}` ; do
		ln -s ../cp2k-WFN*${ii}* .
	done
	# drop the last two links of spin channel 2 (files named *2-*)
	ls -a *2-* | tail -2 | xargs rm
	$submit_command "$job_script"
	)
done
