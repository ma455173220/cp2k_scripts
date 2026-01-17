#!/bin/bash
# JobTrack - HPC Job Management Tool
# Supports VASP and CP2K, compatible with PBS Pro, Slurm, and Local scripts

LOG_FILE="$HOME/.jobtrack.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Detect scheduler
detect_scheduler_from_script() {
    local script="$1"
    if grep -q "^#PBS" "$script" 2>/dev/null; then
        echo "PBS"
    elif grep -q "^#SBATCH" "$script" 2>/dev/null; then
        echo "SLURM"
    else
        echo "LOCAL"
    fi
}

# Initialize
init_tracker() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "# JobTrack Log - Format: TIMESTAMP|DIR|JOB_ID|TYPE" > "$LOG_FILE"
    fi
}

# Log submission
log_submission() {
    local submit_script="$1"
    local job_output="$2"
    local scheduler="$3"
    
    local job_id
    if [ "$scheduler" = "PBS" ]; then
        job_id=$(echo "$job_output" | grep -oE '[0-9]+\.(gadi-pbs|setonix-pbs|r-man[0-9]+|[a-z0-9\-]+)')
    elif [ "$scheduler" = "SLURM" ]; then
        job_id=$(echo "$job_output" | grep -oE 'Submitted batch job [0-9]+' | awk '{print $4}')
    elif [ "$scheduler" = "LOCAL" ]; then
        job_id="$job_output"  # PID passed directly
    fi
    
    if [ -z "$job_id" ]; then
        echo -e "${RED}Error: Cannot extract Job ID/PID${NC}"
        return 1
    fi
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp|$PWD|$job_id|$scheduler" >> "$LOG_FILE"
    
    if [ "$scheduler" = "LOCAL" ]; then
        echo -e "${GREEN}✓${NC} Local job PID $job_id logged"
    else
        echo -e "${GREEN}✓${NC} Job $job_id logged"
    fi
}

# Smart submit
smart_submit() {
    local submit_script="$1"
    
    if [ ! -f "$submit_script" ]; then
        echo -e "${RED}Error: Script not found${NC}"
        return 1
    fi
    
    local scheduler=$(detect_scheduler_from_script "$submit_script")
    
    local output
    if [ "$scheduler" = "PBS" ]; then
        output=$(qsub "$submit_script" 2>&1)
        echo "$output"
        if [ $? -eq 0 ]; then
            log_submission "$submit_script" "$output" "$scheduler"
        else
            echo -e "${RED}Submission failed${NC}"
            return 1
        fi
    elif [ "$scheduler" = "SLURM" ]; then
        output=$(sbatch "$submit_script" 2>&1)
        echo "$output"
        if [ $? -eq 0 ]; then
            log_submission "$submit_script" "$output" "$scheduler"
        else
            echo -e "${RED}Submission failed${NC}"
            return 1
        fi
    elif [ "$scheduler" = "LOCAL" ]; then
        # Make script executable
        chmod +x "$submit_script"
        
        # Get absolute path
        local script_abs=$(realpath "$submit_script")
        
        # Create nohup output file
        local nohup_out="nohup_$(basename "$submit_script" .sh).out"
        
        # Submit with nohup
        echo -e "${BLUE}Submitting local script with nohup...${NC}"
        nohup "$script_abs" > "$nohup_out" 2>&1 &
        local pid=$!
        
        # Check if process started
        sleep 0.5
        if ps -p $pid > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Script started: PID $pid"
            echo -e "${GRAY}Output: $PWD/$nohup_out${NC}"
            log_submission "$submit_script" "$pid" "$scheduler"
        else
            echo -e "${RED}✗${NC} Script failed to start"
            return 1
        fi
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
    tail -n "$num" "$LOG_FILE" | grep -v '^#' | tac | while IFS='|' read -r timestamp dir job_id type; do
        local date=$(echo "$timestamp" | cut -d' ' -f1)
        local time=$(echo "$timestamp" | cut -d' ' -f2)
        
        if [ "$date" != "$last_date" ]; then
            [ -n "$last_date" ] && echo ""
            local relative=$(get_relative_date "$date")
            echo -e "${YELLOW}━━━ $relative ($date) ━━━${NC}"
            last_date="$date"
        fi
        
        local short_dir=$(echo "$dir" | awk -F'/' '{n=NF; if(n>1) print $(n-1)"/"$n; else print $n}')
        
        # Add type indicator
        local type_display=""
        if [ "$type" = "LOCAL" ]; then
            type_display="${MAGENTA}[LOCAL]${NC} "
        fi
        
        printf "${GRAY}%s${NC} %s${CYAN}%s${NC} %s\n" "$time" "$type_display" "$job_id" "$short_dir"
    done
}

# Today's summary
today_summary() {
    local today=$(date '+%Y-%m-%d')
    local count=$(grep "^$today" "$LOG_FILE" | wc -l)
    local local_count=$(grep "^$today" "$LOG_FILE" | grep -c "|LOCAL$")
    local hpc_count=$((count - local_count))
    
    echo -e "${BLUE}Today's Summary${NC}\n"
    echo -e "Total:     ${GREEN}$count${NC} jobs"
    echo -e "HPC:       ${CYAN}$hpc_count${NC} jobs"
    echo -e "Local:     ${MAGENTA}$local_count${NC} jobs"
    echo ""
    
    if [ $count -gt 0 ]; then
        grep "^$today" "$LOG_FILE" | while IFS='|' read -r timestamp dir job_id type; do
            local time=$(echo "$timestamp" | cut -d' ' -f2)
            local short_dir=$(echo "$dir" | awk -F'/' '{n=NF; if(n>1) print $(n-1)"/"$n; else print $n}')
            
            local type_display=""
            if [ "$type" = "LOCAL" ]; then
                type_display="${MAGENTA}[LOCAL]${NC} "
            fi
            
            printf "${GRAY}%s${NC} %s${CYAN}%s${NC} %s\n" "$time" "$type_display" "$job_id" "$short_dir"
        done
        echo ""
    fi
    
    echo -e "${BLUE}Currently Running (HPC)${NC}\n"
    if command -v qstat &> /dev/null; then
        qstat -u "$USER" 2>/dev/null || echo "No PBS jobs"
    elif command -v squeue &> /dev/null; then
        squeue -u "$USER" 2>/dev/null || echo "No Slurm jobs"
    else
        echo "No HPC scheduler detected"
    fi
    
    echo ""
    echo -e "${BLUE}Currently Running (Local)${NC}\n"
    local local_running=0
    grep "^$today" "$LOG_FILE" | grep "|LOCAL$" | while IFS='|' read -r timestamp dir pid type; do
        if ps -p "$pid" > /dev/null 2>&1; then
            local short_dir=$(echo "$dir" | awk -F'/' '{n=NF; if(n>1) print $(n-1)"/"$n; else print $n}')
            printf "${MAGENTA}PID ${pid}${NC} - ${short_dir}\n"
            local_running=1
        fi
    done
    
    if [ $local_running -eq 0 ]; then
        echo "No local jobs running"
    fi
}

# Check process status
check_process_status() {
    local pid="$1"
    if ps -p "$pid" > /dev/null 2>&1; then
        echo "RUNNING"
    else
        echo "COMPLETED"
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
    
    IFS='|' read -r timestamp dir job_id_log type <<< "$info"
    
    echo -e "${BLUE}Job Details${NC}\n"
    echo -e "Type:      ${CYAN}$type${NC}"
    
    if [ "$type" = "LOCAL" ]; then
        echo -e "PID:       ${CYAN}$job_id_log${NC}"
        local status=$(check_process_status "$job_id_log")
        if [ "$status" = "RUNNING" ]; then
            echo -e "Status:    ${GREEN}RUNNING${NC}"
        else
            echo -e "Status:    ${GRAY}COMPLETED${NC}"
        fi
    else
        echo -e "Job ID:    ${CYAN}$job_id_log${NC}"
    fi
    
    echo -e "Submitted: $timestamp"
    echo -e "Directory: $dir"
    echo ""
    
    if [ "$type" != "LOCAL" ]; then
        echo -e "${BLUE}Scheduler Status${NC}\n"
        if [ "$type" = "PBS" ] && command -v qstat &> /dev/null; then
            qstat -f "$job_id" 2>/dev/null || echo "Job completed or not found"
        elif [ "$type" = "SLURM" ] && command -v squeue &> /dev/null; then
            scontrol show job "$job_id" 2>/dev/null || echo "Job completed or not found"
        fi
    else
        # Show process info for local jobs
        echo -e "${BLUE}Process Info${NC}\n"
        if ps -p "$job_id_log" > /dev/null 2>&1; then
            ps -f -p "$job_id_log"
        else
            echo "Process completed"
        fi
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
        
        # Check for nohup output
        local nohup_files=$(ls "$dir"/nohup*.out 2>/dev/null)
        if [ -n "$nohup_files" ]; then
            echo ""
            echo "Local script output:"
            for f in $nohup_files; do
                echo -e "  ${GREEN}✓${NC} $(basename "$f")"
            done
        fi
    fi
}

# Kill local job
kill_local_job() {
    local pid="$1"
    
    if [ -z "$pid" ]; then
        echo -e "${RED}Error: No PID provided${NC}"
        return 1
    fi
    
    local info=$(grep "$pid" "$LOG_FILE" | grep "|LOCAL$" | tail -1)
    if [ -z "$info" ]; then
        echo -e "${RED}Error: Local job not found${NC}"
        return 1
    fi
    
    if ps -p "$pid" > /dev/null 2>&1; then
        echo -e "${YELLOW}Killing process $pid...${NC}"
        kill "$pid" 2>/dev/null
        sleep 1
        
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${YELLOW}Process still running, using SIGKILL...${NC}"
            kill -9 "$pid" 2>/dev/null
        fi
        
        if ! ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Process $pid killed"
        else
            echo -e "${RED}✗${NC} Failed to kill process"
            return 1
        fi
    else
        echo -e "${GRAY}Process $pid already completed${NC}"
    fi
}

# Help
show_help() {
    cat << 'EOF'
JobTrack - HPC Job Management Tool

Usage: jobtrack <command> [options]

Commands:
  submit <script>      Submit and log job (PBS/Slurm/Local)
  list [n]             List recent jobs (default: 20)
  today                Today's summary
  show <job_id>        Show job details
  kill <pid>           Kill local job by PID
  help, -h             Show this help

Examples:
  # HPC jobs
  jobtrack submit job.pbs
  jobtrack submit job.slurm
  
  # Local scripts (automatically detected)
  jobtrack submit workflow.sh
  
  # Other commands
  jobtrack list 50
  jobtrack today
  jobtrack show 12345678.gadi-pbs
  jobtrack show 98765  # Local PID
  jobtrack kill 98765  # Kill local job

Job Types:
  PBS      - #PBS directives detected
  SLURM    - #SBATCH directives detected  
  LOCAL    - No scheduler directives (runs with nohup)

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
        kill) kill_local_job "$2" ;;
        help|--help|-h) show_help ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}"
            echo "Use 'jobtrack -h' for help"
            exit 1
            ;;
    esac
}

main "$@"
