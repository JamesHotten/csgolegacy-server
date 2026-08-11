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
- 新增 `lan_player_scoreboard.smx`，为 `STEAM_ID_LAN` 真人按“IP＋昵称”生成稳定的局内计分板身份
- 同 IP、同昵称的同时在线玩家仍会分配独立身份，并检测在线 AccountID 冲突
- LAN 真人在同一张地图中断线重连后，恢复击杀、死亡、助攻、MVP 和贡献分
- 保留 SQLite 存储模式，并在 Release 中包含打包时的玩家数据库快照

`lan_player_scoreboard.sp` 源码位于仓库的 `mods` 目录。部署脚本会使用覆盖包内的 SourceMod 编译器安装最新版，因此不依赖发行包中较旧的编译版。
