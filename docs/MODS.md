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
- 新增 `lan_player_scoreboard.smx`，尝试为 `STEAM_ID_LAN` 真人提供计分板临时身份
- 保留 SQLite 存储模式，并在 Release 中包含打包时的玩家数据库快照

`lan_player_scoreboard.sp` 源码位于仓库的 `mods` 目录，编译版包含在 Release 覆盖包中。
