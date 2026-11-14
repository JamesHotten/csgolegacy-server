# BOT 近墙架枪回归

CT 与 T 仍照原来的任务安排移动和到位。只有在插件准备发送固定瞄准请求时，才从 BOT 当前眼位检查枪线。原方向可用时保留它；近处被挡时，在相邻方向找替代，不强制 BOT 转身。无有效方向时停止刷新固定瞄准，原生 AI 仍可观察、交火和执行目标任务。Nuke 的 CT 掉包守卫另外保留按楼层选枪线的规划。

默认开启；可通过 `sm_bot_ct_clear_watch 0`、`sm_bot_t_clear_watch 0` 分别关闭通用检查。`sm_bot_ct_nuke_guard_clear_watch 0` 独立关闭 Nuke 专用规划。

## 独立服验证

1. 只在无真人、监听本机回环地址的测试服编译并加载 `tests/tactical_sightline_runtime_probe.sp`。正式服不安装探针。
2. 从 `de_inferno` 启动竞技图，启用 `sm_objective_angle_survey 1`。探针自动轮换十张地图，在 A/B 两点分别检查 CT 开局、T 下包掩护、T 下包后守包、CT 回防集合和推进。从真实 BOT 眼位查询即将用于架枪的方向；测试站在目标点和能够落脚的偏移位置。
3. 等日志出现 `ANGLE_SURVEY_DONE` 后执行 `./tests/check_tactical_sightline_runtime.ps1 -Log <console.log>`。验证需要每种用例都存在且保留可用枪线，不能靠关闭全部架枪通过。旧版对照加 `-ExpectBlocked`。
4. 另用 `tests/ct_loose_c4_runtime_probe.sp` 验证掉包后 CT 调度和接敌释放，用 `tests/plant_route_runtime_probe.sp` 验证实际下包和拆包。角度探针的合成下包事件只用于触发战术阶段，不代表实战下包成功。

安装通过仓库既有的 `mods/install_ct_tactics.ps1`，该安装同时保留已验证的防原地连跳：记录真实起跳，有位移时重新放行，梯子、投掷与逃离危险不受重复次数限制。

2026-11-15 对照：旧版 100 个用例、2,309 个有效眼位，发现 312 条近墙枪线；通用保护版 100 个用例、2,340 个眼位，返回 2,254 条可用枪线，未发现近墙枪线。测试不等于覆盖每个对局站位或动态障碍。

另外，除 Nuke 外九图共完成 26 处掉包眼位场景，未发现近墙枪线。Overpass 有一处无法建立可见掉包的测试条件，同图另两处通过。Nuke 下层实战探针确认 T 下包及 CT 回防拆包完成。
