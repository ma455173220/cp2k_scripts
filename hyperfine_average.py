#!/apps/python3/3.10.0/bin/python3

import os,sys,datetime

os.chdir(os.getcwd())


output_file = sys.argv[1]
number_of_rows = sys.argv[2:]

with open(output_file, 'r') as f:
    lines = f.readlines()
    for line in lines:
        if "Extracted value" in line:
            line_start = lines.index(line)
            line_start += 3 
            for i in number_of_rows:
                value_sum = 0
                line_end = line_start + int(i)
                value_lines = lines[line_start:line_end]
                for ii in value_lines:
                    value = ii.split('\t')[1:][0].strip().split()
                    if len(value) == 1:
                        value_sum += float(value[0])
                    else:
                        value = max(abs(float(value[0])), abs(float(value[1])), abs(float(value[2])))
                        value_sum += float(value)
                value_average = value_sum / int(i)
                print("%.8f" %value_average)
                line_start = line_end 
f.close()
