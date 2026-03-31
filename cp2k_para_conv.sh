#!/usr/bin/env bash
set -euo pipefail

INP_FILE=""
PARAM=""
VALUES=()
EXTRA_FILES=()
JOB_SCRIPT=""
CLEAN_DIR=0

SCRIPT_NAME="$(basename "$0")"

usage() {
cat <<'EOF'
cp2k_para_conv.sh
用途：对 CP2K .inp 文件中的指定参数生成多组测试文件夹，并可选择性提交任务

用法：
  bash cp2k_para_conv.sh -p PARAM -v "val1 val2 ..." [选项]

参数：
  -p  （必填）要测试的参数名，如 CUTOFF、REL_CUTOFF、EPS_SCF
      多值参数（k点等）可用冒号替代空格，如 "MONKHORST-PACK:2:2:2"
  -v  （必填）测试值列表，空格分隔，引号括起；"none" 表示注释掉该参数
  -i  （可选）CP2K 输入文件路径（默认：当前目录唯一的 .inp 文件）
  -j  （可选）提交脚本文件名（如 job.sh）；指定后询问是否提交
  -f  （可选）额外要复制的文件，可重复指定多次
  -c  （可选）若目录已存在，先清空再重建（默认：合并写入）
  -h  显示此帮助

示例：
  bash cp2k_para_conv.sh -p CUTOFF -v "300 400 500 600" -j job.sh
  bash cp2k_para_conv.sh -p EPS_SCF -v "1.0E-5 1.0E-6 1.0E-7" -j job.sh
  bash cp2k_para_conv.sh -p SCHEME -v "MONKHORST-PACK:2:2:2 MONKHORST-PACK:4:4:4" -j job.sh
  bash cp2k_para_conv.sh -p SCF_GUESS -v "none RESTART" -j job.sh
  bash cp2k_para_conv.sh -p CUTOFF -v "400 500" -f BASIS_MOLOPT -f GTH_POTENTIALS
EOF
}

error_usage() {
    printf '\n  [错误] %s\n\n' "$1" >&2
    usage >&2
    exit 1
}

sanitize_name() {
    printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-zA-Z0-9._-]/_/g'
}

detect_scheduler() {
    if command -v qsub >/dev/null 2>&1; then
        echo "pbs"
    elif command -v sbatch >/dev/null 2>&1; then
        echo "slurm"
    else
        echo "none"
    fi
}

while getopts ":p:v:i:j:f:ch" opt; do
    case "$opt" in
        p) PARAM="$OPTARG" ;;
        v) read -r -a VALUES <<< "$OPTARG" ;;
        i) INP_FILE="$OPTARG" ;;
        j) JOB_SCRIPT="$OPTARG" ;;
        f) EXTRA_FILES+=("$OPTARG") ;;
        c) CLEAN_DIR=1 ;;
        h) usage; exit 0 ;;
        :) error_usage "选项 -$OPTARG 需要参数" ;;
        \?) error_usage "未知选项 -$OPTARG" ;;
    esac
done

[[ -z "$PARAM" ]] && error_usage "请用 -p 指定参数名"
[[ ${#VALUES[@]} -eq 0 ]] && error_usage "请用 -v 指定至少一个测试值"

command -v python3 >/dev/null 2>&1 || error_usage "未找到 python3，请先加载或安装 python3"

if [[ -z "$INP_FILE" ]]; then
    inp_files=()
    while IFS= read -r -d '' f; do
        inp_files+=("$f")
    done < <(find . -maxdepth 1 -type f -name "*.inp" -print0)

    if [[ ${#inp_files[@]} -eq 0 ]]; then
        error_usage "当前目录未找到 .inp 文件，请用 -i 指定"
    elif [[ ${#inp_files[@]} -gt 1 ]]; then
        printf '  [发现多个 .inp 文件]：\n' >&2
        for f in "${inp_files[@]}"; do
            printf '    %s\n' "$f" >&2
        done
        error_usage "请用 -i 指定目标文件"
    else
        INP_FILE="${inp_files[0]}"
        printf '[提示] 自动使用：%s\n' "$INP_FILE"
    fi
fi

[[ ! -f "$INP_FILE" ]] && error_usage "找不到输入文件：$INP_FILE"
[[ -n "$JOB_SCRIPT" && ! -f "$JOB_SCRIPT" ]] && error_usage "找不到提交脚本：$JOB_SCRIPT"

INP_BASENAME="$(basename "$INP_FILE")"

EXTRA_LINKS=()
while IFS= read -r -d '' lnk; do
    EXTRA_LINKS+=("$(basename "$lnk")")
done < <(find . -maxdepth 1 -type l -print0 2>/dev/null)

if [[ ${#EXTRA_FILES[@]} -eq 0 ]]; then
    while IFS= read -r -d '' f; do
        fname="$(basename "$f")"
        case "$fname" in
            "$SCRIPT_NAME"|"$INP_BASENAME"|*.out|*.log|*.bak) continue ;;
        esac
        EXTRA_FILES+=("$fname")
    done < <(find . -maxdepth 1 -type f -print0)
    printf '[提示] 未指定 -f，将复制筛选后的普通文件（共 %d 个）\n' "${#EXTRA_FILES[@]}"
fi

for f in "${EXTRA_FILES[@]}"; do
    if [[ ! -f "$f" && ! -L "$f" ]]; then
        printf '  [警告] 找不到文件：%s，将跳过\n' "$f" >&2
    fi
done

printf '========================================\n'
printf '  参数：%s\n' "$PARAM"
printf '  测试值：%s\n' "${VALUES[*]}"
printf '  源文件：%s\n' "$INP_FILE"
printf '  附加文件（%d 个）：%s\n' "${#EXTRA_FILES[@]}" "${EXTRA_FILES[*]:-（无）}"
[[ ${#EXTRA_LINKS[@]} -gt 0 ]] && printf '  软链接（%d 个）：%s\n' "${#EXTRA_LINKS[@]}" "${EXTRA_LINKS[*]}"
[[ -n "$JOB_SCRIPT" ]] && printf '  提交脚本：%s\n' "$JOB_SCRIPT"
[[ "$CLEAN_DIR" -eq 1 ]] && printf '  模式：清空已存在目录（-c）\n'
printf '========================================\n'

modify_inp() {
    local src="$1"
    local dst="$2"
    local param="$3"
    local val="$4"

    python3 - "$src" "$dst" "$param" "$val" <<'PYEOF'
import sys
import re

src, dst, param, val = sys.argv[1:]
write_val = val.replace(":", " ")
val_lc = val.lower()

pat_active = re.compile(
    r'^(\s*)(' + re.escape(param) + r')(\s+)(\S.*?)(\s*(?:#.*)?)$',
    re.IGNORECASE
)
pat_commented = re.compile(
    r'^(\s*)#\s*(' + re.escape(param) + r')(\s+)(\S.*?)(\s*(?:#.*)?)$',
    re.IGNORECASE
)

def build_line(indent, pname, new_val, tail_comment):
    comment_str = f"  {tail_comment.strip()}" if tail_comment.strip() else ""
    return f"{indent}{pname}  {new_val}{comment_str}\n"

with open(src, encoding="utf-8", newline="") as fh:
    raw = fh.read().replace("\r\n", "\n").replace("\r", "\n")
lines = raw.splitlines(keepends=True)

result = []
modified = False
match_count = 0

for line in lines:
    stripped = line.rstrip("\n")
    m_active = pat_active.match(stripped)
    m_commented = pat_commented.match(stripped)
    if m_active or m_commented:
        match_count += 1

    if not modified:
        if val_lc == "none":
            if m_active:
                tail = m_active.group(5)
                line = f"{m_active.group(1)}# {m_active.group(2)}  {m_active.group(4)}{tail}\n"
                modified = True
        else:
            if m_active:
                line = build_line(m_active.group(1), m_active.group(2), write_val, m_active.group(5))
                modified = True
            elif m_commented:
                line = build_line(m_commented.group(1), m_commented.group(2), write_val, m_commented.group(5))
                modified = True

    result.append(line)

if match_count > 1:
    sys.stderr.write(f"  [警告] 参数 {param} 匹配到 {match_count} 处，仅修改首个匹配\n")

if not modified:
    if val_lc == "none":
        sys.stderr.write(f"  [提示] {param} 未找到激活行，无需注释（文件未修改）\n")
    else:
        result.append(f"\n  {param}  {write_val}\n")
        sys.stderr.write(f"  [追加] 未找到 {param}，已追加到文件末尾\n")

with open(dst, "w", encoding="utf-8") as fh:
    fh.writelines(result)

if modified:
    if val_lc == "none":
        sys.stderr.write(f"  已注释 {param}\n")
    else:
        sys.stderr.write(f"  已设置 {param}  →  {write_val}\n")
PYEOF
}

GENERATED_DIRS=()

for val in "${VALUES[@]}"; do
    val_lc="$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')"
    safe_param="$(sanitize_name "$PARAM")"
    safe_val="$(sanitize_name "$val")"

    if [[ "$val_lc" == "none" ]]; then
        dir_name="${safe_param}_none"
    else
        dir_name="${safe_param}_${safe_val}"
    fi

    [[ -z "$dir_name" || "$dir_name" == "/" || "$dir_name" == "." ]] && {
        printf '  [错误] 非法目录名：%s\n' "$dir_name" >&2
        exit 1
    }

    if [[ -d "$dir_name" ]]; then
        if [[ "$CLEAN_DIR" -eq 1 ]]; then
            printf '[提示] 清空已存在目录：%s\n' "$dir_name"
            rm -rf -- "$dir_name"
        else
            printf '[警告] 目录已存在，合并写入（旧文件不删除）：%s\n' "$dir_name" >&2
        fi
    fi
    mkdir -p "$dir_name"

    target_inp="${dir_name}/${INP_BASENAME}"
    if ! modify_output=$(modify_inp "$INP_FILE" "$target_inp" "$PARAM" "$val" 2>&1); then
        printf '  [错误] 修改 .inp 失败，跳过：%s\n' "$dir_name" >&2
        continue
    fi
    printf '%s\n' "$modify_output" | sed "s/^/  [${dir_name}]/"

    for f in "${EXTRA_FILES[@]}"; do
        [[ "$(basename "$f")" == "$INP_BASENAME" ]] && continue
        if [[ -f "$f" || -L "$f" ]]; then
            cp "$f" "${dir_name}/"
            printf '  [%s] 已复制 %s\n' "$dir_name" "$f"
        else
            printf '  [%s] 跳过不存在的文件：%s\n' "$dir_name" "$f" >&2
        fi
    done

    for lnk in "${EXTRA_LINKS[@]}"; do
        ln -sf "../${lnk}" "${dir_name}/${lnk}"
        printf '  [%s] 已建立软链接 %s → ../%s\n' "$dir_name" "$lnk" "$lnk"
    done

    cat > "${dir_name}/generation_info.txt" <<EOF
source_inp=${INP_FILE}
modified_param=${PARAM}
modified_value=${val}
generated_dir=${dir_name}
EOF

    GENERATED_DIRS+=("$dir_name")
    printf '  → 完成：%s/\n\n' "$dir_name"
done

printf '========================================\n'
printf '  全部完成，共生成 %d 个测试文件夹\n' "${#GENERATED_DIRS[@]}"
printf '========================================\n'

[[ ${#GENERATED_DIRS[@]} -eq 0 ]] && {
    printf '  [错误] 没有成功生成任何测试目录\n' >&2
    exit 1
}

[[ -z "$JOB_SCRIPT" ]] && exit 0

printf '\n  生成的目录：\n'
for d in "${GENERATED_DIRS[@]}"; do
    printf '    - %s\n' "$d"
done
printf '\n'

SCHEDULER="$(detect_scheduler)"
case "$SCHEDULER" in
    pbs)   SUBMIT_CMD="qsub";   SCHED_NAME="PBS" ;;
    slurm) SUBMIT_CMD="sbatch"; SCHED_NAME="Slurm" ;;
    none)
        printf '  [警告] 未检测到 qsub 或 sbatch，无法提交任务\n' >&2
        exit 0
        ;;
esac

printf '  检测到调度系统：%s（%s）\n\n' "$SCHED_NAME" "$SUBMIT_CMD"

if [[ ! -t 0 ]]; then
    printf '  [非交互模式] 跳过提交，请手动进入各目录提交任务\n'
    exit 0
fi

printf '  是否提交全部 %d 个任务？[y/N] ' "${#GENERATED_DIRS[@]}"
read -r -t 30 answer || { printf '\n  [超时] 已跳过提交\n'; exit 0; }

case "$answer" in
    [yY]|[yY][eE][sS])
        printf '\n'
        submit_ok=0
        submit_fail=0
        for d in "${GENERATED_DIRS[@]}"; do
            job_path="${d}/${JOB_SCRIPT}"
            if [[ ! -f "$job_path" ]]; then
                printf '  [跳过] 找不到提交脚本：%s\n' "$job_path" >&2
                ((submit_fail++)) || true
                continue
            fi
            if job_id=$(cd "$d" && "$SUBMIT_CMD" "$JOB_SCRIPT" 2>&1); then
                printf '  [已提交] %s  →  %s\n' "$d" "$job_id"
                ((submit_ok++)) || true
            else
                printf '  [失败]   %s  →  %s\n' "$d" "$job_id" >&2
                ((submit_fail++)) || true
            fi
        done
        printf '\n  提交完毕：成功 %d 个，失败/跳过 %d 个\n' "$submit_ok" "$submit_fail"
        ;;
    *)
        printf '  已跳过提交\n'
        ;;
esac
