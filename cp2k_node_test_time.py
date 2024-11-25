#!/apps/python3/3.10.0/bin/python3
import re
from datetime import datetime
import os

# Get a sorted list of directories starting with 'node_', sorted by the number after 'node_'
node_folders = sorted([folder for folder in os.listdir('.') if folder.startswith('node_') and os.path.isdir(folder)], key=lambda x: int(x.split('_')[1]))

# Loop through sorted directories
for folder_name in node_folders:
    # Path to cp2k.out file within the folder
    cp2k_out_path = os.path.join(folder_name, 'cp2k.out')
    
    # Check if cp2k.out file exists
    if os.path.exists(cp2k_out_path):
        # Read the content of the cp2k.out file
        with open(cp2k_out_path, 'r') as file:
            content = file.read()

        # Use regular expressions to extract start time and end time
        start_time_match = re.search(r'PROGRAM STARTED AT\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)', content)
        end_time_match = re.search(r'PROGRAM ENDED AT\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)', content)

        # Check if both start and end times were successfully matched
        if start_time_match and end_time_match:
            start_time_str = start_time_match.group(1)
            end_time_str = end_time_match.group(1)

            # Convert the strings to datetime objects
            start_time = datetime.strptime(start_time_str, "%Y-%m-%d %H:%M:%S.%f")
            end_time = datetime.strptime(end_time_str, "%Y-%m-%d %H:%M:%S.%f")

            # Calculate the time difference
            duration = end_time - start_time

            # Output the runtime in seconds
            duration_in_seconds = duration.total_seconds()
            print(f"Folder: {folder_name}, Total run time: {duration_in_seconds} seconds")
        else:
            print(f"Folder: {folder_name}, Could not find start or end time in the file.")
    else:
        print(f"Folder: {folder_name}, cp2k.out file not found.")
