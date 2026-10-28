#!/usr/bin/env python3

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
            # keep only data rows: skip blank lines and "----" separators
            # (written between atoms by extract-hyperfine.sh in multi-dir mode)
            data_lines = [l for l in lines[line_start:] if l.strip() and not l.strip().startswith('----')]
            line_start = 0
            for i in number_of_rows:
                value_sum = 0
                line_end = line_start + int(i)
                value_lines = data_lines[line_start:line_end]
                for ii in value_lines:
                    # value is the last tab-separated column:
                    #   single dir: atom<TAB>value      multi dir: dir<TAB>atom<TAB>value
                    value = ii.rstrip('\n').split('\t')[-1].strip().split()
                    if len(value) == 1:
                        value_sum += float(value[0])
                    else:
                        value = max(abs(float(value[0])), abs(float(value[1])), abs(float(value[2])))
                        value_sum += float(value)
                value_average = value_sum / int(i)
                print("%.8f" %value_average)
                line_start = line_end 
f.close()
