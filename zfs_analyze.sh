#!/bin/bash
# Append the zfs.xml of every HOMO-LUMO-N directory (made by zfs_run.sh) to zfs_sum.log.
#
# Usage: zfs_analyze.sh [-n "1 2 3 ..."]
#   -n LIST   values of N (default: 1 2 3 4 5 6 7 8 9 10 12 15 20, as in zfs_run.sh)

output="zfs_sum.log"

dir_num="1 2 3 4 5 6 7 8 9 10 12 15 20"

while getopts ":n:h" opt; do
	case "$opt" in
		n) dir_num="$OPTARG" ;;
		h) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
		*) echo "Unknown option or missing value: -$OPTARG (see -h)"; exit 1 ;;
	esac
done

for i in $dir_num ; do
	if [ ! -d HOMO-LUMO-$i ] ; then
		echo "Warning: HOMO-LUMO-$i does not exist, skipped" >&2
		continue
	fi
	echo "-----------------------" >> $output
	echo "HOMO-LUMO-$i" >> $output
	echo "-----------------------" >> $output
	cat HOMO-LUMO-$i/zfs.xml >> $output
	echo -e "\n" >> $output
done
