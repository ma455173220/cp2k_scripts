#Generate final NEB trajectory from xyz file of every NEB point, and export corresponding energies
#Written by Tian Lu (sobereva@sina.com)
#
#Argument 1: Project name
#Argument 2: Number of points in the band
#Output [Project name]_traj.xyz and [Project name]_ene.txt
#e.g. NEB.sh conf 10
#
#!/bin/bash

rm -f $1_traj.xyz
if (($2<10)) ; then
  read nline < "$1-pos-Replica_nr_1-1.xyz"
else
  read nline < "$1-pos-Replica_nr_01-1.xyz"
fi
echo "Number of atoms: $nline"
((nline++))
((nline++))
for ((i=1;i<=$2;i=i+1))
do
if (($2<10)) ; then
  export idx=`printf "%01d\n" $i`
else
  export idx=`printf "%02d\n" $i`
fi
echo "processing $1-pos-Replica_nr_${idx}-1.xyz..."
tail -$nline "$1-pos-Replica_nr_${idx}-1.xyz" >> $1_traj.xyz
done
echo "Trajectory has been exported to $1_traj.xyz"
awk '/E =/ {i=i+1; printf "%s %16.8f\n", i, $6}' $1_traj.xyz > $1_ene.txt
echo "Energies have been exported to $1_ene.txt"

