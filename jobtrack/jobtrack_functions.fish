# JobTrack - Additional Fish Functions

function jobtrack_list -d "List recent jobs"
    set -l count 20
    if test (count $argv) -gt 0
        set count $argv[1]
    end
    jobtrack list $count
end

function jobtrack_today -d "Today's jobs"
    jobtrack today
end

function jobtrack_submit -d "Submit job"
    if test (count $argv) -eq 0
        if test -f "job.pbs"
            jobtrack submit job.pbs
        else if test -f "job.slurm"
            jobtrack submit job.slurm
        else if test -f "job"
            jobtrack submit job
        else
            echo "Error: No job script found"
            echo "Usage: jobtrack_submit <script>"
            return 1
        end
    else
        jobtrack submit $argv[1]
    end
end

function jobtrack_show -d "Show job details"
    if test (count $argv) -eq 0
        echo "Usage: jobtrack_show <job_id>"
        return 1
    end
    jobtrack show $argv[1]
end
