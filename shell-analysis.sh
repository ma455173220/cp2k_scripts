#!/bin/bash

if [ -a sum.ssv ] ; then
	rm sum.ssv
fi

for i in `ls | sort `; do
	if [ -d $i ] ; then
		cd $i
		value=`grep "  1 P   31" *.out | awk -F ' ' '{print $NF}'`
		cd ..
		echo -e "$i $value" >> sum.ssv
	fi
done
