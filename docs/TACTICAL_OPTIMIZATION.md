# BOT 战术优化：独立服验收

本轮不改经济、买枪、枪法或反应时间。正式服不加载独立服探针、不沿用独立服的 CFG／数据库。

| 次序 | 改动 | 开关（默认） |
| --- | --- | --- |
| 1 | Inferno、Mirage、Nuke 开局移动命令在连续停滞后，最多替一名 BOT 改一次同路线目标；已到位、投道具、梯子和空中暂停不计。找不到站得下且导航可达的点则不换点。持包 BOT 进点途中持续卡住时，仅把持包者交回原生 AI，队友不改目标。 | `sm_bot_t_route_retry 1` |
| 2 | 三图 CT 按 A/B 点安排可到包点的多个入口，找不到时沿用通用分配。清场后预估到达和拆弹时间，考虑有没有钳；有真人 CT 或选不到合适 BOT 时保留原生选择。T 下包后尝试给最近一名守包者安排可见炸弹视角，其他人看回防方向。 | `sm_bot_ct_retake_roles 1`、`sm_bot_t_postplant_sectors 1` |
| 3 | Mirage 使用已有录制：直接打 A 不选窗口烟，B 二楼用本路烟闪，有 Catwalk 分路的队员才可选窗口烟。包匪不离队投录制道具，每名执行者最多有 4 秒；CT 最多派一名附近有烟的人拖延，其他人不被分派。 | `sm_bot_mirage_route_utility 1` |
| 4 | Mirage 可选：默认进攻上叠加一名无包的佯攻者，主力不转点；标准 CT 阵型上叠加 A 点双人短前探，超时或发生交火时按职责回退。它们不替换原有战术抽签。 | `sm_bot_t_fake_opening_chance 0`、`sm_bot_ct_pair_pressure_chance 0` |
| 5 | Mirage／Nuke 标准 CT 阵型尝试分开重叠站位，或给重复瞄点换一条可见枪线；没有合适位置不移动，保留 Inferno 原来的专属点位。 | `sm_bot_ct_cover_spacing 1` |
| 6 | 建立空服测试和日志检查，核对路线、目标事件、回合结果、加时和资源下载。先禁用子功能排查；`sm_bot_ct_tactics_enable 0` / `sm_bot_t_tactics_enable 0` 会撤销对应的调度命令。 | 测试插件默认关闭 |

## 验收步骤

1. 用独立的 App 740 目录和端口安装；正式服数据库、配置和插件在任何部署前单独备份。只在独立服开启 `plant_route_runtime_probe.smx`、`tactical_stability_runtime_probe.smx`，不要复制到正式服。
2. 路线试验从 `de_inferno` 启动，开启 `sm_plant_route_probe 1`、`sm_plant_route_probe_series 1`。第一轮设 `sm_plant_route_probe_stall 1`，观察三个 `ROUTE_STALL_PASS`；第二轮关闭 stall，`sm_plant_route_probe_clear_delay 7.0`，核对三图 `PLANT_ROUTE_PASS` 和 `RETAKE_ROUND winner=3 reason=7`。有武器、道具、交火条件的全对局另测。
3. Mirage 道具试验使用 `sm_plant_route_probe_utility 1`，看实际烟闪事件与回合结果；实验组合用 `sm_plant_route_probe_combos 1` 并临时设两项实验概率为 100，核对佯攻者不是包匪和两名 CT 能回原位。结束恢复概率为 0。
4. 仅启用 `sm_tactical_stability_fixture 1` 测短局换边与撤销订单；它用测试结束条件推进比赛，不改正式赛制。运行 `tests/check_tactical_isolated_regression.ps1`，传入独立服目录和回环 HTTP 资源地址，检查其余回归。用 `tests/check_tactical_optimization.ps1` 核对卡路、回防、组合、道具和换边日志（回防系列同时有道具时可复用同一份日志）。
5. 尚需真人从 LAN 连接，测试取得资源、加入队伍、重连与离开后 BOT 槽位；还需要真人／正常交火样本判断补枪和胜率，空服结果不能代替这些验收。

## 本轮记录

- Inferno、Mirage、Nuke 三图受控卡路均由基线的零次替换变为一次同路替换，其他四个目标保持不变。
- Inferno B、Mirage A、Nuke B 全部通过真下包、真拆弹和 CT 拆弹获胜的回合结果；下包到拆除分别为 19.35、17.10、33.32 秒。测试对手先保留约 7 秒，再清场，不代表有交火时的成功率。
- Mirage 记录到真实烟雾落地；可选假打试验还观察到一路队员的 `1st Arch Smoke` 录像实际投出。尚未逐一实跑 A 点所有烟闪和 CT 指定防守烟。
- 短局在常规半场及加时半场均保持 5v5，10 个原 BOT userid 交换阵营，关掉两侧调度后订单数为 0。换图、回放日志检查及 36 项其它回归通过，包含独立 HTTP 资源原始字节、HEAD、禁止访问私有路径测试。
- 上线前复测曾发现 Inferno 包匪在香蕉道停滞；`sm_plant_route_probe_plant_stall 1` 的受控用例先得到 `PLANT_HANDOFF_FAIL`，修正后得到 `PLANT_HANDOFF_PASS`，解除冻结后实际跑到 B 区下包，CT 在下包后 20.10 秒拆除。该用例只冻结测试 BOT，并不注入下包或拆包事件。
- 最终部署版本（T 0.1.5、CT 0.1.8）重新通过 36 项回归和三图未冻结包匪的实跑；Inferno B、Mirage A、Nuke B 从实际下包到拆除分别为 20.10、18.10、30.60 秒，三轮均为引擎判 CT 拆包获胜。这些轮次没有有交火的回防；真人进退与资源下载仍需客户端验收。

## 正式服部署与回滚

停服更新三个 `.smx`、对应三个源码及新增 `bot_mirage_utility.inc`，未启动正式服。配置、SQLite 和其他插件共 273 项哈希保持不变。已验证备份 203 项配置／SQLite 文件及被替换的六个文件；从正式服 SourceMod `data/tactical-optimization-rollback-20261114` 按原相对路径可取回。回滚代码时保持停服，恢复六个旧文件即可，新增 include 在旧版不被使用，无需还原数据库或配置。测试插件和日志不随正式服部署。
