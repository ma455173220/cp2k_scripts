#!/bin/bash
#Generate initial guessing trajectory from xyz file of every NEB point, and export corresponding energies
#Thin wrapper around NEB.sh --first (Written by Tian Lu, sobereva@sina.com). e.g. initNEB.sh conf 10
impl="$(dirname "$(readlink -f "$0")")/NEB.sh"
[ -x "$impl" ] || impl="$(command -v NEB.sh)" || { echo "Error: NEB.sh not found (keep it next to this script or in PATH)" >&2; exit 1; }
exec "$impl" --first "$@"
