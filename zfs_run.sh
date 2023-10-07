#!/bin/bash

dir_num="1 2 3 4 5 6 7 8 9 10 12 15 20"

for i in $dir_num ; do

	if [ -d HOMO-LUMO-$i ] ; then
		rm -rf HOMO-LUMO-$i
	fi

	mkdir HOMO-LUMO-$i
	cp ./o2 HOMO-LUMO-$i
        cd HOMO-LUMO-$i
        num_add=`expr $i + 9`
        #ln -s ../cp2k-WFN*`eval echo {00001..000${num_add}}`* . 
	for ii in `eval echo {00001..000${num_add}}` ; do
		ln -s ../cp2k-WFN*${ii}* .
	done
	ls -a *2-* | tail -2 | xargs rm
	qsub o2
        cd ..
done
