#!/bin/bash
#Generate final NEB trajectory from xyz file of every NEB point, and export corresponding energies
#(with --first: the initial guess trajectory, as initNEB.sh)
#Written by Tian Lu (sobereva@sina.com)
#
#Argument 1: Project name
#Argument 2: Number of points in the band
#Output [Project name]_traj.xyz and [Project name]_ene.txt
#  (--first: [Project name]_inittraj.xyz and [Project name]_initene.txt)
#e.g. NEB.sh conf 10      NEB.sh --first conf 10  (= initNEB.sh conf 10)
#

frame="last"
if [ "$1" == "--first" ] ; then
  frame="first"
  shift
elif [ "$1" == "--last" ] ; then
  shift
fi

if [ $# -ne 2 ] || ! [[ $2 =~ ^[0-9]+$ ]] ; then
  echo "Usage: $(basename "$0") [--first|--last] project_name number_of_points"
  exit 1
fi

if [ "$frame" == "last" ] ; then
  traj=$1_traj.xyz
  ene=$1_ene.txt
else
  traj=$1_inittraj.xyz
  ene=$1_initene.txt
fi

rm -f $traj
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
if [ "$frame" == "last" ] ; then
  tail -$nline "$1-pos-Replica_nr_${idx}-1.xyz" >> $traj
else
  head -$nline "$1-pos-Replica_nr_${idx}-1.xyz" >> $traj
fi
done
echo "Trajectory has been exported to $traj"
awk '/E =/ {i=i+1; printf "%s %16.8f\n", i, $6}' $traj > $ene
echo "Energies have been exported to $ene"
