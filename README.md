# cp2k_scripts

CP2K 计算辅助脚本（Gadi PBS 和 Setonix Slurm 都能用）。
提交作业的脚本会自动识别调度器：有 `qsub` 就走 PBS，有 `sbatch` 就走 Slurm。
脚本之间互相调用时，按以下顺序查找被调用的脚本：先找本脚本所在目录，再找 `PATH`，最后才用旧的 `/home/561/hm1876/...` 路径。
有菜单的脚本都可以直接把选项写在命令行上（不写才显示菜单），`-h` 显示用法。

## 公共库（必须和脚本放在同一目录，或在 `PATH` 中）

| 文件 | 内容 |
|---|---|
| `cp2k_common.sh` | bash 公共函数（被其它脚本 `source`）：调度器识别/提交（`submit_cmd`、`submit_in_dir`）、`find_script`、`confirm`、`die/warn/info`、`cp2k_finished/cp2k_energy/cp2k_walltime`、`latest_out` |
| `cp2k_inp.py` | CP2K 输入文件解析（大小写、`#`/`!` 注释、`&END`、嵌套、`@SET` 变量）。命令行：`get-cell 文件`（inp/restart/`*-1.cell`/POSCAR；`--step N`、`--format vectors\|lengths\|cellpar\|cp2k`）、`set-key 文件 段落/路径 参数 值`、`has-section`、`replace-section` |
| `cp2k_xyz.py` | 流式读取 xyz 轨迹（逐帧，不占内存）、CP2K 注释行解析、考虑周期性的键长（向量化，ASE） |

> 作业追踪工具 `jobtrack/` 只保留在 `vasp-scripts/jobtrack/`。

## 作业与输入

| 脚本 | 用途 |
|---|---|
| `cp2k_runscript` | Gadi PBS 作业模板（会读取 `~/CP2K_JOB_PARAMETERS`，文件存在时才读） |
| `cp2k_runscript_setonix` | Setonix Slurm 作业模板（pawsey0328，work 分区，每节点 128 核，srun）。⚠️ 先用 `module avail cp2k` 查到模块名，替换 `module load "cp2k/<VERSION>"`；找不到 `cp2k.psmp` 时作业会立即报错退出。HFX 的 STORAGE_LOCATION 放在 `$MYSCRATCH`（Setonix 没有 jobfs） |
| `cp2k_submission_script_generator.sh` | 由作业模板生成作业脚本，然后编辑或提交。模板：PBS 用 `~/cp2k_runscript`，Slurm 用 `~/cp2k_runscript_setonix`（家目录没有时用本仓库里的同名文件；也可作为第二个参数指定） |
| `cp2k-restart.sh` | `cp2k-restart.sh restart input`：把 restart 里的 CELL/COORD（以及 MD/BAND 等）写回 inp。找不到段或段重复时报错且不改文件；修改前留 `input.bak` |
| `diag2ot_geo2cell2md.sh` | `diag2ot_geo2cell2md.sh input [ot\|diag\|geo\|cell\|md]`：把输入切换成 OT/DIAG/GEO_OPT/CELL_OPT/MD（需要 Multiwfn；修改前留 `input.bak`） |
| `cp2k_clean.sh` | 递归删除 `*.wfn` / `*.cub*`（⚠️ 也会删 restart 用的 wfn）。先列出文件和总大小再确认；`-n` 只预览，`-y` 不询问 |

## 收敛测试

| 脚本 | 用途 |
|---|---|
| `cp2k_para_conv.sh` | **通用参数扫描**：`-p 参数 -v "取值"`，负责生成目录和提交（`-h` 查看帮助）。`-p 段落/参数`（如 `MGRID/CUTOFF`、`OUTER_SCF/EPS_SCF`）只改该段落里的参数，段落里没有时加在 `&END` 之前。输入里没有该关键字时报错（`-a` 允许追加）；不加 `-f` 时不复制 wfn/轨迹等大文件，>50 MB 的文件用软链接 |
| `cp2k_cutoff_conv.sh` / `cp2k_relcutoff_conv.sh` | CUTOFF / REL_CUTOFF 测试：`[prepare\|submit\|analyse]`，生成、提交、汇总成表（CUTOFF.txt / REL_CUTOFF.txt）。`-v "取值"`、`-f 另一个 cutoff`、`-j 作业脚本`（默认 conv_test）、`-i`/`-O` 输入/输出文件名。`cp2k_relcutoff_conv.sh` = `cp2k_cutoff_conv.sh --rel` |
| `kpoints_analyse.sh` | 汇总 `kpoints_*` 目录 → kpoints_data.ssv；`-p 前缀 -v "取值" -O 输出文件 -o 表格` 可用于任何 `<前缀>_<值>` 目录 |
| `eps_schwarz_analyse.sh` | 汇总 `eps_schwarz_*` 目录 → cutoff_data.ssv（= `kpoints_analyse.sh --preset eps_schwarz`） |
| `cp2k_conv_analyse.py` | **通用收敛分析**：自动找 `cp2k_para_conv.sh` 生成的目录（`generation_info.txt`），或 `-p 'cutoff_*Ry'` / `-p kpoints_` 等；按数值排序，每个目录给出状态（完成/运行中/失败、SCF 不收敛次数）、能量、原子数、每原子能量、相对上一点和参考点（默认最后一点，`--ref first`）的 ΔE（meV/atom）、SCF 步数、耗时，有输出时加压强/带隙/费米能级（`--grids` 加格点数）；标出 "converged at"（`-t` 阈值，默认 1 meV/atom）；表格打印到屏幕并写入 TSV（`-o`），`--plot 图.png` |
| `cp2k_U_conv.sh` | Hubbard U 扫描：`[prepare\|submit\|analyse]`，生成、提交、晶格常数（晶胞矢量长度）随 U 的变化。`-v "U 值"`、`-j 作业脚本`（默认 NBT） |
| `cp2k_node_test.sh` + `cp2k_node_test_time.py` | 节点数扩展性测试：生成并提交，再汇总耗时 |

## 结构优化 / NEB / 频率 / MD 分析

| 脚本 | 用途 |
|---|---|
| `cp2k-output-analyse.py` | GEO_OPT / CELL_OPT 输出 → `<out>__data.csv`（含每步 SCF 步数、总耗时；CELL_OPT 在每行末尾另加内压、压强偏差、压强是否收敛、体积、a/b/c；逐行流式读取）；`--plot` / `--no-plot`（都不写时在终端里询问，非终端不作图） |
| `cp2k-neb-analyse.py` | BAND 输出 → csv；另外读取每步的 `ENERGIES [au] =` / `DISTANCES REP =`：`<out>__band_energies.csv`（每步各 replica 相对 replica 1 的能量，eV）、`<out>__profile.csv`（最后一步的能量曲线），打印正/逆反应能垒和最高 image；`--plot` 还会保存 `<out>__profile.png`（这部分格式按 CP2K 源码写的，请先用真实输出核对） |
| `xyz2neb.pl` | 初态、末态 xyz 线性插值 → `0.xyz … N.xyz`；加 `-c 文件`（inp/restart/`*-1.cell`/POSCAR）或 `a b c` 时按最小镜像插值（跨周期边界的原子不会穿过晶胞中间） |
| `cp2k_nebavoid.sh` | `[xyz2poscar\|poscar2xyz]`：NEB 各 image 用 VASPKIT 处理后再合并成 `traj.xyz`（晶胞取自 cp2k.inp） |
| `NEB.sh` / `initNEB.sh` | 收集各 replica 的最后一帧 / 第一帧 → 轨迹 + 能量（`initNEB.sh` = `NEB.sh --first`） |
| `cp2kfreq.pl` / `cp2kfreq2mov.pl` | 频率列表 / 每个振动模式的 xyz 动画 |
| `cp2k_md_analysis.py` | `.ener` 作图（`cp2k_md_analysis.py [file] [-c 列] [-o 图.png]`，默认 `cp2k-1.ener`；不写 `-c` 时菜单选择） |
| `xyz_extractor.py` | 从大轨迹中抽帧：`-f` 指定帧 / `-s` 步长 / `-r` 随机 |

## 结构转换

| 脚本 | 用途 |
|---|---|
| `cp2k2cif.sh` | `cp2k2cif.sh 文件 [poscar\|cif\|pdb\|xyz]`：用 Multiwfn 转换（不写格式时菜单选择） |
| `xyz2cif.sh` | `xyz2cif.sh proj-pos-1.xyz [帧]`：从轨迹取某一帧 → cif；晶胞取 `proj-1.cell` 中同一步的（存在时），否则取 `proj.inp` 的 |
| `xyz2extxyz.py` | 递归把 `*-pos-*.xyz` 转成 extxyz（`--all` 转换所有 xyz）；晶胞：`--cell` 指定 / 同名 `*-1.cell` 逐帧 / 自动找 inp、restart；逐帧流式处理 |
| `cp2k2gro.py` | cp2k 轨迹 → GROMACS `.gro`（可附带 `.top`/`.mdp`） |
| `bond_length.py` / `bond_length_traj.py` | 键长统计（单个 POSCAR / 多帧轨迹）；`bond_length_traj.py --cell` 可以是 POSCAR、cp2k.inp、restart 或 `*-1.cell`（逐帧晶胞，NPT/CELL_OPT） |

## 电子结构

| 脚本 | 用途 |
|---|---|
| `pdos_sigma.py` | `.pdos` 高斯展宽（第三方，GPL） |
| `cp2k_csv2bandstructure.sh` | `cp2k_bs2csv` 输出拼接成一个 csv |
| `cp2k_import_nval.py` | 从赝势文件生成"元素 → 价电子数"的 JSON（数据目录取 `$CP2K_DATA_DIR`） |

## 超精细 / g 张量 / ZFS / 应变

| 脚本 | 用途 |
|---|---|
| `extract-hyperfine.sh` | 提取指定原子的超精细常数 → iso_A.csv / a-iso_A.csv（单目录或多目录；每个输出文件只完整读一遍） |
| `hyperfine_average.py` | 对上面的结果按组求平均（两种输出格式都支持） |
| `superhyperfine_cp2k.sh` | 按近邻壳层统计 Si 的超精细（Si 专用） |
| `eig.py` | `cp2k-GTENSOR-1.data` → g 张量本征值 |
| `zfs_run.sh` / `zfs_analyze.sh` | 零场分裂：生成并提交 / 汇总（`-n "1 2 3 ..."` 改 HOMO-LUMO 列表，`zfs_run.sh -j` 改作业脚本，默认 o2） |
| `cp2k_strain.sh` | 生成静水压、单轴、剪切应变并提交（需要 Multiwfn；剪切需要 vasp-scripts 里的 `deform_strain.sh` 在 PATH 中） |
| `cp2k_strain_restart-ae.sh` | 应变目录续算 |
| `cp2k_strain_analysis.sh` / `cp2k_strain_g-factor_analysis.sh` | EFG（默认第 1 个原子 B，`-a 原子序号 -e 元素`）/ g 因子随应变的变化 → output.csv（两个脚本默认写同一个文件名，用 `-o` 改）；`cp2k_strain_g-factor_analysis.sh` = `cp2k_strain_analysis.sh --gtensor` |

## 外部依赖

Multiwfn、VASPKIT（`atomkit`）、`cp2k_bs2csv`、python3（numpy/pandas/matplotlib/ASE）、perl。
