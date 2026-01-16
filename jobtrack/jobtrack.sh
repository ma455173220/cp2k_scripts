#!/bin/bash
# JobTrack - HPC Job Management Tool
# Supports VASP and CP2K, compatible with PBS Pro and Slurm

LOG_FILE="$HOME/.jobtrack.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# Detect scheduler
detect_scheduler_from_script() {
    local script="$1"
    if grep -q "^#PBS" "$script" 2>/dev/null; then
        echo "PBS"
    elif grep -q "^#SBATCH" "$script" 2>/dev/null; then
        echo "SLURM"
    else
        echo "UNKNOWN"
    fi
}

# Initialize
init_tracker() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "# JobTrack Log - Format: TIMESTAMP|DIR|JOB_ID" > "$LOG_FILE"
    fi
}

# Log submission
log_submission() {
    local submit_script="$1"
    local job_output="$2"
    local scheduler=$(detect_scheduler_from_script "$submit_script")
    
    local job_id
    if [ "$scheduler" = "PBS" ]; then
        job_id=$(echo "$job_output" | grep -oE '[0-9]+\.(gadi-pbs|setonix-pbs|r-man[0-9]+|[a-z0-9\-]+)')
    elif [ "$scheduler" = "SLURM" ]; then
        job_id=$(echo "$job_output" | grep -oE 'Submitted batch job [0-9]+' | awk '{print $4}')
    fi
    
    if [ -z "$job_id" ]; then
        echo -e "${RED}Error: Cannot extract Job ID${NC}"
        return 1
    fi
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp|$PWD|$job_id" >> "$LOG_FILE"
    echo -e "${GREEN}✓${NC} Job $job_id logged"
}

# Smart submit
smart_submit() {
    local submit_script="$1"
    
    if [ ! -f "$submit_script" ]; then
        echo -e "${RED}Error: Script not found${NC}"
        return 1
    fi
    
    local scheduler=$(detect_scheduler_from_script "$submit_script")
    
    if [ "$scheduler" = "UNKNOWN" ]; then
        echo -e "${RED}Error: Cannot detect scheduler${NC}"
        return 1
    fi
    
    local output
    if [ "$scheduler" = "PBS" ]; then
        output=$(qsub "$submit_script" 2>&1)
    elif [ "$scheduler" = "SLURM" ]; then
        output=$(sbatch "$submit_script" 2>&1)
    fi
    
    echo "$output"
    
    if [ $? -eq 0 ]; then
        log_submission "$submit_script" "$output"
    else
        echo -e "${RED}Submission failed${NC}"
        return 1
    fi
}

# Get relative date
get_relative_date() {
    local date_str="$1"
    local date_epoch=$(date -d "$date_str" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null)
    local today_epoch=$(date +%s)
    local diff_days=$(( (today_epoch - date_epoch) / 86400 ))
    
    if [ $diff_days -eq 0 ]; then
        echo "Today"
    elif [ $diff_days -eq 1 ]; then
        echo "Yesterday"
    elif [ $diff_days -lt 7 ]; then
        echo "$diff_days days ago"
    else
        echo "$date_str"
    fi
}

# List tasks
list_tasks() {
    local num="${1:-20}"
    echo -e "${BLUE}Recent $num jobs${NC}\n"
    
    local last_date=""
    tail -n "$num" "$LOG_FILE" | grep -v '^#' | tac | while IFS='|' read -r timestamp dir job_id; do
        local date=$(echo "$timestamp" | cut -d' ' -f1)
        local time=$(echo "$timestamp" | cut -d' ' -f2)
        
        if [ "$date" != "$last_date" ]; then
            [ -n "$last_date" ] && echo ""
            local relative=$(get_relative_date "$date")
            echo -e "${YELLOW}━━━ $relative ($date) ━━━${NC}"
            last_date="$date"
        fi
        
        local short_dir=$(echo "$dir" | awk -F'/' '{n=NF; if(n>1) print $(n-1)"/"$n; else print $n}')
        printf "${GRAY}%s${NC} ${CYAN}%s${NC} %s\n" "$time" "$job_id" "$short_dir"
    done
}

# Today's summary
today_summary() {
    local today=$(date '+%Y-%m-%d')
    local count=$(grep "^$today" "$LOG_FILE" | wc -l)
    
    echo -e "${BLUE}Today's Summary${NC}\n"
    echo -e "Submitted: ${GREEN}$count${NC} jobs\n"
    
    if [ $count -gt 0 ]; then
        grep "^$today" "$LOG_FILE" | while IFS='|' read -r timestamp dir job_id; do
            local time=$(echo "$timestamp" | cut -d' ' -f2)
            local short_dir=$(echo "$dir" | awk -F'/' '{n=NF; if(n>1) print $(n-1)"/"$n; else print $n}')
            printf "${GRAY}%s${NC} ${CYAN}%s${NC} %s\n" "$time" "$job_id" "$short_dir"
        done
        echo ""
    fi
    
    echo -e "${BLUE}Currently Running${NC}\n"
    if command -v qstat &> /dev/null; then
        qstat -u "$USER" 2>/dev/null || echo "Cannot get status"
    elif command -v squeue &> /dev/null; then
        squeue -u "$USER" 2>/dev/null || echo "Cannot get status"
    else
        echo "No scheduler detected"
    fi
}

# Show detail
show_detail() {
    local job_id="$1"
    local info=$(grep "$job_id" "$LOG_FILE" | tail -1)
    
    if [ -z "$info" ]; then
        echo -e "${RED}Job not found${NC}"
        return 1
    fi
    
    IFS='|' read -r timestamp dir job_id_log <<< "$info"
    
    echo -e "${BLUE}Job Details${NC}\n"
    echo -e "Job ID:    ${CYAN}$job_id_log${NC}"
    echo -e "Submitted: $timestamp"
    echo -e "Directory: $dir"
    echo ""
    
    echo -e "${BLUE}Scheduler Status${NC}\n"
    if command -v qstat &> /dev/null; then
        qstat -f "$job_id" 2>/dev/null || echo "Job completed"
    elif command -v squeue &> /dev/null; then
        scontrol show job "$job_id" 2>/dev/null || echo "Job completed"
    fi
    
    if [ -d "$dir" ]; then
        echo ""
        echo -e "${BLUE}Output Files${NC}\n"
        
        if [ -f "$dir/INCAR" ] || [ -f "$dir/POSCAR" ]; then
            echo "VASP:"
            [ -f "$dir/OUTCAR" ] && echo -e "  ${GREEN}✓${NC} OUTCAR" || echo -e "  ${RED}✗${NC} OUTCAR"
            [ -f "$dir/vasp_log" ] && echo -e "  ${GREEN}✓${NC} vasp_log" || echo -e "  ${RED}✗${NC} vasp_log"
        fi
        
        if [ -f "$dir/cp2k.inp" ]; then
            echo "CP2K:"
            [ -f "$dir/cp2k.out" ] && echo -e "  ${GREEN}✓${NC} cp2k.out" || echo -e "  ${RED}✗${NC} cp2k.out"
        fi
    fi
}

# Help
show_help() {
    cat << 'EOF'
JobTrack - HPC Job Management Tool

Usage: jobtrack <command> [options]

Commands:
  submit <script>      Submit and log job
  list [n]             List recent jobs (default: 20)
  today                Today's summary
  show <job_id>        Show job details
  help, -h             Show this help

Examples:
  jobtrack submit job.pbs
  jobtrack list 50
  jobtrack today

Aliases:
  jt   → jobtrack
  jts  → jobtrack submit
  jtl  → jobtrack list
  jtf  → jobtrack_fzf (FZF browser, Fish)
  jtt  → jobtrack today
  jtg  → Quick jump (Fish function)

EOF
}

# Main
main() {
    init_tracker
    
    case "${1:-help}" in
        submit) smart_submit "$2" ;;
        list|ls) list_tasks "${2:-20}" ;;
        today) today_summary ;;
        show|detail) show_detail "$2" ;;
        help|--help|-h) show_help ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}"
            echo "Use 'jobtrack -h' for help"
            exit 1
            ;;
    esac
}

main "$@"
