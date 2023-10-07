#!/bin/bash

if [ -z "$1" ] ; then
        echo -e "\033[31mERROR:\033[0m Missing file operand! Please identify the name of restart file!"
	echo -e "Format: cp2k-restart.sh restart_file input_file"
        exit 1
fi

if [ -z "$2" ] ; then
	        echo -e "\033[31mERROR:\033[0m Missing file operand! Please identify the name of target file!"
		echo -e "Format: cp2k-restart.sh restart_file input_file"
		exit 1
fi


restart_cell_top_line_number=`grep -n "&CELL\$" $1 | grep -v "#" | head -1 | awk -F ':' '{print $1}'`
restart_cell_bottom_line_number=`grep -n "CELL\$" $1 | grep -v "#" | tail -1 | awk -F ':' '{print $1}'`
sed -n "${restart_cell_top_line_number},${restart_cell_bottom_line_number}p" $1 >> tmp_cell

restart_coord_top_line_number=`grep -n "&COORD\$" $1 | grep -v "#" | head -1 | awk -F ':' '{print $1}'`
restart_coord_bottom_line_number=`grep -n "COORD\$" $1 | grep -v "#" | tail -1 | awk -F ':' '{print $1}'`

sed -n "${restart_coord_top_line_number},${restart_coord_bottom_line_number}p" $1 >> tmp_coord

target_cell_top_line_number=`grep -n "&CELL\$" $2 | grep -v "#" | head -1 | awk -F ':' '{print $1}'`
target_cell_bottom_line_number=`grep -n "CELL\$" $2 | grep -v "#" | tail -1 | awk -F ':' '{print $1}'`

sed -i "${target_cell_top_line_number},${target_cell_bottom_line_number}d" $2
new_cell_line_number=`expr ${target_cell_top_line_number} - 1`
sed -i "${new_cell_line_number}r tmp_cell" $2
rm tmp_cell

target_coord_top_line_number=`grep -n "&COORD\$" $2 | grep -v "#" | head -1 | awk -F ':' '{print $1}'`
target_coord_bottom_line_number=`grep -n "COORD\$" $2 | grep -v "#" | tail -1 | awk -F ':' '{print $1}'`

sed -i "${target_coord_top_line_number},${target_coord_bottom_line_number}d" $2
new_coord_line_number=`expr $target_coord_top_line_number - 1`
sed -i "${new_coord_line_number}r tmp_coord" $2
rm tmp_coord

check_md=`grep "RUN_TYPE" $1 |  grep -v "#" | awk -F ' ' '{print $NF}'`
if [ $check_md == "MD" ] ;  then 
	restart_md_top_line_number=`grep -n "&MD\$" $1 | grep -v "#" | head -1 | awk -F ':' '{print $1}'`
	restart_md_bottom_line_number=`grep -n "MD\$" $1 | grep -v "#" | tail -1 | awk -F ':' '{print $1}'`
	
	sed -n "${restart_md_top_line_number},${restart_md_bottom_line_number}p" $1 >> tmp_md
	
	target_md_top_line_number=`grep -n "&MD\$" $2 | grep -v "#" | head -1 | awk -F ':' '{print $1}'`
	target_md_bottom_line_number=`grep -n "MD\$" $2 | grep -v "#" | tail -1 | awk -F ':' '{print $1}'`
	
	sed -i "${target_md_top_line_number},${target_md_bottom_line_number}d" $2
	
	new_md_line_number=`expr ${target_md_top_line_number} - 1`
	sed -i "${new_md_line_number}r tmp_md" $2
	rm tmp_md

        restart_velocity_top_line_number=`grep -n "&VELOCITY\$" $1 | grep -v "#" | head -1 | awk -F ':' '{print $1}'`
        restart_velocity_bottom_line_number=`grep -n "VELOCITY\$" $1 | grep -v "#" | tail -1 | awk -F ':' '{print $1}'`

        sed -n "${restart_velocity_top_line_number},${restart_velocity_bottom_line_number}p" $1 >> tmp_vel

        check_velocity_target=`grep "&VELOCITY" $2 | grep -v "#"`
        if [ $check_velocity_target ] ;  then
	        target_velocity_top_line_number=`grep -n "&VELOCITY\$" $2 | grep -v "#" | head -1 | awk -F ':' '{print $1}'`
	        target_velocity_bottom_line_number=`grep -n "VELOCITY\$" $2 | grep -v "#" | tail -1 | awk -F ':' '{print $1}'`
	
	        sed -i "${target_velocity_top_line_number},${target_velocity_bottom_line_number}d" $2
        	new_velocity_line_number=`expr $target_velocity_top_line_number - 1`
        	sed -i "${new_velocity_line_number}r tmp_vel" $2
		rm tmp_vel
	else
		target_coord_bottom_line_number=`grep -n "COORD\$" $2 | grep -v "#" | tail -1 | awk -F ':' '{print $1}'`
		new_velocity_line_number=$target_coord_bottom_line_number
		sed -i "${new_velocity_line_number}r tmp_vel" $2
		rm tmp_vel
	fi
else
	# This may cause issue when you have both GEO_OPT and MD sections in the input file
	restart_step_start_val_line_number=`grep -n "STEP_START_VAL" $1 | awk -F ':' '{print $1}'`
	if [ ${restart_step_start_val_line_number} ] ; then
		target_step_start_val_line_number=`grep -n "STEP_START_VAL" $2 | grep -v "#  " |  awk -F ':' '{print $1}'`	
		restart_step_start_val=`grep "STEP_START_VAL" $1`
		if [ ${target_step_start_val_line_number} ] ; then
			sed -i "${target_step_start_val_line_number}c $restart_step_start_val" $2
		else
			target_rms_force_line_number=`grep -n "RMS_FORCE" $2 | grep -v "#  " | awk -F ':' '{print $1}'`
			sed -i "${target_rms_force_line_number}a $restart_step_start_val" $2
		fi
	fi
fi
echo "Done!"
