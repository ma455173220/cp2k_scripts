# JobTrack - Enhanced Version

Fast job management for HPC calculations (VASP/CP2K) **and local scripts**.

## New Features ✨

- 🚀 **Local script support**: Run `workflow.sh` with `nohup` automatically
- 🔍 **Process tracking**: Monitor local jobs with PID
- 🎯 **Mixed workflow**: Manage HPC and local jobs together
- 🛑 **Kill command**: Stop local jobs easily

## Job Types

| Type | Detection | Submit Command | ID Format |
|------|-----------|----------------|-----------|
| PBS | `#PBS` directives | `qsub` | `12345.gadi-pbs` |
| Slurm | `#SBATCH` directives | `sbatch` | `67890` |
| **Local** | No scheduler directives | `nohup ... &` | **PID** |

## Quick Install

```bash
tar xzf jobtrack.tar.gz
./install.sh
```

## Usage

### Submit Jobs

```bash
# HPC jobs (auto-detected)
jts job.pbs          # PBS job
jts job.slurm        # Slurm job

# Local scripts (auto-detected)
jts workflow.sh      # Runs with nohup automatically
jts analysis.sh      # Any script without #PBS/#SBATCH
```

**How it works:**
- Script with `#PBS` → submitted via `qsub`
- Script with `#SBATCH` → submitted via `sbatch`
- Script without scheduler directives → runs with `nohup ... &`

### Manage Jobs

```bash
# Browse with FZF
jtf                  # Interactive browser (shows [LOCAL] tag)

# List jobs
jtl 50               # Shows both HPC and local jobs

# Today's summary
jtt                  # Separates HPC and local job counts

# Show details
jobtrack show 12345678.gadi-pbs    # HPC job
jobtrack show 98765                # Local job (PID)

# Kill local job
jobtrack kill 98765                # Kills process by PID
```

### Go to Directory

```bash
# Go to job directory (Fish only)
jtg 12345678         # HPC job
jtg 98765            # Local job
```

## Examples

### Typical Workflow

```bash
# Morning: Submit calculations
jts vasp_relax.pbs       # HPC job
jts prepare_data.sh      # Local preprocessing
jts cp2k_md.slurm        # Another HPC job

# Check status
jtt                      # Quick summary
# Output:
# Today's Summary
# 
# Total:     3 jobs
# HPC:       2 jobs
# Local:     1 jobs

# Browse jobs
jtf                      # Opens FZF browser
# Shows:
# 10:30:45 12345678.gadi-pbs calculation/relax
# 10:28:12 [LOCAL] 98765 preprocessing/data
# 10:25:33 87654321 md/equilibration
```

### Managing Local Jobs

```bash
# Submit local workflow
$ jts workflow.sh
Submitting local script with nohup...
✓ Script started: PID 98765
Output: /home/user/project/nohup_workflow.out
✓ Local job PID 98765 logged

# Check if still running
$ jobtrack show 98765
Job Details

Type:      LOCAL
PID:       98765
Status:    RUNNING
Submitted: 2026-01-17 10:28:12
Directory: /home/user/project

Process Info

UID        PID  PPID  C STIME TTY      TIME CMD
user     98765     1  0 10:28 ?        00:00:05 /bin/bash ./workflow.sh

# Kill if needed
$ jobtrack kill 98765
Killing process 98765...
✓ Process 98765 killed
```

## Date Grouping

Jobs automatically grouped by submission date with type indicators:

```
Recent 20 jobs

━━━ Today (2026-01-17) ━━━
10:30:45 12345678.gadi-pbs calculation/ZrS2
10:28:12 [LOCAL] 98765 preprocessing/data_prep
09:15:22 12345677.gadi-pbs defects/V_S

━━━ Yesterday (2026-01-16) ━━━
16:42:10 [LOCAL] 87654 analysis/post_process
14:20:31 12345676.gadi-pbs perovskites/BTO
```

## FZF Preview

### HPC Jobs (VASP)
```
╔════════════════════════════════════════════════╗
║              Job Details                        ║
╚════════════════════════════════════════════════╝

Submitted: 2026-01-17 10:30:45
Job ID:    12345678.gadi-pbs

Directory:
  /scratch/project/calculations/ZrS2

═══════════════════════════════════════════════
VASP Calculation
═══════════════════════════════════════════════

▶ OUTCAR
──────────────────────────────────────────────
  FREE ENERGIE OF THE ION-ELECTRON SYSTEM
  ...
```

### Local Jobs
```
╔════════════════════════════════════════════════╗
║              Job Details                        ║
╚════════════════════════════════════════════════╝

Submitted: 2026-01-17 10:28:12
PID:       98765
Status:    RUNNING

Directory:
  /home/user/project/preprocessing

═══════════════════════════════════════════════
Process Info
═══════════════════════════════════════════════

UID        PID  PPID  C STIME TTY      TIME CMD
user     98765     1  0 10:28 ?        00:00:05 /bin/bash ./workflow.sh

Local script output:
  ✓ nohup_workflow.out
```

## Commands Reference

```bash
jobtrack submit <script>   # Submit and log job (auto-detect type)
jobtrack list [n]          # List recent jobs (default: 20)
jobtrack today             # Today's summary (separate HPC/local)
jobtrack show <job_id>     # Show job details
jobtrack kill <pid>        # Kill local job (NEW)
jobtrack -h                # Help
```

## Features Comparison

| Feature | HPC Jobs | Local Jobs |
|---------|----------|------------|
| Submit | `qsub`/`sbatch` | `nohup ... &` |
| ID format | Job ID | PID |
| Status check | `qstat`/`squeue` | `ps` |
| Kill | `qdel`/`scancel` | `jobtrack kill` |
| FZF browser | ✅ | ✅ |
| Directory jump | ✅ | ✅ |
| Output files | OUTCAR/cp2k.out | nohup_*.out |

## Requirements

- Bash or Fish shell
- fzf: `conda install -c conda-forge fzf`
- PBS Pro or Slurm (optional, for HPC jobs)

## Aliases

Automatically added during installation:

### Bash
```bash
jt   → jobtrack
jts  → jobtrack submit
jtl  → jobtrack list
jtt  → jobtrack today
```

### Fish
```fish
jt   → jobtrack
jts  → jobtrack submit
jtl  → jobtrack list
jtf  → jobtrack_fzf
jtt  → jobtrack today
jtg  → jtg (go to directory)
```

## Files

- `jobtrack` - Main program
- `~/.jobtrack.log` - Job history (format: TIMESTAMP|DIR|JOB_ID|TYPE)
- `~/.config/fish/functions/jobtrack_*.fish` - Fish functions
- `nohup_<script>.out` - Local script output

## FZF Shortcuts

```
Enter   → Go to directory (in current shell)
Ctrl-Y  → Copy Job ID/PID to clipboard
Ctrl-D  → Delete task from log
ESC     → Exit
```

## Log Format (New)

```
# Old format (backward compatible):
2026-01-17 10:30:45|/path/to/dir|12345678.gadi-pbs

# New format (with type):
2026-01-17 10:30:45|/path/to/dir|12345678.gadi-pbs|PBS
2026-01-17 10:28:12|/path/to/dir|98765|LOCAL
2026-01-17 09:15:22|/path/to/dir|87654321|SLURM
```

## Migration from Old Version

The enhanced version is **backward compatible**. Existing log entries without TYPE field will work normally. New submissions will include the TYPE field.

## Tips

1. **Check local job output**: 
   ```bash
   tail -f nohup_workflow.out
   ```

2. **Find all local jobs today**:
   ```bash
   jtt | grep LOCAL
   ```

3. **Kill all local jobs** (be careful!):
   ```bash
   grep "$(date +%Y-%m-%d)" ~/.jobtrack.log | grep LOCAL | cut -d'|' -f3 | xargs -I {} jobtrack kill {}
   ```

4. **Monitor long-running local script**:
   ```bash
   jts long_analysis.sh
   watch -n 5 'jobtrack show <PID>'
   ```

## Uninstall

```bash
# Remove executable
rm ~/.local/bin/jobtrack

# Remove Fish functions
rm ~/.config/fish/functions/jobtrack_*.fish

# Remove aliases from ~/.bashrc and ~/.config/fish/config.fish
# (search for "# JobTrack aliases" and delete that section)

# Remove log
rm ~/.jobtrack.log
```

---

**Quick start:** 
```bash
jts workflow.sh    # Submit local script
jtf                # Browse all jobs
```
