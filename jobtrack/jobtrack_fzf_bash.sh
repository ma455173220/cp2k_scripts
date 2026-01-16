#!/bin/bash
# JobTrack - FZF Interactive Browser
# Dependencies: fzf

LOG_FILE="$HOME/.jobtrack.log"

# Colors
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Format task list for fzf - compact format
format_for_fzf() {
    tail -n 500 "$LOG_FILE" | grep -v '^#' | while IFS='|' read -r timestamp dir job_id; do
        # Shorten directory display (last 2 levels)
        short_dir=$(echo "$dir" | awk -F'/' '{n=NF; if(n>1) print $(n-1)"/"$n; else print $n}')
        # Compact format: timestamp | job_id | dir
        printf "%s | %s | %s\n" "$timestamp" "$job_id" "$short_dir"
    done | tac  # Reverse order, newest first
}

# Main FZF interface
main() {
    if ! command -v fzf &> /dev/null; then
        echo "Error: fzf not found"
        echo "Install: conda install -c conda-forge fzf"
        exit 1
    fi
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "Error: Log file not found: $LOG_FILE"
        echo "Submit a job first: jobtrack submit job.pbs"
        exit 1
    fi
    
    # Create temporary preview script
    local preview_script=$(mktemp)
    cat > "$preview_script" << 'PREVIEW_EOF'
#!/bin/bash
LOG_FILE="$HOME/.jobtrack.log"

# Colors
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

line="$1"

# Extract Job ID (format: TIMESTAMP | JOB_ID | SHORT_DIR)
job_id=$(echo "$line" | awk -F' [|] ' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')

if [ -z "$job_id" ]; then
    echo -e "${RED}Cannot parse Job ID${NC}"
    exit 1
fi

# Get full info from log
info=$(grep -F "$job_id" "$LOG_FILE" | tail -1)
if [ -z "$info" ]; then
    echo -e "${RED}Job not found: $job_id${NC}"
    exit 1
fi

IFS='|' read -r timestamp dir _ <<< "$info"

echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}              Job Details                         ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Submitted:${NC} $timestamp"
echo -e "${CYAN}Job ID:${NC}    $job_id"
echo ""
echo -e "${CYAN}Directory:${NC}"
echo -e "  $dir"
echo ""

# Check if directory exists
if [ ! -d "$dir" ]; then
    echo -e "${RED}⚠ Directory not found${NC}"
    exit 0
fi

# Check calculation type
is_vasp=false
is_cp2k=false

if [ -f "$dir/INCAR" ] || [ -f "$dir/POSCAR" ]; then
    is_vasp=true
fi

if [ -f "$dir/cp2k.inp" ]; then
    is_cp2k=true
fi

# VASP output
if [ "$is_vasp" = true ]; then
    echo -e "${BLUE}═════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}VASP Calculation${NC}"
    echo -e "${BLUE}═════════════════════════════════════════════════${NC}"
    echo ""
    
    # OUTCAR tail
    if [ -f "$dir/OUTCAR" ]; then
        echo -e "${GREEN}▶ OUTCAR${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────────${NC}"
        tail -13 "$dir/OUTCAR" 2>/dev/null || echo -e "${RED}Read failed${NC}"
        echo ""
    else
        echo -e "${RED}✗ OUTCAR not found${NC}"
        echo ""
    fi
    
    # vasp_log tail
    if [ -f "$dir/vasp_log" ]; then
        echo -e "${GREEN}▶ vasp_log${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────────${NC}"
        tail -6 "$dir/vasp_log" 2>/dev/null || echo -e "${RED}Read failed${NC}"
        echo ""
    fi
fi

# CP2K output
if [ "$is_cp2k" = true ]; then
    echo -e "${BLUE}═════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}CP2K Calculation${NC}"
    echo -e "${BLUE}═════════════════════════════════════════════════${NC}"
    echo ""
    
    # cp2k.out tail
    if [ -f "$dir/cp2k.out" ]; then
        echo -e "${GREEN}▶ cp2k.out${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────────${NC}"
        tail -10 "$dir/cp2k.out" 2>/dev/null || echo -e "${RED}Read failed${NC}"
        echo ""
    else
        echo -e "${RED}✗ cp2k.out not found${NC}"
        echo ""
    fi
fi

# Unknown type
if [ "$is_vasp" = false ] && [ "$is_cp2k" = false ]; then
    echo -e "${YELLOW}Unknown calculation type${NC}"
    echo ""
    echo -e "${BLUE}═══ Directory Contents (first 15 files) ═══${NC}"
    ls -lh "$dir" 2>/dev/null | head -16 | tail -15
fi
PREVIEW_EOF
    
    chmod +x "$preview_script"
    
    # Run FZF
    local selected=$(format_for_fzf | \
        fzf --ansi \
            --reverse \
            --height=100% \
            --header='Enter: cd | Ctrl-Y: Copy | Ctrl-D: Delete | ESC: Exit' \
            --preview "$preview_script {}" \
            --preview-window=right:60%:wrap \
            --bind "ctrl-y:execute-silent(echo {} | awk -F' [|] ' '{gsub(/^[ \\t]+|[ \\t]+\\$/, \"\", \\$2); print \\$2}' | tr -d '\\n' | xclip -selection clipboard 2>/dev/null || pbcopy 2>/dev/null || (echo -n {} | awk -F' [|] ' '{gsub(/^[ \\t]+|[ \\t]+\\$/, \"\", \\$2); print \\$2}' | printf \"\\033]52;c;%s\\a\" \"\$(base64 -w0 2>/dev/null || base64)\"))+abort" \
            --bind "ctrl-d:execute-silent(job_id=\$(echo {} | awk -F' [|] ' '{gsub(/^[ \\t]+|[ \\t]+\\$/, \"\", \\$2); print \\$2}'); grep -vF \"\$job_id\" $LOG_FILE > ${LOG_FILE}.tmp && mv ${LOG_FILE}.tmp $LOG_FILE)+reload(tail -n 500 $LOG_FILE | grep -v '^#' | while IFS='|' read -r ts dr ji; do sd=\$(echo \"\$dr\" | awk -F'/' '{n=NF; if(n>1) print \$(n-1)\"/\"\$n; else print \$n}'); printf \"%s | %s | %s\\n\" \"\$ts\" \"\$ji\" \"\$sd\"; done | tac)")
    
    # Cleanup
    rm -f "$preview_script"
    
    if [ -n "$selected" ]; then
        # Extract Job ID
        local job_id=$(echo "$selected" | awk -F' [|] ' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
        
        if [ -z "$job_id" ]; then
            echo -e "${RED}Error: Cannot extract Job ID${NC}"
            exit 1
        fi
        
        # Get directory from log
        local dir=$(grep -F "$job_id" "$LOG_FILE" | tail -1 | cut -d'|' -f2)
        
        if [ -z "$dir" ]; then
            echo -e "${RED}Error: Job directory not found${NC}"
            exit 1
        fi
        
        echo ""
        echo -e "${CYAN}Selected job:${NC} $job_id"
        echo -e "${CYAN}Directory:${NC}   $dir"
        echo ""
        
        # Enter directory
        if [ -d "$dir" ]; then
            echo "Entering directory..."
            local user_shell="${SHELL:-/bin/bash}"
            cd "$dir" && exec "$user_shell"
        else
            echo -e "${RED}Error: Directory does not exist - $dir${NC}"
            exit 1
        fi
    fi
}

main "$@"
