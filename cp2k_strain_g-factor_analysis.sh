#!/bin/bash
# g-tensor vs strain: thin wrapper around cp2k_strain_analysis.sh --gtensor (same options, see -h).
impl="$(dirname "$(readlink -f "$0")")/cp2k_strain_analysis.sh"
[ -x "$impl" ] || impl="$(command -v cp2k_strain_analysis.sh)" || { echo "Error: cp2k_strain_analysis.sh not found (keep it next to this script or in PATH)" >&2; exit 1; }
exec "$impl" --gtensor "$@"
