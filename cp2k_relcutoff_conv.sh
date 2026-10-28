#!/bin/bash
# REL_CUTOFF convergence test: thin wrapper around cp2k_cutoff_conv.sh --rel (same options, see -h).
impl="$(dirname "$(readlink -f "$0")")/cp2k_cutoff_conv.sh"
[ -x "$impl" ] || impl="$(command -v cp2k_cutoff_conv.sh)" || { echo "Error: cp2k_cutoff_conv.sh not found (keep it next to this script or in PATH)" >&2; exit 1; }
exec "$impl" --rel "$@"
