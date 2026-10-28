#!/bin/bash

bs_file=$1
if [ -a ${bs_file}.total.csv ] ; then
	rm ${bs_file}.total.csv
fi
cp2k_bs2csv $1
bs2csv_files=`ls ${bs_file}.set* | sort -V`   # -V: set-2 before set-10
bs2csv_files_first_one=`ls ${bs_file}.set* | sort -V | head -1 `
for i in $bs2csv_files; do
	if [ $i == $bs2csv_files_first_one ] ; then
		cat $i >> ${bs_file}.total.csv
	else
		sed -e '1d' $i >> ${bs_file}.total.csv
	fi
done
