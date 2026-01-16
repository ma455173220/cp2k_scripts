# JobTrack - Fish Function (FZF Browser with Ctrl-D delete)
# Install: Save as ~/.config/fish/functions/jobtrack_fzf.fish

function jobtrack_fzf -d "JobTrack FZF browser"
    set -l LOG_FILE "$HOME/.jobtrack.log"
    
    if not test -f "$LOG_FILE"
        echo "Error: Log file not found"
        echo "Submit a job first: jobtrack submit job.pbs"
        return 1
    end
    
    if not command -v fzf &> /dev/null
        echo "Error: fzf not found"
        echo "Install: conda install -c conda-forge fzf"
        return 1
    end
    
    # Create preview script
    set -l preview_script (mktemp)
    
    echo '#!/bin/bash
LOG_FILE="$HOME/.jobtrack.log"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

line="$1"
job_id=$(echo "$line" | awk -F" [|] " "{gsub(/^[ \\t]+|[ \\t]+\$/, \"\", \$2); print \$2}")

[ -z "$job_id" ] && echo -e "${RED}Cannot parse Job ID${NC}" && exit 1

info=$(grep -F "$job_id" "$LOG_FILE" | tail -1)
[ -z "$info" ] && echo -e "${RED}Job not found${NC}" && exit 1

IFS="|" read -r timestamp dir _ <<< "$info"

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

[ ! -d "$dir" ] && echo -e "${RED}⚠ Directory not found${NC}" && exit 0

is_vasp=false
is_cp2k=false

[ -f "$dir/INCAR" ] || [ -f "$dir/POSCAR" ] && is_vasp=true
[ -f "$dir/cp2k.inp" ] && is_cp2k=true

if [ "$is_vasp" = true ]; then
    echo -e "${BLUE}═════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}VASP Calculation${NC}"
    echo -e "${BLUE}═════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ -f "$dir/OUTCAR" ]; then
        echo -e "${GREEN}▶ OUTCAR${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────────${NC}"
        tail -13 "$dir/OUTCAR" 2>/dev/null || echo -e "${RED}Read failed${NC}"
        echo ""
    else
        echo -e "${RED}✗ OUTCAR not found${NC}"
        echo ""
    fi
    
    if [ -f "$dir/vasp_log" ]; then
        echo -e "${GREEN}▶ vasp_log${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────────${NC}"
        tail -6 "$dir/vasp_log" 2>/dev/null || echo -e "${RED}Read failed${NC}"
        echo ""
    fi
fi

if [ "$is_cp2k" = true ]; then
    echo -e "${BLUE}═════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}CP2K Calculation${NC}"
    echo -e "${BLUE}═════════════════════════════════════════════════${NC}"
    echo ""
    
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

if [ "$is_vasp" = false ] && [ "$is_cp2k" = false ]; then
    echo -e "${YELLOW}Unknown calculation type${NC}"
    echo ""
    echo -e "${BLUE}═══ Directory Contents (first 15 files) ═══${NC}"
    ls -lh "$dir" 2>/dev/null | head -16 | tail -15
fi
' > $preview_script
    
    chmod +x $preview_script
    
    # Create delete helper script
    set -l delete_script (mktemp)
    echo '#!/bin/bash
LOG_FILE="$HOME/.jobtrack.log"
line="$1"
job_id=$(echo "$line" | awk -F" [|] " "{gsub(/^[ \\t]+|[ \\t]+\$/, \"\", \$2); print \$2}")
[ -n "$job_id" ] && grep -vF "$job_id" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
' > $delete_script
    chmod +x $delete_script
    
    # Create reload script
    set -l reload_script (mktemp)
    echo '#!/bin/bash
LOG_FILE="$HOME/.jobtrack.log"
tail -n 500 "$LOG_FILE" | grep -v "^#" | while IFS="|" read -r ts dr ji; do
    sd=$(echo "$dr" | awk -F"/" "{n=NF; if(n>1) print \$(n-1)\"/\"\$n; else print \$n}")
    printf "%s | %s | %s\\n" "$ts" "$ji" "$sd"
done | tac
' > $reload_script
    chmod +x $reload_script
    
    # Format list - compact format
    set -l formatted_list (tail -n 500 "$LOG_FILE" | grep -v '^#' | while read -l line
        set -l parts (string split '|' $line)
        if test (count $parts) -ge 3
            set -l timestamp $parts[1]
            set -l dir $parts[2]
            set -l job_id $parts[3]
            
            set -l short_dir (echo $dir | awk -F'/' '{n=NF; if(n>1) print $(n-1)"/"$n; else print $n}')
            
            # Compact format: timestamp | job_id | dir
            printf "%s | %s | %s\n" "$timestamp" "$job_id" "$short_dir"
        end
    end | tac)
    
    # Run FZF - compact header
    set -l selected (printf '%s\n' $formatted_list | fzf \
        --ansi \
        --reverse \
        --height=100% \
        --header='Enter: cd | Ctrl-Y: Copy | Ctrl-D: Delete | ESC: Exit' \
        --preview "$preview_script {}" \
        --preview-window=right:60%:wrap \
        --bind "ctrl-y:execute-silent(echo {} | awk -F' [|] ' '{gsub(/^[ \\t]+|[ \\t]+\\\$/, \"\", \\\$2); print \\\$2}' | tr -d '\\n' | xclip -selection clipboard 2>/dev/null || pbcopy 2>/dev/null)+abort" \
        --bind "ctrl-d:execute-silent($delete_script {})+reload($reload_script)")
    
    # Cleanup
    rm -f $preview_script $delete_script $reload_script
    
    [ -z "$selected" ] && return 0
    
    set -l job_id (echo $selected | awk -F' [|] ' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
    
    if test -z "$job_id"
        echo "Error: Cannot extract Job ID"
        return 1
    end
    
    set -l target_dir (grep -F "$job_id" "$LOG_FILE" | tail -1 | cut -d'|' -f2)
    
    if test -z "$target_dir"
        echo "Error: Directory not found"
        return 1
    end
    
    if not test -d "$target_dir"
        echo "Error: Directory does not exist"
        return 1
    end
    
    echo ""
    set_color cyan
    echo "Selected job: $job_id"
    echo "Directory:    $target_dir"
    set_color normal
    echo ""
    cd "$target_dir"
    commandline -f repaint
end
