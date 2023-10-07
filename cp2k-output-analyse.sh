#!/bin/bash

cat <<EOF
*************************************
*** The format of the script: ***
$0 OUTPUT_FILE.out
*************************************
EOF

if [ -z "$1" ] ; then
	        echo -e "\033[31mERROR:\033[0m Missing file operand! Please identify the name of OUTPUT_FILE.out"
		        exit 1
fi

echo "====================================="
echo "In process..."
echo "..."

#input_file=$PWD/$input_file
input_file=${1%.*}.inp
plot_file=$PWD/${1%.*}__data.ssv
output_file=${1%.*}.out



starttime=`grep -w "PROGRAM STARTED AT"  $output_file | awk -F "AT" '{print $NF}' | tr -s [:space:]`


if [ -a $plot_file ] ; then
	rm -r $plot_file
fi

MAX_D=`grep -w "Conv. limit for step size" $output_file | head -1 | awk -F '=' '{print $NF}' | sed s/[[:space:]]//g | sed 's/0*$//'`
RMS_D=`grep -w "Conv. limit for RMS step" $output_file | head -1 | awk -F '=' '{print $NF}' | sed s/[[:space:]]//g | sed 's/0*$//'`
MAX_F=`grep -w "Conv. limit for gradients" $output_file | head -1 | awk -F '=' '{print $NF}' | sed s/[[:space:]]//g | sed 's/0*$//'`
RMS_F=`grep -w "Conv. limit for RMS grad" $output_file | head -1 | awk -F '=' '{print $NF}' | sed s/[[:space:]]//g | sed 's/0*$//'`


RUN_TYPE=`grep -w "Run type" $output_file | awk -F ' ' '{print $NF}'`
EPS_SCF=`grep -w "eps_scf:" $output_file | awk -F ":" '{print $NF}' | tr -s [:space:]`
OUTER_SCF_CHECK=`grep -w "Outer loop SCF in use" $output_file`
MAX_SCF=`grep -w "max_scf:" $output_file | awk -F ":" '{print $NF}' | tr -s [:space:]`
#use awk to grab the string between *** and ***
GEO_OPTIMIZER=`grep -w -A 1 "STARTING GEOMETRY OPTIMIZATION" $output_file | tail -1 | awk 'BEGIN{FS="***|***"} {print $2}' | tr -s [:space:]`
#check the SCF optimizer
OT_CHECK=`grep -w -w OT $output_file | head -1 | awk -F ' ' '{print $2}'`
if [ $OT_CHECK ] ;  then
	SCF_OPTIMIZER="OT"
else
	SCF_OPTIMIZER="DIAGONALIZATION"
fi

echo "# Job Starting Date: $starttime" >> $plot_file
echo "# Directory: $PWD" >> $plot_file
[[ -n $RUN_TYPE ]] && echo "# RUN_TYPE: $RUN_TYPE" >> $plot_file
[[ -n $EPS_SCF ]] && echo "# EPS_SCF: $EPS_SCF" >> $plot_file
[[ -n $MAX_SCF ]] && echo "# MAX_SCF: $MAX_SCF" >> $plot_file
[[ ! -n $MAX_SCF ]] && echo "# MAX_SCF: 50" >> $plot_file
[[ -n $SCF_OPTIMIZER ]] && echo "# SCF_OPTIMIZER: $SCF_OPTIMIZER" >> $plot_file
[[ -n $OUTER_SCF_CHECK ]] && echo "# OUTER_SCF: TRUE" >> $plot_file
[[ -n $GEO_OPTIMIZER ]] && echo "# GEO_OPTIMIZER: $GEO_OPTIMIZER" >> $plot_file
echo -n "# CYCLE | TOTAL_ENERGY [a.u.] | MAX_D.($MAX_D) | RMS_D.($RMS_D) | MAX_F.($MAX_F) | RMS_F.($RMS_F) | USEDTIME [s]" >> $plot_file

CYCLE_TOTAL=`grep -w "Informations at step" $output_file | wc -l`
#for((i=1;i<=3;i++));do
for((i=1;i<=$CYCLE_TOTAL;i++));do
    CYCLE_NUMBER=`grep -w -am $i "Informations at step" $output_file | tail -1 | awk -F "=" '{print $NF}' | awk -F "-" '{print $1}'` 
    if [ $RUN_TYPE == "GEO_OPT" ] ; then
	    READ_LINE_NUMBER=21
    elif [ $RUN_TYPE == "CELL_OPT" ] ; then
	    READ_LINE_NUMBER=28
    else
	    echo -e "\033[31mERROR:\033[0m This script can only be used for Geometry Optimization results!"
	    exit 1
    fi
    TOTAL_ENERGY=`grep -w  -m $i -A $READ_LINE_NUMBER "Informations at step" $output_file | tail -${READ_LINE_NUMBER} | grep -w "Total Energy" | awk -F '=' '{print $NF}' | sed s/[[:space:]]//g`
    USEDTIME=`grep -w  -m $i -A $READ_LINE_NUMBER "Informations at step" $output_file | tail -${READ_LINE_NUMBER} | grep -w "Used time" | awk -F '=' '{print $NF}' | sed s/[[:space:]]//g`
    MAX_D_VALUE=`grep -w  -m $i -A $READ_LINE_NUMBER "Informations at step" $output_file | tail -${READ_LINE_NUMBER} | grep -w "Max. step size" | awk -F '=' '{print $NF}' | sed s/[[:space:]]//g`
    if [[ $MAX_D_VALUE ]] ; then
	    if [[  `echo "$MAX_D_VALUE > $MAX_D" | bc` -eq 1 ]] ; then
		    MAX_D_CONVERGENCE="NO"
	    else
		    MAX_D_CONVERGENCE="YES"
	    fi
	    RMS_D_VALUE=`grep -w  -m $i -A $READ_LINE_NUMBER "Informations at step" $output_file | tail -${READ_LINE_NUMBER} | grep -w "RMS step size" | awk -F '=' '{print $NF}' | sed s/[[:space:]]//g`
	    #RMS_D_CONVERGENCE=`grep -w  -m $i -A $READ_LINE_NUMBER "Informations at step" $output_file | tail -${READ_LINE_NUMBER} | grep -w "Convergence in RMS step" | awk -F '=' '{print $NF}' | sed s/[[:space:]]//g`
	    if [[  `echo "$RMS_D_VALUE > $RMS_D" | bc` -eq 1 ]] ; then
	            RMS_D_CONVERGENCE="NO"
	    else
	            RMS_D_CONVERGENCE="YES"
	    fi
	    MAX_F_VALUE=`grep -w  -m $i -A $READ_LINE_NUMBER "Informations at step" $output_file | tail -${READ_LINE_NUMBER} | grep -w "Max. gradient" | awk -F '=' '{print $NF}' | sed s/[[:space:]]//g`
	    #MAX_F_CONVERGENCE=`grep -w  -m $i -A $READ_LINE_NUMBER "Informations at step" $output_file | tail -${READ_LINE_NUMBER} | grep -w "Conv. for gradients" | head -1 | awk -F '=' '{print $NF}' | sed s/[[:space:]]//g`
	    if [[  `echo "$MAX_F_VALUE > $MAX_F" | bc` -eq 1 ]] ; then
	            MAX_F_CONVERGENCE="NO"
	    else
	            MAX_F_CONVERGENCE="YES"
	    fi
	    RMS_F_VALUE=`grep -w  -m $i -A $READ_LINE_NUMBER "Informations at step" $output_file | tail -${READ_LINE_NUMBER} | grep -w "RMS gradient" | awk -F '=' '{print $NF}' | sed s/[[:space:]]//g`
	    if [[  `echo "$RMS_F_VALUE > $RMS_F" | bc` -eq 1 ]] ; then
	            RMS_F_CONVERGENCE="NO"
	    else
	            RMS_F_CONVERGENCE="YES"
	    fi
	    #RMS_F_CONVERGENCE=`grep -w  -m $i -A $READ_LINE_NUMBER "Informations at step" $output_file | tail -${READ_LINE_NUMBER} | grep -w "Conv. for gradients" | tail -1 | awk -F '=' '{print $NF}' | sed s/[[:space:]]//g`
	
	    ENERGY_CHANGE=`grep -w  -m $i -A $READ_LINE_NUMBER "Informations at step" $output_file | tail -${READ_LINE_NUMBER} | grep -w "Decrease in energy" | awk -F '=' '{print $NF}' | sed s/[[:space:]]//g`
	    if [[ ${ENERGY_CHANGE} == "NO" ]] ; then
	        printf "\n%s" xx >> $plot_file
		printf "%5s %19s" $CYCLE_NUMBER $TOTAL_ENERGY >> $plot_file
	    else
	        printf "\n%7s %19s" $CYCLE_NUMBER $TOTAL_ENERGY >> $plot_file
	    fi
    	    printf "%14.6f %3s" $MAX_D_VALUE $MAX_D_CONVERGENCE >> $plot_file
	    printf "%12.6f %3s" $RMS_D_VALUE $RMS_D_CONVERGENCE >> $plot_file
	    printf "%14.6f %3s" $MAX_F_VALUE $MAX_F_CONVERGENCE >> $plot_file
	    printf "%13.6f %3s" $RMS_F_VALUE $RMS_F_CONVERGENCE >> $plot_file
	    printf "%13.3f" $USEDTIME >> $plot_file
else
	    printf "\n%7s %19s %12s %15s %16s %17s %17.3f" $CYCLE_NUMBER $TOTAL_ENERGY "N/A" "N/A" "N/A" "N/A" $USEDTIME >> $plot_file
fi
done
printf "\n# Done!" >> $plot_file
echo "====================================="
