#!/bin/bash

output="zfs_sum.log"

dir_num="1 2 3 4 5 6 7 8 9 10 12 15 20"

for i in $dir_num ; do
        cd HOMO-LUMO-$i
	echo "-----------------------" >> ../$output
	echo "HOMO-LUMO-$i" >> ../$output
	echo "-----------------------" >> ../$output
	cat zfs.xml >> ../$output
	echo -e "\n" >> ../$output
	cd ..
done
