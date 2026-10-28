#!/bin/bash
# EPS_SCHWARZ test table: thin wrapper around kpoints_analyse.sh --preset eps_schwarz (same options, see -h).
impl="$(dirname "$(readlink -f "$0")")/kpoints_analyse.sh"
[ -x "$impl" ] || impl="$(command -v kpoints_analyse.sh)" || { echo "Error: kpoints_analyse.sh not found (keep it next to this script or in PATH)" >&2; exit 1; }
exec "$impl" --preset eps_schwarz "$@"
