# Legacy 十图 CT 补防和回防入口

CT 调度器 `0.1.15` 的范围是 Inferno、Train、Mirage、Nuke、Dust II、Overpass、Vertigo、Cache、Ancient、Anubis。购买、经济、武器数值、反应、T 进攻与既有的 Mirage/Nuke 专项不变。

## 下包前：有证据才补位

标准防守收到报点或掉人时，用实际包点高度和距离区分包区与中间地带。可支援的 BOT 必须有实际导航路径到达同层站位，不能在交火、被闪或还在执行上一次补防；普通补防不抽走另一点的最后一名守员。候选站位控制暴露角度，并至少能架真实接触处或此包点的一个入口。没有合适站位则不强拉。

如果附近已有队员独立看到同一个敌人、现在仍然可见且枪线实际畅通，单次报点不额外调人。这个条件不阻止强攻确认或已确认包匪的全队回防，不抢掉包守包，也不改变 Nuke 下层锚点的优先补位。独立记录 `reinforce_skip/already_supported`。

## 下包后：用本图的入口，不为集合强绕路

每点尝试配置的回防入口，要求从实际守员到入口及由入口到炸弹均可走。相对直接路径，多出的估计导航距离不得超过 560 单位。若具名入口已不适合当前存活阵容，仍给未分到入口的队员原有通用回防位。实际分配才记录 `retake_lane_assigned`；仅找到候选不计入。

沿用单人、剩余引信太短、已接敌、无人防守等现有推进条件。Cache 从它的内置 NAV 为 CT 单独采用 A 的 Truck、ARamp、Catwalk 和 B 的 Rafters、Back、CTSpawn；T 的守包观察入口表不变。

## 验收与回滚

- `tests/ct_teamwork_runtime_probe.sp` 在回环独立服逐图 A/B 输入一次非包匪接触，对照实际下发目标、同层且无遮挡的枪线及另一点锚位是否保留。
- `tests/check_ct_teamwork_runtime.ps1` 汇总上述测试与 `-ctrefinelive` 下的十图真下包/拆包回归。额外记录 Overpass 正常速度 5v5 的实战对照；胜率不代替行动验证。
- 2026-11-17：最终二进制正常速度测试，20/20 首次报点各调一名 CT 且保留另一点锚位；20/20 真实下包并拆除成功，19 个用例实际分配到具名入口，覆盖全部十图。Nuke B 在该用例保守回退到通用入口，仍走完回防并拆弹。另有 36 项已有代码／数据检查通过。
- Overpass 旧版和候选各 10 回合、半场对调：CT 胜场 2→4，CT 首杀 3→6，T 下包 9→6；CT 实际开始拆弹 3→1，拆成均为 1。这个短样本不能证明整体胜率，也不能说明回防已经更强。实战候选没有触发 `already_supported`；更严格的同敌人校验不改变该组已观察到的补防决定。
- 设 `sm_bot_ct_profiled_relief 0` 回退新增的十图补防，设 `sm_bot_ct_profiled_retake 0` 回退新增的十图具名回防。旧 Overpass 专项仍由 `sm_bot_ct_overpass_teamwork` 单独控制。建议在下一回合观察效果。
- 完全回滚：停服，从 `csgo/addons/sourcemod/data/ct-tenmap-teamwork-rollback-20261117` 按相对路径恢复 CT 插件及源码。其他插件、配置和玩家数据不需要还原。
