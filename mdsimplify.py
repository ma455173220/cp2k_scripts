#!/home/561/hm1876/.local/miniconda3/bin/python
'''
script to repick xyz from cp2k-pos* for every 10 or 20 structure.
'''
import sys,math,linecache

inputFile = str(sys.argv[1])
numOfAtoms = (linecache.getline(inputFile,1)).strip()
N = int(numOfAtoms) + 2
print("number of Atoms:", int(numOfAtoms))

count = -1
for count, line in enumerate(open(inputFile, 'r')):
    pass
count += 1
print(count)

O = (count//N)/int(sys.argv[2])
print(O)

Output = open('newpos.xyz','w')
for i in range(0,int(O)+1):
    for j in range(1,N+1):
        results = (linecache.getline(inputFile,i*int(sys.argv[2])*N+j)).strip()
        Output.write(results)
        Output.write("\n")
Output.close()
