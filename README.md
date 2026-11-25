# systolic2x2：2×2脉动阵列的开源ASIC后端全流程

## 这是什么

2×2输出驻留脉动阵列（8位有符号输入、32位有符号输出）的数字IC设计。前端（SPEC、RTL、功能验证、逻辑综合）完成并验收后，用开源EDA工具链与SKY130开源PDK把后端完整跑了一遍：形式等价→工艺映射→STA→布局布线→GDS→DRC/LVS。

## 后端怎么实现

工具链：Yosys/eqy（OSS CAD Suite）、OpenSTA、OpenROAD、Magic、Netgen、KLayout；PDK为sky130A（sky130_fd_sc_hd库，tt_025C_1v80单角）。

1. 形式等价：eqy分区证明。第一版因分区把同一物理线拆成多个互不相关的输入，28个分区报假反例；flatten合并别名线后，21个分区中17个PASS，剩下4个累加分区PDR引擎长时间无结论，改用寄存器边界切割的组合证明补全（逐个寄存器证明其下一状态函数，并做负对照验证证明流程本身有效），再按拍归纳得到时序等价。
2. 工艺映射：交付网表是行为式的，先重新综合，再映射到sky130标准单元：2243个单元，面积19215µm²，182个触发器。
3. STA：OpenSTA分析，SDC为10ns试跑假设（不是设计规格），tt单角。
4. 物理流程：LibreLane与本机旧版OpenROAD不兼容，改用OpenROAD直接脚本流：floorplan（216.64×216.64µm）→tapcell→电源网络→布局→repair_design→CTS→repair_timing→布线，详细布线违例从984收敛到0；DEF经Magic写出GDS（7.37MB），KLayout读回的实例数与DEF一致。
5. DRC/LVS：Magic按sky130A规则做全量DRC；LVS用Magic提取版图、Netgen比对DEF导出的布局后网表。

## 实现到哪一步

- 形式等价：PASS（组合论证口径，限定见下节）
- 工艺映射：完成，2243个单元/19215µm²
- STA：完成，但setup未收敛。综合直出WNS为−1.69ns；布线后主口径−0.25ns（其余寄生口径−0.50ns与+0.001ns，其中+0.001ns未计线电容、不可信），hold满足；布线后等效fmax约97.6MHz。关键路径是乘法器直串32位累加器的23级进位链，违例端点全在累加器高位。
- 物理流程：完成，布线违例0，GDS已产出
- DRC：0违例
- LVS：Circuits match uniquely（器件2295=2295，线网2332=2332）
- DFT：未执行

## 缺陷与限定

1. 时序未收敛：10ns目标下布线后还差0.25ns，未放宽约束，也未加大时序修复力度重跑。根源是累加器进位链过长，结构性的修法是给乘加之间加流水级，未做。
2. 不是foundry签核：DRC/LVS为开源规则实现，未做antenna、density等专项检查；STA只有tt单角，寄生是估算值（未做布线后RC抽取），SDC是试跑假设而非真实规格。
3. 等价结论带组合论证前提：eqy本身从未对全设计报过PASS，结论靠分区证明加寄存器切割证明拼接；映射网表与交付网表之间未做形式等价，LVS比对的是DEF导出网表而非映射网表。
4. LVS提取时清除了fill单元库副本中的li1/mcon形状，实际GDS里fill的li1是否造成伪连通，不在本次覆盖内。
5. 流程工程化程度低：OpenROAD为2022年旧版、手写脚本流，LibreLane标准流程未跑通；过程中出现过空跑假成功、日志被覆盖等操作事故，均已在过程记录中如实标注。
6. 规模小：仅2×2教学级设计，更大规模、更高利用率下未验证。

## 目录

| 路径 | 内容 |
|---|---|
| `rtl/` | RTL（`systolic2x2.v`）、自检测试台、金标准模型 `golden.py`、测试向量 |
| `synth/` | Yosys 综合脚本、统计与通用网表 |
| `backend/` | 物理流程脚本 `flow.tcl`、SDC、sky130 映射网表、STA/DRC/LVS 报告、最终 DEF |
| `docs/` | `SPEC.md` 规格、`RESULT.md` 前端结果、`BACKEND_RESULT.md` 后端结果与工具版本 |

## 怎么复现（读懂再跑）

- 工具与版本见 `docs/BACKEND_RESULT.md` 第 2 节：Yosys 0.70、OpenSTA 2.3.1、OpenROAD 2.0_3175（2022 年旧版）、Magic 8.3.678、Netgen 1.5.272、KLayout 0.30.13，PDK 为 sky130A。
- 前端仿真（`rtl/` 目录下，测试台从当前目录读 `vectors.hex`）：`iverilog -g2005 -o sim tb_systolic2x2.v systolic2x2.v && vvp sim`。命令按文件结构给出，**未在本仓库中重新实测**；`docs/RESULT.md` 记录的是 iverilog 12.0 的结果。
- 综合（在 `rtl/` 目录下，脚本按相对路径读 `systolic2x2.v` 并写 `logs/`）：`mkdir -p logs && yosys ../synth/synth.ys`。同样未在本仓库重新实测。
- 后端：`backend/flow.tcl` 里的路径（`/home/hatch/workspace/...`）是作者机器上的绝对路径，直接运行会失败，需要先改成自己的 PDK 与工作目录。**这条流程没有一键复现**，仓库保存的是证据与脚本，不是可移植的流程。

## 仓库内容说明

本仓库含RTL与测试台、金标准模型、综合网表、sky130映射网表、STA/DRC/LVS报告与最终DEF。GDS为二进制文件（7.37MB），未存入本仓库，保存在完整交付包systolic2x2_full.zip中；后端逐轮过程记录见docs/BACKEND_RESULT.md所列的原始日志（不在本仓库）。

## 关于我自己的沉淀

这条后端流程是在AI编排下由Coding Agent执行的，我负责定目标、定验收标准和看结论。中间大量环节是我让AI跳过去的：eqy分区为什么会报假反例、切割证明怎么建模、OpenROAD脚本每一步在做什么、DRC/LVS的配置怎么定位，我并没有亲手趟过。这份仓库先作为「流程跑通」的证据存档；下一步我要抽完整的一天，亲手把这条流程从RTL到GDS重跑一遍，把跳过的部分补成自己的理解。在那之前，我不会说这条流程是我独立掌握的。
