# JobTrack Go - Jump to job directory
# Install: Save as ~/.config/fish/functions/jtg.fish

function jtg -d "Jump to job directory by Job ID"
    if test (count $argv) -eq 0
        echo "Usage: jtg <job_id>"
        echo ""
        echo "Examples:"
        echo "  jtg 12345678.gadi-pbs"
        echo "  jtg 9876543"
        return 1
    end
    
    set -l JOB_ID $argv[1]
    set -l LOG_FILE "$HOME/.jobtrack.log"
    set -l WORK_DIR ""
    
    # Try PBS
    if command -v qstat &> /dev/null
        set WORK_DIR (qstat -xwf $JOB_ID 2>/dev/null | grep Output_Path | awk -F ":" '{print $NF}' | awk -F "/" 'OFS="/"{$NF="";print}' | sed 's:/$::')
        
        if test -z "$WORK_DIR"; and test -f "$LOG_FILE"
            set WORK_DIR (grep -F "$JOB_ID" "$LOG_FILE" | tail -1 | cut -d'|' -f2)
        end
    end
    
    # Try Slurm
    if test -z "$WORK_DIR"; and command -v scontrol &> /dev/null
        set WORK_DIR (scontrol show job $JOB_ID 2>/dev/null | grep -oP 'WorkDir=\K[^ ]+')
        
        if test -z "$WORK_DIR"
            set WORK_DIR (sacct -j $JOB_ID --format=WorkDir -P --noheader 2>/dev/null | head -n 1)
        end
        
        if test -z "$WORK_DIR"; and test -f "$LOG_FILE"
            set WORK_DIR (grep -F "$JOB_ID" "$LOG_FILE" | tail -1 | cut -d'|' -f2)
        end
    end
    
    # Last resort: log only
    if test -z "$WORK_DIR"; and test -f "$LOG_FILE"
        set WORK_DIR (grep -F "$JOB_ID" "$LOG_FILE" | tail -1 | cut -d'|' -f2)
    end
    
    # Check if found
    if test -z "$WORK_DIR"
        set_color red
        echo "Error: Unable to find work directory for job $JOB_ID"
        set_color normal
        return 1
    end
    
    # Remove any whitespace
    set WORK_DIR (string trim $WORK_DIR)
    
    # Check if exists
    if not test -d "$WORK_DIR"
        set_color red
        echo "Error: Directory does not exist: $WORK_DIR"
        set_color normal
        return 1
    end
    
    # Change to directory in current shell
    echo ""
    set_color green
    echo "Job $JOB_ID found"
    set_color cyan
    echo "→ $WORK_DIR"
    set_color normal
    echo ""
    
    cd "$WORK_DIR"
    commandline -f repaint
end
