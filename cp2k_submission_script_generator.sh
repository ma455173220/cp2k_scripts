#!/bin/bash
#Submission script generator. It can also give warning when the memory exceeds 4 times of the number of cpu.
#Format of using: script inputfile.d12 SUBMISSION_FILE (PS:the SUBMISSION_FILE is optional)

SCRIPT_DIR=~/cp2k_runscript


INPUT_FILE=$1
SUBMISSION_FILE=$2

cat <<EOF
*************************************************************************
*********************** The format of the script: ***********************
$0 file_name.inp (submission file)
*************************************************************************
EOF


cp2k_version_choice (){

    sed -i '/^mpirun/s/^/# /' $PWD/$SUB_SCRIPT
    sed -i '/cp2k-2024.1-intelmpi/s/^# //' $PWD/$SUB_SCRIPT

}

editor_check () {
        if [ $EDITOR_CHOICE -eq '1' ] ; then
                /home/561/hm1876/.local/bin/vim $PWD/$SUB_SCRIPT
        elif [ $EDITOR_CHOICE -eq '2' ] ; then
                nano $PWD/$SUB_SCRIPT
        fi
}


if [ -z "$1" ] ; then
	echo -e "\033[31mERROR:\033[0m Missing file operand! Please identify the name of file_name.inp!"
	exit 1
fi

echo -e "Enter the name of the new submission script"
read SUB_SCRIPT
if [ -z "$2" ] ; then
        cp -f $SCRIPT_DIR $PWD/$SUB_SCRIPT
else
        cp -f $2 $PWD/$SUB_SCRIPT
fi

sed -i "s/JOBNAME=\"[^)]*\"/JOBNAME=\"${1%.*}\"/" $SUB_SCRIPT
sed -i "s/OUT_NAME=\"[^)]*\"/OUT_NAME=\"${1%.*}\"/" $SUB_SCRIPT

# echo -e "Which CP2K version are you using?\n1. 2023.1\n2. 2024.1"
# read CP2K_VERSION_CHOICE
# if [ $CP2K_VERSION_CHOICE -eq '2' ] ; then 
#     cp2k_version_choice
# fi

echo -e "Which text editor are you using?\n1 vi/vim\n2 nano"
read EDITOR_CHOICE
editor_check

echo -e "Do you want to submit the script?\n1 YES\n2 NO"
read SUBMIT_CHOICE
if [ $SUBMIT_CHOICE -eq '1' ] ; then
	echo -e "\n========================================\nSubmission in process, please wait...\n..."
	echo "qsub $SUB_SCRIPT"
	/opt/pbs/default/bin/qsub $SUB_SCRIPT && echo -e "\nJob submitted!\n========================================"
else
	echo -e "\n========================================\nDone!\n========================================"
fi
