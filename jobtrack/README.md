# JobTrack

Fast job management for HPC calculations (VASP/CP2K).

## Features

- ⚡ Instant directory switching
- 📅 Date grouping (Today, Yesterday, N days ago)
- 🎯 Minimal output
- 🔍 FZF interactive browser
- 📝 Auto-detect PBS/Slurm

## Quick Install

```bash
tar xzf jobtrack.tar.gz
./install.sh
```

The installer will:
- Ask for installation directory (default: `~/.local/bin`)
- Install Fish functions automatically
- Add aliases to `.bashrc` and `.config/fish/config.fish`
- Check and configure PATH

## Usage

```bash
# Submit job
jobtrack submit job.pbs
# or: jts job.pbs

# Browse with FZF
jobtrack_fzf
# or: jtf

# List jobs (date grouped)
jobtrack list 50
# or: jtl 50

# Today's summary
jobtrack today
# or: jtt

# Go to job directory (queries scheduler)
jobtrack goto 12345678.gadi-pbs
# or: jtg 12345678
# Works with running jobs (PBS/Slurm) and completed jobs (from log)
```

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
jtg  → jtg (independent function)
```

**Note:** `jtg` is an independent Fish function (like `jtf`), not a shell alias.

## Date Grouping

Jobs automatically grouped by submission date:

```
Recent 20 jobs

━━━ Today (2026-01-16) ━━━
10:30:45 12345678.gadi-pbs calculation/ZrS2
09:15:22 12345677.gadi-pbs defects/V_S

━━━ Yesterday (2026-01-15) ━━━
16:42:10 12345676.gadi-pbs perovskites/BTO

━━━ 2 days ago (2026-01-14) ━━━
11:05:18 12345674.gadi-pbs bulk/relax
```

## FZF Preview

VASP output with clear separation:

```
VASP Calculation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

OUTCAR (last 13 lines)
  FREE ENERGIE OF THE ION-ELECTRON SYSTEM
  ...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

vasp_log (last 6 lines)
  DAV:  12    -0.123E+02   -0.123E-04
  ...
```

## Requirements

- Fish shell (for FZF browser)
- fzf: `conda install -c conda-forge fzf`
- PBS Pro or Slurm

## Commands

```bash
jobtrack submit <script>   # Submit and log job
jobtrack list [n]          # List recent jobs (default: 20)
jobtrack today             # Today's summary
jobtrack show <job_id>     # Show job details
jobtrack -h                # Help
```

### Additional Fish Functions

```fish
jtf <job_id>   # FZF browser (interactive)
jtg <job_id>   # Quick jump (direct)
```

### jtg - Quick Job Directory Jump (Fish only)

`jtg` is an independent Fish function that jumps to job directories:

```fish
# Fast - changes directory in current shell
jtg 12345678.gadi-pbs      # PBS job
jtg 9876543                # Slurm job
```

**How it works:**
1. Queries PBS (`qstat -xwf`) or Slurm (`scontrol`/`sacct`)
2. Falls back to jobtrack log for completed jobs
3. **Changes directory in current shell** (like jtf's Enter)
4. **No .bashrc modifications needed** - just a `.fish` file

**Implementation:**
- Independent Fish function in `~/.config/fish/functions/jtg.fish`
- No shell configuration changes required
- Same speed as jtf's Enter (~0.01s)

**Fish only:** Bash users can use `jtf` (FZF browser) instead.

## Files

- `jobtrack` - Main program
- `~/.jobtrack.log` - Job history
- `~/.config/fish/functions/jobtrack_*.fish` - Fish functions

## FZF Shortcuts

### Bash version (`jobtrack_fzf_bash.sh`)
```bash
Enter   → Go to directory (in current shell)
Ctrl-Y  → Copy Job ID to clipboard
Ctrl-D  → Delete task from log
ESC     → Exit
```

### Fish version (`jtf` or `jobtrack_fzf`)
```fish
Enter   → Go to directory (in current shell)
Ctrl-Y  → Copy Job ID to clipboard
Ctrl-D  → Delete task from log  ← Now supported!
ESC     → Exit
```

**Implementation:** Fish version uses separate helper scripts for delete and reload operations to avoid complex string escaping.

## jtg vs jtf (Fish only)

| Feature | jtg | jtf |
|---------|-----|-----|
| Speed | ⚡ Instant | 🐢 Opens interface |
| Use case | Know Job ID | Browse/search |
| Running jobs | ✅ Queries scheduler | ❌ Log only |
| Preview | ❌ | ✅ OUTCAR/vasp_log |
| Copy ID | ❌ | ✅ Ctrl-Y |
| Delete | ❌ | ✅ Ctrl-D |
| Implementation | `.fish` function | `.fish` function |
| Config needed | ❌ None | ❌ None |

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

**Quick start:** Run `jtf` to browse jobs!
