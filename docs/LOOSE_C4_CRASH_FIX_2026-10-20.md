# 掉包原生空指针：可回滚修复（2026-10-20）

## 证据及修复范围

Steam 转储：`C:\Program Files (x86)\Steam\dumps\crash_srcds.exe_20261020153656_1.dmp`。
SHA256：`F211DB4E4DF0008535B7BFB1B192E8DF6D6408025A649A81BA4032A25660A128`。
时间：2026-10-20 15:36:56（UTC+8）。异常 `0xC0000005`，读取地址 `0xD4`。
现场为 `server.dll+0x4E06D3` 的 `mov eax,[ebx+0xD4]`，EBX 和首个参数均为 0。
调用者先查询 `CCSBot::CanSeeLooseBomb`，再从原生 BOT 管理器取得掉包对象传给后续逻辑。
转储未包含管理器全局数据，不能据此还原掉包对象失效的完整触发过程。

原 BetterBots 后置钩子只要找到任意无主 `weapon_c4`，就会强制返回真，
并额外给 CT 下达接近命令。这不能保证原生管理器有有效的掉包对象，存在破坏原生判断前提的风险。

本次保守修复：

- 原钩子只返回 `MRES_Ignored`，不修改引擎返回值，也不额外执行 `BotMoveTo`。
- 保留现有 CT 调度器的真实目击共享、全队守包、交火释放与安静后恢复。
- `FindLooseBomb` 旧辅助函数改为 `stock`，仅避免不再使用后的编译警告，不改函数逻辑。
- 安装器包含幂等迁移，重复部署不会恢复旧覆盖逻辑，也不会重复插入保护段。
- 没有修改反应、枪法、购买、经济、皮肤或战绩规则；没有执行数据库结构变更或手工数据恢复。

## 验证

`tests/ct_loose_c4_runtime_probe.sp` 在原生 BOT AI 停止时创建不可见的测试 C4，
调用原生视野查询，验证原生假值不会被提升为真。不主动执行消费空指针的后续引擎代码。

同一运行测试在修复前输出：

```text
CT_GUARD_PROBE native_loose_c4_false_not_promoted FAIL
CT_GUARD_PROBE_FAIL failures=1
```

修复后输出：

```text
CT_GUARD_PROBE native_loose_c4_false_not_promoted PASS
CT_GUARD_PROBE_PASS failures=0
```

全员守包、接敌立即释放、连续开火延长安静窗口、安静后归位、普通补防不覆盖守包及 C4 消失清理均通过。
27 项 PowerShell 回归检查全部通过；最终重编译无警告。
重复安装后保护段仅一处。正常启动已确认 CT/T 调度、经验记录开启，BOT 可移动和开枪，胜负条件正常。
测试 SMX 已移入 `plugins/disabled`，正常服务器不加载测试探针。

这验证了不安全覆盖被消除及现有守包功能仍工作，不等于完全复现并证明 15:36:56 的所有触发条件。
真人接管 BOT、掉包/捡包交错情况下仍需要实战观察是否复发。

## 精确回滚

修复前运行文件保留在：
`D:\CSGOServer\server\csgo\addons\sourcemod\data\ct-loose-c4-fix-20261020`。
其中 `bot_stuff.sp` 与 `bot_stuff.smx` 是本次修复前的完整配对，不是最早未装战术的版本。

如出现明确回归，先关闭目标服务器，再分别将这两个备份复制回
`csgo/addons/sourcemod/scripting/bot_stuff.sp` 和 `csgo/addons/sourcemod/plugins/bot_stuff.smx`。
无需回滚 CT/T 调度器或玩家数据库。
注意：恢复旧 SMX 也会恢复已知不安全覆盖；再次运行现有安装器会重新应用保护。
不要把通用 `rollback_ct_tactics.ps1` 当作本次小修复的精确回滚，它移除的功能范围更大。
