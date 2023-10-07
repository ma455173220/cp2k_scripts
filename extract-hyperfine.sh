#!/bin/bash

DIRECTORY_LIST=`ls -d */ 2>>/dev/null`

if [ -z "$DIRECTORY_LIST" ] ; then
	if [ -z "$1" ] ; then
                echo -e "\033[31mERROR:\033[0m Missing file operand! Please identify the atom index"
                exit 1
        fi
	if [ -a $1 ] ; then
		ATOM_INDEX=`cat $1 | awk -F " " '{print $2}'`
	else
		ATOM_INDEX="$1 $2 $3 $4 $5 $6"
	fi
else
	if [ -z "$1" ] ; then
                echo -e "\033[31mERROR:\033[0m Missing file operand! Please identify the name of Directory"
                exit 1
	fi
	
	if [ -z "$2" ] ; then
	        echo -e "\033[31mERROR:\033[0m Missing file operand! Please identify the atom index"
	        exit 1
	fi
	HYPERFINE_DIR=$1
	if [ -a $2 ] ; then
		ATOM_INDEX=`cat $2`
	else
		ATOM_INDEX="$2 $3 $4 $5 $6 $7"
	fi
fi

CURRENT_DIR=`pwd`
ISO_HYPERFINE_OUTPUT_FILE="iso_A.csv"
AISO_HYPERFINE_OUTPUT_FILE="a-iso_A.csv"

if [ -a $ISO_HYPERFINE_OUTPUT_FILE ] ; then
	rm $ISO_HYPERFINE_OUTPUT_FILE
fi

if [ -a $AISO_HYPERFINE_OUTPUT_FILE ] ; then
        rm $AISO_HYPERFINE_OUTPUT_FILE
fi


if [ -z "$DIRECTORY_LIST" ] ; then
        LASTEST_OUTPUT_FILE=`ls -lhtr *.out | tail -1 | awk -F " " '{print $NF}'`
        echo $LASTEST_OUTPUT_FILE >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
        echo $LASTEST_OUTPUT_FILE >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
	NUM_OF_ATOMS=`grep "\- Atoms:" $LASTEST_OUTPUT_FILE | awk -F ":" '{print $NF}' 2>>/dev/null` 
	for ii in $ATOM_INDEX ; do
		ATOM_LINE_NUMBER=`expr $ii \* 5 + 1`
		if [ $NUM_OF_ATOMS -lt $ii ] ; then
			echo "Atom index is larger than the number of atoms in the system" >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
			echo "Atom index is larger than the number of atoms in the system" >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
		else
        		grep -EA $ATOM_LINE_NUMBER "Calculation of EPR hyperfine coupling tensors" $LASTEST_OUTPUT_FILE | tail -5 | head -2 >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
        		grep -EA $ATOM_LINE_NUMBER "Calculation of EPR hyperfine coupling tensors" $LASTEST_OUTPUT_FILE | tail -5 >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
		fi
	done
else
	for ii in $ATOM_INDEX ; do
		ATOM_LINE_NUMBER=`expr $ii \* 5 + 1`
		for i in $DIRECTORY_LIST ; do
		        cd $i
			echo $i >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
			echo $i >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
			if [ -d $HYPERFINE_DIR ] ; then
		        	cd $HYPERFINE_DIR
				LASTEST_OUTPUT_FILE=`ls -lhtr *.out | tail -1 | awk -F " " '{print $NF}' 2>>/dev/null`
				echo $LASTEST_OUTPUT_FILE >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
				echo $LASTEST_OUTPUT_FILE >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
				NUM_OF_ATOMS=`grep "\- Atoms:" $LASTEST_OUTPUT_FILE | awk -F ":" '{print $NF}'`
				if [ $NUM_OF_ATOMS -lt $ii ] ; then
        	    			echo "Atom index is larger than the number of atoms in the system" >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
        	        		echo "Atom index is larger than the number of atoms in the system" >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
        			else
		        		grep -EA $ATOM_LINE_NUMBER "Calculation of EPR hyperfine coupling tensors" $LASTEST_OUTPUT_FILE	| tail -5 | head -2 >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
					grep -EA $ATOM_LINE_NUMBER "Calculation of EPR hyperfine coupling tensors" $LASTEST_OUTPUT_FILE	| tail -5 >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
				fi
			else
				echo "$HYPERFINE_DIR does not exist!" >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
				echo "$HYPERFINE_DIR does not exist!" >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
			fi
		        cd $CURRENT_DIR
		done
		echo -e "----------------------------------------\n" >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
		echo -e "----------------------------------------\n" >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
	done
fi

echo -e "=========================================\n" >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
echo -e "=========================================\n" >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
echo "Extracted value" >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
echo -e "-----------------------------------------" >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
echo "Extracted value" >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
echo -e "-----------------------------------------" >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
echo -e "Dir\tAtom_index\tIso_A" >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
echo -e "Dir\tAtom_index\tA_iso_xy\tA_iso_yz\tA_iso_xz" >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE

if [ -z "$DIRECTORY_LIST" ] ; then
	LASTEST_OUTPUT_FILE=`ls -lhtr *.out | tail -1 | awk -F " " '{print $NF}'`
	NUM_OF_ATOMS=`grep "\- Atoms:" $LASTEST_OUTPUT_FILE | awk -F ":" '{print $NF}' 2>>/dev/null`
	for ii in $ATOM_INDEX ; do
		ATOM_LINE_NUMBER=`expr $ii \* 5 + 1`
		if [ $NUM_OF_ATOMS -lt $ii ] ; then
        	        echo "Atom index is larger than the number of atoms in the system" >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
        	        echo "Atom index is larger than the number of atoms in the system" >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
        	else
        		Iso=` grep -EA $ATOM_LINE_NUMBER "Calculation of EPR hyperfine coupling tensors" $LASTEST_OUTPUT_FILE | tail -5 | head -1 | awk -F " " '{print $NF}'`
        		echo -e "$ii\t$Iso" >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
        		A_iso_xy=`grep -EA $ATOM_LINE_NUMBER "Calculation of EPR hyperfine coupling tensors" $LASTEST_OUTPUT_FILE | tail -2 | head -1 | awk -F " " '{print $3}'`
        		A_iso_yz=`grep -EA $ATOM_LINE_NUMBER "Calculation of EPR hyperfine coupling tensors" $LASTEST_OUTPUT_FILE | tail -2 | head -1 | awk -F " " '{print $NF}'`
        		A_iso_xz=`grep -EA $ATOM_LINE_NUMBER "Calculation of EPR hyperfine coupling tensors" $LASTEST_OUTPUT_FILE | tail -2 | tail -1 | awk -F " " '{print $1}'`
        		echo -e "$ii\t${A_iso_xy} ${A_iso_yz} ${A_iso_xz}" >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
		fi
	done
else
	for ii in $ATOM_INDEX ; do
		ATOM_LINE_NUMBER=`expr $ii \* 5 + 1`
		for i in $DIRECTORY_LIST ; do
			cd $i
			if [ -d $HYPERFINE_DIR ] ; then
				cd $HYPERFINE_DIR
				LASTEST_OUTPUT_FILE=`ls -lhtr *.out | tail -1 | awk -F " " '{print $NF}'`
				NUM_OF_ATOMS=`grep "\- Atoms:" $LASTEST_OUTPUT_FILE | awk -F ":" '{print $NF}' 2>>/dev/null`
				if [ $NUM_OF_ATOMS -lt $ii ] ; then
        	    			echo $i "Atom index is larger than the number of atoms in the system" >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
        	        		echo $i "Atom index is larger than the number of atoms in the system" >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
        			else
					Iso=` grep -EA $ATOM_LINE_NUMBER "Calculation of EPR hyperfine coupling tensors" $LASTEST_OUTPUT_FILE | tail -5 | head -1 | awk -F " " '{print $NF}'`
		       			echo -e "$i\t$ii\t$Iso" >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
					A_iso_xy=`grep -EA $ATOM_LINE_NUMBER "Calculation of EPR hyperfine coupling tensors" $LASTEST_OUTPUT_FILE | tail -2 | head -1 | awk -F " " '{print $3}'`  
		        		A_iso_yz=`grep -EA $ATOM_LINE_NUMBER "Calculation of EPR hyperfine coupling tensors" $LASTEST_OUTPUT_FILE | tail -2 | head -1 | awk -F " " '{print $NF}'` 
		        		A_iso_xz=`grep -EA $ATOM_LINE_NUMBER "Calculation of EPR hyperfine coupling tensors" $LASTEST_OUTPUT_FILE | tail -2 | tail -1 | awk -F " " '{print $1}'`
		        		echo -e "$i\t$ii\t${A_iso_xy} ${A_iso_yz} ${A_iso_xz}" >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
				fi
			else
				echo $i "$HYPERFINE_DIR does not exist!" >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
        	                echo $i "$HYPERFINE_DIR does not exist!" >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
			fi
			cd $CURRENT_DIR
		done
		echo -e "----------------------------------------\n" >> $CURRENT_DIR/$ISO_HYPERFINE_OUTPUT_FILE
                echo -e "----------------------------------------\n" >> $CURRENT_DIR/$AISO_HYPERFINE_OUTPUT_FILE
	done
fi
