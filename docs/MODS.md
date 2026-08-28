# MOD 清单

Release 覆盖包来自当前已运行的服务器，而不是只保存下载链接。

## 核心组件

- MetaMod:Source
- SourceMod 1.12
- SourceScramble Manager
- CS:GO BetterBots
- BOT SteamIDs、BOT Inventory、BOT Ping、BOT Mimic
- BOT 聊天系统
- RankMe 与 RankMe 作弊功能系统
- Matchmaking 段位显示
- 武器皮肤、贴纸、手套、音乐盒
- 探员选择器
- 喷漆系统
- 回合伤害统计和其他整合包辅助插件

## 本仓库修改

- 服务端游戏端口固定为 `27016`
- 独立 client port 设置为 `27006`，减少同机客户端端口冲突
- App 740 运行变量
- UTF-8 控制台
- 默认 `sv_lan 1` 和 `-insecure`
- BOT 默认在真人加入前生成
- 新增 `000_lan_player_identity.smx`，为 `STEAM_ID_LAN` 真人按“IP＋昵称”生成稳定的合成 Steam2 身份
- 同 IP、同昵称的同时在线玩家仍会分配独立身份，并检测在线 AccountID 冲突
- RankMe、段位、武器皮肤、贴纸、手套、探员、喷漆、音乐盒和对应客户端偏好统一使用该身份，多个 LAN 真人不再共用 `STEAM_ID_LAN` 数据
- 正常 Steam 认证玩家仍使用官方 Steam 身份，不经过 LAN 数据分流
- LAN 认证尚未返回时会在 `sv_lan 1` 下同步建立合成身份，不向 MOD 暴露共享的 `STEAM_ID_LAN` 或 AccountID 0
- 计分板记录按当前 UserID 定位，并在加载阶段重复发送、进入后低频自检；冷启动首次连接和复用槽位重连均会重新建立补丁循环
- SQLite 配置下修复探员插件写死 MySQL SQL 导致的初始化失败；MySQL 配置继续使用未经修改的原始插件
- LAN 真人在同一张地图中断线重连后，恢复击杀、死亡、助攻、MVP、贡献分和官方竞技规则下累计的离线现金
- 离线账户按实际 `round_end` 结果、胜负原因、引擎维护的队伍连败档位和当前 `cash_team_*` 设置累计团队回合奖励；存活时断线的当前回合跳过，之后完整缺席的回合照常结算，击杀、下包、拆包等个人行为奖励不补发
- 现金仅在玩家重新加入断线前的同一阵营后恢复一次，随后交回游戏原生经济系统继续结算；换边、加时阶段切换和换图不携带旧经济，且始终受 `mp_maxmoney` 限制
- 经济奖励策略与身份/计分板状态机分离：`sm_lan_economy_ruleset 0` 保持原有/CS:GO Legacy 行为，`1` 使用当前 CS2 策略；CS2 策略额外按每名被消灭的 T 向每名 CT 发放 `sm_lan_economy_cs2_ct_kill_bonus`（默认 `$50`）
- 在线和断线 CT 使用同一份 CS2 团队补助；模式切换会清空尚未恢复的局内经济缓存，避免同一账户混用两套规则，但不会触碰计分板战绩、合成身份、SQLite、皮肤、贴纸、手套、探员或 Cookie
- 保留 SQLite 存储模式，并在 Release 中包含打包时的玩家数据库快照

`lan_player_scoreboard.sp` 源码位于仓库的 `mods` 目录；两套独立奖励策略分别位于 `lan_economy_csgo.inc` 和 `lan_economy_cs2.inc`。部署脚本会把三者一起编译为最先加载的 `000_lan_player_identity.smx`，从而继续共享同一套经过验证的身份、断线缓存和恢复时序，并把第三方插件的认证 Native 绑定改到统一身份服务。原 SMX 会备份到 `plugins/disabled/lan-identity-originals`。

现有共享 `STEAM_ID_LAN` 数据明确归属 `James_Hotten`：该昵称固定使用 `STEAM_1:0:959533336`，换 IP 或换机器也不会改变。首次使用新版部署脚本后，该昵称连接时会自动迁移旧的 RankMe、皮肤、手套、贴纸和探员数据；Cookie 只为该昵称继承旧共享值。其他新玩家从空白独立配置开始。每张表的冲突旧行删除与其余旧行更新在同一事务中执行，会一起提交或一起回滚；所有迁移操作均可安全重试。任一数据库失败会让身份插件明确停止加载，修复数据库问题并重启后会重试，不会静默以部分迁移状态继续提供 MOD 身份。

身份稳定条件是连接 IP 与昵称不变。两名同 IP、同昵称玩家同时在线时会使用 `#N` 会话后缀保持独立；如果这些完全无法区分的玩家全部离线后以不同顺序重连，无法可靠判断各自原来的后缀。

`James_Hotten` 的兼容身份是按昵称保留的，不是密码认证。不要让不受信任的玩家使用该昵称；需要对外开放服务器时，应另行增加管理员密码、白名单或真实 Steam 认证。仅凭 `sv_lan 1` 提供的同 IP、同昵称信息，服务器无法可靠区分两个物理客户端。
