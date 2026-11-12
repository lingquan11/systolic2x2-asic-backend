# BACKEND_RESULT：systolic2x2 前后端全流程（后端部分）

写于 2026-11-12。任务根目录 `~/workspace/aices-backend-setup/work-systolic/`（下称 ROOT）。逐轮过程与全部失败尝试见 `ROOT/SESSION_LOG.md`，原始日志在 `ROOT/logs/`。本文件由执行本后端流程的 Agent 本人撰写。

## 0. 一句话结论
- 形式等价：**PASS，但口径是"eqy 分区级 17/21 + 寄存器边界切割的组合证明 + 按拍归纳"，不是单一的 eqy PASS**，带若干限定（见 §3）。
- 工艺映射：2243 个 sky130 单元，面积 19214.678 µm²。
- STA：10ns 试跑假设下，综合直出网表 setup **未收敛**（WNS -1.69ns）。
- 物理流程：openroad 直接脚本流到 GDS，详细布线违例收敛到 0；布线后 setup **仍未收敛**（主口径 WNS -0.25ns），hold 满足。
- DRC：magic 0 个违例。LVS：netgen "Circuits match uniquely"（器件 2295=2295，线网 2332=2332）。
- 本结果**不是 foundry 签核**，也不是 LibreLane 流程的结果。

## 1. 源设计与源文件
| 项 | 内容 |
|---|---|
| 设计 | design-04-systolic2x2（2×2 输出驻留脉动阵列，8 位有符号输入、32 位有符号输出；前端已验收 PASS） |
| 源目录（只读使用） | `~/workspace/aices-pilot-2026-11-11/design-04-systolic2x2/` |
| 交付 RTL | `systolic2x2.v`，SHA256 `bcafa42f0f7ba2d4e1aa5bf2871b10682bf4ce7bb8048ba409d8837ab1728bec` |
| 交付综合网表 | `systolic2x2_netlist.v`，SHA256 `e086a610c045d6000b1efad48e8f2715a0688b1872cc530e7cac591f9cf04681`（Yosys 0.33 写出的行为式网表，0 个门单元、0 个 sky130 单元） |
| 核对情况 | 该设计 `work/` 与 `pkg/02_最终交付物/` 两处同名文件哈希一致。**该设计的 RESULT.md / SESSION_LOG.md / selfcheck.txt 中没有记录这两个文件的 SHA**，因此只能核对两处副本一致，无法与"记录值"比对。 |
| 本任务副本 | `ROOT/work/systolic2x2.v`、`ROOT/work/systolic2x2_netlist.v`（只读复制，未改动） |

## 2. 流程与工具版本
| 工具 | 版本 / 来源 |
|---|---|
| yosys / eqy / sby / yosys-abc | oss-cad-suite：Yosys 0.70+368（git 7cf88aca6）、eqy v0.70-2、sby v0.70-9 |
| OpenSTA | 2.3.1（conda-env-or 的 `sta`） |
| OpenROAD | 2.0_3175_gf12e2f474（2022-03 构建，旧版；缺 `write_gds`、`global_connect`，`report_* > 文件` 重定向不可用） |
| magic | 8.3.678（conda-env） |
| netgen | 1.5.272（litex-hub，conda-env-ng，带 Tcl 绑定） |
| klayout | 0.30.13（venv-py 的 Python 模块） |
| PDK | sky130A，版本 `8afc8346a57fe1ab7934ba5a6056ea8b43078e71`，`PDK_ROOT=~/workspace/aices-backend-setup/tools/pdk-root` |
| 标准单元库 | sky130_fd_sc_hd，`tt_025C_1v80.lib`（单角） |
| 流程 | 非 LibreLane（LibreLane 3.0.17 与旧版 openroad 不兼容，见 mac4 的 SETUP_RESULT）；物理流程为 openroad 直接脚本流，GDS 由 magic 读 DEF 写出 |

## 3. 形式等价：PASS（按组合论证口径）
### 3.1 eqy 分区级
- 配置（`ROOT/work/systolic2x2_abc_v2.eqy`）：`read_verilog -icells -sv`；gold、gate 两侧 `prep -top systolic2x2` 之后各加 `flatten` 与 `opt_clean -purge`；`use sby`、`depth 5`、`engine abc pdr`。
- v1（未 flatten，`systolic2x2_abc.eqy`）：258 个分区中 28 个报 "not equivalent"，用时 114s。逐个核对：**28/28 的反例都含"同一物理线被拆成多个互不相关输入、且取值互相矛盾"**（24 个含 rst_n/clk 矛盾，4 个为 first/en 别名矛盾），是 eqy 分区方式造成的假失败。
- v2（flatten 合并别名线后）：共 21 个分区，**17 个 PASS**（每个 0–2s），**c00/c01/c10/c11 四个累加分区 abc pdr 无结论**（c00 跑约 26 分钟、CPU 满载、内存仅约 38MB，无输出，按 1500s 规则终止）。无任何 FAIL。
- 所以 **eqy 工具本身从未对整个设计报过 PASS**。

### 3.2 四个累加分区：寄存器边界切割的组合证明
- 方法：gold、gate 各自 flatten 后 `expose -cut -dff`，每个寄存器 Q 换成自由输入，同名输出即带异步复位的下一状态函数；`async2sync` 建模复位；yosys 生成 gold/gate 同名输出异或的比较电路，abc `iprove` 对每个输出逐个证恒为 0。
- 切割后两侧端口名与位宽完全一致（43 个端口，diff 为空）：gold 16 个寄存器字 = gate 182 个单比特寄存器，按名一一对应。
- 结果（原始日志 `ROOT/logs/comb_*.log`，均 UNSATISFIABLE）：`pe00.acc` 179s、`pe01.acc` 29s、`pe10.acc` 165s、`pe11.acc` 150s；`c00..c11`、`out_valid`、`phase`、`f1/f2/l1/l2`、`a1_d/b1_d`、`pe00.a_out/b_out`、`pe01.b_out`、`pe10.a_out` 均 PROVED（<1s）。
- **负对照**：在临时副本里把 gate 的 `phase` 复位极性故意翻转，同一流程判 SATISFIABLE（有反例）；说明 PROVED 不是流程恒返回 UNSAT。
- 过程中作废的一次结果：曾用 abc `cec` 按**位置**比对而 gold/gate 端口顺序不同，得到假的 NOT EQUIVALENT，已作废（`scripts/cec_signal.INVALID.sh`），改为按端口名配对。

### 3.3 组合论证（三环合起来按拍归纳 ⇒ 时序等价）
1. 两侧寄存器按名一一对应（端口 diff 为空），状态编码相同；
2. 每个寄存器的下一状态函数 `rst_n ? D(现态,输入) : 复位值` 在 Q 取任意值时 gold 与 gate 组合等价，其中复位分支的复位值等价，故复位后初始状态相同；
3. 全部主输出（c00–c11、out_valid）作为现态与输入的组合函数等价。

覆盖清单（无缺口）：phase、f1、f2、l1、l2、out_valid（6×1）；a1_d、b1_d（2×8）；pe00.a_out、pe00.b_out、pe01.b_out、pe10.a_out（4×8）；pe00/01/10/11.acc（4×32）；输出 c00–c11 为 acc 直连。合计 16 个寄存器字 / 182 位。

### 3.4 全部限定（须随 PASS 一起读）
- **状态同名对应**：等价是"状态一一对应"意义下的，依赖寄存器名匹配；gate 由同版本 Yosys 综合得来，不是跨重编码的通用等价。
- **async2sync 建模**：异步复位按复位当拍即生效建模。
- **切割含不可达状态**：切割模型中 Q 取任意值（含不可达状态），比可达状态要求更强，证过则更保险。
- **四条无扇出线两侧同缺**：`pe01.a_out`、`pe10.b_out`、`pe11.a_out`、`pe11.b_out` 在两侧切割模型里都不存在（推断为无扇出被 `opt_clean` 删除，未单独验证；RTL 中这几条线确实未被使用）。
- eqy 的 4 个 c 分区无结论，由组合切割证明替代；最终口径为 "eqy 分区级 17/21（flatten 后）+ 4 个累加分区由组合切割证明补全"。
- 映射网表（§4）是对交付网表**重新综合**得到的，**映射网表与交付网表之间未做形式等价**；eqy 与组合证明证的是交付 RTL ≡ 交付网表。
- v2 第 1 次运行的日志被第 2 次 `-f` 重跑覆盖，未留档（已在 SESSION_LOG 说明）。

## 4. 工艺映射
- 输入形态核对：交付网表是行为式（`assign`/`always`），故先 `synth -flatten` 再映射（照 mac4）。脚本 `ROOT/work/map_systolic2x2.ys`：`read_liberty -lib` → `synth -top systolic2x2 -flatten` → `dfflibmap` → `abc`（`-dont_use` lpflow/probe/clkbuf/clkdly）→ `hilomap` → `check -assert`。日志 `ROOT/logs/map_systolic2x2.log`，统计 `ROOT/work/map_stat.txt`，用时 7s。
- 结果：**2243 个单元，面积 19214.678 µm²**；182 个 `dfrtp_1`；lpflow 单元 0 个。主要单元：xnor2_1 355、nand2_1 340、xor2_1 194、maj3_1 185、nor2_1 148。
- 映射网表：`ROOT/work/systolic2x2_sky130_netlist.v`，SHA256 `81dfd6cefcb996691780360416a2029801db044439f9a57406862afb3b2f6993`。

## 5. STA（综合直出映射网表，OpenSTA 2.3.1）
- **SDC 是试跑假设，不是设计规格**（沿用 mac4）：10ns 时钟、理想时钟，输入延迟 1ns（rst_n/in_valid/a0/a1/b0/b1），输出延迟 1ns，无负载、无线负载模型。`ROOT/work/systolic2x2.sdc`。
- 结果（tt_025C_1v80 单角）：**WNS -1.69ns，TNS -12.31ns**（setup 违例）；hold worst +0.411ns；recovery +9.226ns（均 MET）。
- **关键路径**：起点 `_4288_`（`b1_d[0]` 寄存器）→ nand4/and2 → **23 级 maj3_1 进位链（每级约 0.40ns）** → 约 9 级逻辑 → 终点 `_4163_/D`（`c01[31]` 寄存器）；到达 11.484ns，要求 9.796ns，slack -1.688ns。
- 违例端点 18 个，全是累加寄存器高位（c01 8 个、c10 9 个、c11 1 个，c00 无）。另有 max slew 违例 189 处（最差 2.35ns 对限值 1.50ns）、max cap 违例 5 处——来自未做缓冲/扇出修复的综合直出网表，物理流程的 `repair_design` 才处理。
- 报告 `ROOT/work/sta_systolic2x2.rpt`，端点清单 `ROOT/work/sta_endpoints.rpt`。
- **fmax 口径**：综合直出（布局前、理想时钟）周期 10+1.69=11.69ns ≈ 85.5MHz，**这是布局前口径**；布线后口径见 §6.3（10.25ns ≈ 97.6MHz）。

## 6. 物理流程（openroad 2022-03 版，直接脚本流）
- 脚本 `ROOT/work/or-flow/flow.tcl`（参照 mac4 的 flow.tcl，仅改路径、设计名、利用率）：floorplan → tapcell → pdn → 全局布局 → repair_design → 详细布局 → CTS → repair_timing（`-setup -hold`）→ 全局布线 → 详细布线 → filler。SDC 10ns 假设不变。主日志 `ROOT/logs/or_flow_systolic2x2.log`，用时 870s，rc=1（见 §9）。
### 6.1 版图
- die **216.64 × 216.64 µm**，75 行 × 449 site，tapcell 539 个；floorplan 目标利用率 45%；最终 `report_design_area` 报 21111 µm²、利用率 50%（含 CTS/修复后新增单元，是否含 filler 未核实）。
- 最终 DEF（`systolic2x2_final.def`）共 6535 个实例：逻辑单元 2295（触发器 182）、tapcell 539、filler 3701。
- repair_design 重定尺寸 225 个实例；CTS：182 个 sink、17 个时钟缓冲、时钟路径最少 2 级；CTS 后 repair_timing 插 35 个缓冲、重定尺寸 47 个，报 "No hold violations found"。
### 6.2 详细布线违例收敛
- 违例数 **984 → 288 → 209 → 7 → 0**，之后各轮均为 0。这是 openroad 布线器内置检查，**不是 sky130 规则的 DRC**（后者见 §7）。
### 6.3 布线后时序（tt_025C_1v80，传播时钟；**非签核，寄生为估算**）
同一份 `final.def` 在三种寄生设置下给出三个 setup 数，全部列出：
| 口径 | setup | hold | 备注 |
|---|---|---|---|
| **主口径**：`estimate_parasitics -placement` + `set_wire_rc -layer met2`（`post_wirerc.tcl`） | **WNS -0.25ns，TNS -0.45ns** | +0.31ns | 关键路径 `_4288_`(b1_d[0]) → `_4163_`(c01[31])；met2 的 RC 取值是粗略值，非 PDK 标定值 |
| flow 末尾 `estimate_parasitics -global_routing` | WNS -0.50ns，TNS -1.29ns | +0.30ns | |
| `estimate_parasitics -placement`，未设 `set_wire_rc`（`post.tcl`） | +0.001ns | +0.357ns | 日志警告 RSZ-0014：线电容为零（未计线电容），偏乐观、不可信 |
- 结论：**布线后 setup 未收敛**（-0.25～-0.50ns，视寄生估算），主口径 -0.25ns；recovery 与 removal 均满足。
- **fmax 口径（布线后）**：周期 10+0.25=10.25ns ≈ 97.6MHz。
- 对照说明：mac4 试跑报的 setup +3.531ns 用的是上表第三行同类口径（`-placement`、未设 `wire_rc`、即未计线电容），属乐观口径，不能与本设计的负值直接比较。
- 产物：`ROOT/work/or-flow/post.tcl`、`post_wirerc.tcl`、`systolic2x2_post_stdout.rpt`、`systolic2x2_post_wirerc_stdout.rpt`。

### 6.4 GDS
- magic 读"PDK 标准单元 GDS + LEF"后 `def read systolic2x2_final.def`、`gds write`（脚本 `ROOT/work/or-flow/def2gds.tcl`，日志 `ROOT/logs/magic_def2gds_systolic2x2.log`，93s；必须设 `PDK_ROOT`）。
- **`ROOT/work/or-flow/systolic2x2.gds`，7369946 字节，SHA256 `dc361503af2d7ab8cc0e02edbe1dc543f19403ed3b2d58ac52ad1877240c8dbe`**。
- klayout 读回：顶层 `systolic2x2`（唯一），bbox (0,0)–(216.64,216.65) µm，顶层直接实例 6535（与 DEF COMPONENTS 一致），cell 共 111，图层 38。读回只证明可读、顶层名与实例数与 DEF 一致，不证明版图正确。

## 7. DRC（magic 8.3.678，sky130A，`drc(full)`）
- **违例总数 0**，`drc listall why` 与顶层 `drc list why` 均输出 "No errors found."。报告 `ROOT/work/drc_systolic2x2.rpt`，脚本 `ROOT/work/drc_systolic2x2.tcl`，日志 `ROOT/logs/magic_drc_systolic2x2.log`（88s）。
- 对照：同一脚本与同一 magic/PDK 对 mac4 版图报出过 2 处 li.3 违例，说明该检查流程能报违例，0 不是流程失效。版图未做任何修改。
- 限定：magic 的 `drc(full)` 是 sky130A 规则的开源实现，不是 foundry 签核；未做 antenna、density 等专项检查。

## 8. LVS（magic 提取 + netgen 1.5.272）
- **结论：Circuits match uniquely。** 器件数 2295 = 2295，线网数 2332 = 2332，pin 列表等价，无 "no matching pin"。报告 `ROOT/work/lvs_systolic2x2.rpt`，比对输出 `ROOT/work/lvs/lvs_comp.out`，日志 `ROOT/logs/netgen_lvs_systolic2x2.log`。
- 配置（沿用 mac4 定位轮 v7 / 配置 G 的做法）：
  1. 版图侧：magic 读"清除 8 个 fill 单元共 102 个 li1+mcon 形状的标准单元库副本"（`work/lvs/lib_fill_no_li1.gds`，`scripts/mklib.py` 生成；PDK 原文件与设计版图均未改）+ LEF + 本设计 `final.def`，提取 → `systolic2x2_layout.spice`；
  2. 源侧：openroad 读 `final.def` 后 `write_verilog -include_pwr_gnd`，`scripts/strip_fill.py` 去掉 fill/tap 实例 4240 个（3701 + 539，与 DEF 统计一致）；
  3. netgen + `sky130A_setup.tcl`（官方默认 permute/property，未额外放宽）。
- 限定：①比对对象是 DEF 导出网表（布局后经 openroad 优化/CTS 的版本），不是 `systolic2x2_sky130_netlist.v`；②提取用的库副本清除了 fill 单元的 li1/mcon，结论适用于"fill/tap 不参与连接"的设计意图，**实际 GDS 中 fill 的 li1 是否造成伪连通，本次 LVS 不覆盖**；③开源 LVS，非 foundry 签核。
- 与 mac4 的关系：mac4 同方法（配置 G）因 `sum[17..30]` 符号扩展 assign 复制出的端口 pin 配不上而判 "failed pin matching"，**从未给出过 match**；本设计没有此类端口，一次配上。该配置在 mac4 上没有交叉验证出 match，这一点如实说明。

## 9. 失败与受限项
- **DFT 未执行**（扫描链、ATPG 均无）。
- 开源 DRC/LVS 是签核等价物，**不是 foundry 签核**。
- 时序只有 tt_025C_1v80 单角；寄生为估算（布线后未做 RC 抽取）；IO 约束为试跑假设；**setup 未收敛**（综合直出 -1.69ns；布线后主口径 -0.25ns），未放宽 SDC、未加大 repair_timing 力度重跑（按 Lead 决定）。
- **映射网表与交付网表之间未做形式等价**；LVS 比对的是 DEF 导出网表。
- eqy 工具本身未对整个设计报 PASS，PASS 靠组合切割证明补全（§3 全部限定）。
- LibreLane 未使用（版本不兼容）；物理流程为旧版 openroad 手写脚本流，参数取自 mac4 流程。
- 过程性问题（均已在 SESSION_LOG 如实记录）：第一次 `sed` 生成 `flow.tcl` 得 0 字节文件致 openroad 空跑并报 rc=0（假成功，已清除）；`flow.tcl` 最后 `report_design_area > 文件` 报 `wrong # args` 致 rc=1，此前所有步骤已完成，时序报告改由 `post.tcl` 补出；v2 第 1 次 eqy 日志被覆盖；两次用 `pkill -f` 连带终止了自己所在的 shell；一次按位置比对的 abc `cec` 得到假的 NOT EQUIVALENT（已作废）。

## 10. 全部产物路径清单（均在 ROOT 下）
- 输入副本：`work/systolic2x2.v`、`work/systolic2x2_netlist.v`
- eqy：`work/systolic2x2_abc.eqy`（v1）、`work/systolic2x2_abc_v2.eqy`（v2）、`work/eqy_out/`（v1 工程）、`work/eqy_out_v2/`（v2 工程）、`logs/eqy_systolic2x2.log`、`logs/eqy_systolic2x2_v2.log`、`logs/eqy_systolic2x2_v2_resume.log`、`logs/small_*.log`、`logs/failed_partitions.txt`
- 组合切割证明：`cut/`（切割模型 `gold_cut2.v`、`gate_cut2.v`，`wrap.v`、`wrap.aig`，负对照 `neg/`）、`scripts/`（`gen_wrap.py`、`prove_outs.sh`、`run_small.sh`、`watch_log.sh`、`mklib.py`、`strip_fill.py`、已弃用的 `cutdff.py` 与作废的 `cec_signal.INVALID.sh`）、`logs/comb_*.log`
- 映射与 STA：`work/map_systolic2x2.ys`、`work/map_stat.txt`、`work/systolic2x2_sky130_netlist.v`、`work/systolic2x2.sdc`、`work/sta_systolic2x2.tcl`、`work/sta_systolic2x2.rpt`、`work/sta_endpoints.rpt`、`logs/map_systolic2x2.log`
- 物理流程：`work/or-flow/`（`flow.tcl`、`systolic2x2_place.def`、`systolic2x2_cts.def`、`systolic2x2_final.def`、`systolic2x2_final.v`、`systolic2x2.gds`、`def2gds.tcl`、`post.tcl`、`post_wirerc.tcl`、`*_post*_stdout.rpt`、`*.guide`）、`logs/or_flow_systolic2x2.log`、`logs/magic_def2gds_systolic2x2.log`
- DRC：`work/drc_systolic2x2.tcl`、`work/drc_systolic2x2.rpt`、`logs/magic_drc_systolic2x2.log`
- LVS：`work/lvs/`（`ex.tcl`、`lvs.tcl`、`systolic2x2_layout.spice`、`systolic2x2_final_pwr.v`、`systolic2x2_final_pwr_nofill.v`、`lib_fill_no_li1.gds`、`lvs_comp.out`）、`work/lvs_systolic2x2.rpt`、`logs/magic_extract_systolic2x2.log`、`logs/netgen_lvs_systolic2x2.log`
- 会话记录：`SESSION_LOG.md`；任务卡 `TASK_CARD.md`

## 11. 复用命令示例
```
T=~/workspace/aices-backend-setup/tools
export PATH=$T/oss-cad-suite/bin:$T/conda-env-or/bin:$T/conda-env/bin:$PATH
export PDK_ROOT=$T/pdk-root PDK=sky130A TMPDIR=$T/tmp

# eqy（flatten 合并别名线；乘法器/累加器分区可能不收敛，需配合组合切割证明）
eqy -f -d eqy_out_v2 work/systolic2x2_abc_v2.eqy
# 组合切割证明：cut/*.ys 生成 gold_cut2.v/gate_cut2.v；scripts/gen_wrap.py 生成 wrap.v；scripts/prove_outs.sh 逐输出 abc iprove

# 工艺映射（行为式网表先 synth 再映射）
yosys -l logs/map.log work/map_systolic2x2.ys
# STA
$T/conda-env-or/bin/sta -no_splash -exit work/sta_systolic2x2.tcl
# 物理流程
$T/conda-env-or/bin/openroad -no_init -no_splash -exit work/or-flow/flow.tcl
# DEF → GDS（必须设 PDK_ROOT）
magic -dnull -noconsole -rcfile $PDK_ROOT/sky130A/libs.tech/magic/sky130A.magicrc work/or-flow/def2gds.tcl
# DRC
magic -dnull -noconsole -rcfile $PDK_ROOT/sky130A/libs.tech/magic/sky130A.magicrc work/drc_systolic2x2.tcl
# LVS（先 magic 提取 work/lvs/ex.tcl，再用 conda-env-ng 的 netgen）
PATH=$T/conda-env-ng/bin:$PATH netgen -batch source work/lvs/lvs.tcl
```
