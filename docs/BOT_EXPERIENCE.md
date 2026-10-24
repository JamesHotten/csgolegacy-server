# BOT 战术经验数据（仅记录）

`000_bot_tactical_experience.smx` 默认开启记录：`sm_bot_experience_record_enable 1`。它不计算胜率、不调整战术概率，也不修改 BOT 的购买、瞄准、路径或经济。CT/T 调度器通过可选 native 上报开局方案；记录器不存在或关闭时，调度器仍正常运行。

数据库位于 `csgo/addons/sourcemod/data/sqlite/bot_tactical_experience.sq3`，独立于皮肤、段位和玩家身份数据库。服务器重启后数据保留。完整战术回滚会移除记录器和配置，但保留该 SQLite 文件，避免误删历史数据。
数据库使用 WAL；在线备份请用 SQLite 的 `.backup`，或停服后连同 `-wal` 文件一起备份，不要只复制运行中的 `.sq3` 主文件。

`rounds` 每个有效回合一行：地图、开始时间（Unix 秒）、回合索引、双方经济档（`eco`/`force`/`full`）、开局战术、目标包点、受调度 BOT 数、胜方和引擎结束原因。CT 战术为 `standard`/`push`/`stack`，标准防守的目标记作 `both`；T 战术为 `default`/`rush`/`split`。没有有效 NAV、没有 BOT 或战术插件关闭时，相应战术记作 `none`。管理员中途重新规划不覆盖首次开局记录。T 中期转点不会修改开局目标；后续可用真实下包事件与之对照。

`events` 每条击杀或成功下包一行，通过 `round_id` 关联 `rounds`。击杀记录双方阵营、是否 BOT、BOT 名称、武器、死亡位置；下包记录下包者、实际 A/B 包点及下包位置。真人姓名和 Steam 身份不写入此库。世界伤害、自杀等击杀仍会记录，但攻击者阵营可能为 `0`。只保存已正常结束的非热身回合；中途停服或重开造成的未结算回合会丢弃。

`signals` 记录低频诊断节点：双方首次目击与首次造成伤害、T 集结结束原因（接敌／到位／超时）、进攻提交与中期转点、CT 补防与回防阶段、BOT 命令到位／释放原因、开始／中止下包，以及道具投出和烟／闪／雷／火的爆点。T 命令连续 4 秒没有明显位移或靠近目标时只记录一次 `route_stall`，不替 BOT 改路或释放命令。`elapsed_ms` 是从 `round_start` 起的毫秒数，包含冻结时间；`x/y/z` 对爆点事件是道具落点，其余为关联玩家当时位置或 0。它只反映事件发生，不直接证明烟闪是否有效。原有 `rounds`、`events` 表不改结构，旧数据库启动时自动新增 `signals` 表。


记录在回合内暂存、回合结束时一次事务写入，避免每次交火同步写盘。最多暂存 64 个击杀／下包事件和 96 个诊断节点；超出上限的后续节点不记录，但不影响回合或 BOT 行为。若数据库不可用，记录器写错误日志，BOT 原有行为不受影响。调度器与记录器通过可选 native 解耦，移除或关闭记录器时原有战术保持不变。

查询示例（在服务器目录执行）：

```powershell
sqlite3 csgo/addons/sourcemod/data/sqlite/bot_tactical_experience.sq3 "SELECT id,map,ct_plan,ct_site,t_plan,t_site,winner FROM rounds ORDER BY id DESC LIMIT 10;"
sqlite3 csgo/addons/sourcemod/data/sqlite/bot_tactical_experience.sq3 "SELECT round_id,kind,actor_team,victim_team,weapon,site FROM events ORDER BY id DESC LIMIT 20;"
sqlite3 csgo/addons/sourcemod/data/sqlite/bot_tactical_experience.sq3 "SELECT round_id,elapsed_ms,team,kind,detail,site FROM signals ORDER BY id DESC LIMIT 30;"
```

暂停后续记录：`sm_bot_experience_record_enable 0`。这不会删除已有数据，也不会关闭 CT/T 战术。
