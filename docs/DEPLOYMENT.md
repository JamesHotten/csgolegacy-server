# 部署手册

## 1. 环境要求

- Windows 10/11 或 Windows Server 2019 及以上
- 至少 60 GB 可用磁盘空间
- 可访问 SteamCMD 和 GitHub Release
- PowerShell 5.1 或 PowerShell 7
- CS:GO Legacy 客户端版本 `1.38.8.1`（客户端/服务端版本必须一致）

## 2. 获取仓库

```powershell
git clone git@github.com:JamesHotten/csgolegacy-server.git
Set-Location csgolegacy-server
```

没有 Git 时也可以在 GitHub 页面下载 Source ZIP。

## 3. 修改基础配置

编辑 `config/server.cfg`，至少修改：

```cfg
hostname "你的服务器名称"
rcon_password "设置一个强密码"
sv_password ""
exec mr15
```

不要把真实 RCON 密码提交回公共仓库。

默认配置启用 `mp_drop_knife_enable 1`，玩家可像丢弃枪械一样丢弃当前刀具；MR15 与 MR12 都保留此设置。

`exec mr15` 是默认 CS:GO Legacy 配置；`exec mr12` 使用当前 CS2 配置。两者通过 `sm_lan_economy_apply 0/1` 让插件在一个事务中统一切换下包被拆补助、CZ75/XM1014/Zeus 击杀奖励、FAMAS/M4A4/MP7/MP5-SD/Bizon/CT 燃烧弹实际价格、退款能力和 CS2 CT 淘汰补助。插件验证全部必要 CVar 后才提交切换，失败会恢复旧值；重复执行当前模式也会重新校正全部参数。运行中成功切换会丢弃尚未恢复的断线经济和本回合退款账本，防止混算，但不会删除数据库数据。换图时只重新应用已选择的模式，不会擅自把 MR12 改回 MR15。

要切换为 CS2 MR12 赛制，在服务器控制台执行 `exec mr12`。该配置同时设置 24 回合、先到 13 分结束、MR3 加时、加时 `$10,000` 初始经济，并启用完整 CS2 经济。执行 `exec mr15` 恢复 30 回合、先到 16 分和完整 CS:GO Legacy 经济；MR15 同样启用 MR3 加时且加时初始资金为 `$10,000`。切换后应使用 `mp_restartgame 1` 开始新比赛。

CS2 模式中输入 `!refund` 可打开退款菜单，`!refund last` 可直接退款最近一件合格物品。物品必须在本回合买入、仍由购买者持有，并且操作发生在购买区和购买时间内；开火或投掷、丢弃、护甲受损、开始使用拆弹器、死亡、换回合或切换模式后不可退款。CS:GO 740 客户端菜单可能继续显示客户端本地价格，服务器实际扣款和退款以所选规则为准。

## 4. 安装

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install_server.ps1
```

脚本执行内容：

1. 下载 SteamCMD。
2. 匿名登录并执行 `app_update 740 validate`。
3. 下载 `v1.0.0` Release 的 MOD 覆盖包。
4. 解压到 `server\csgo`。
5. 应用仓库中的 `config/server.cfg`、`config/mr15.cfg`、`config/mr12.cfg` 和最终竞技模式覆盖配置。
6. 写入运行所需的 AppID 文件。

### 对已经安装好的 App 740 服务器应用 MOD

若全新服务器已经通过 SteamCMD 安装完成，例如：

```text
D:\GameServers\CSGOLegacy\srcds.exe
D:\GameServers\CSGOLegacy\csgo\
```

先关闭该服务器，然后在本仓库目录运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\apply_mods.ps1 -ServerDir "D:\GameServers\CSGOLegacy"
```

脚本会验证目标目录和发行包校验值，将完整 MOD、当前配置及 SQLite 快照写入 `csgo`，并生成 AppID `740` 所需文件和适用于该目标目录的 `start_server.bat`。它不会重新下载或校验 Valve 基础游戏文件。

这里的校验仅针对下载的固定发行压缩包，不会对日志、缓存、崩溃转储或服务器启动后持续变化的 SQLite/玩家数据做逐文件校验。如果目标服务器已经运行过同类插件，请先备份原有 `addons\sourcemod\data\sqlite`，因为首次套用发行包会写入随包提供的 SQLite 快照。

## 5. 启动

双击或在终端运行：

```text
start_server.bat
```

默认参数：

```text
-port 27016 -clientport 27006 -tickrate 128 -insecure
+game_type 0 +game_mode 1 +map de_mirage
```

## 6. 本地或局域网连接

客户端必须启动 CS:GO Legacy，不是 CS2。打开控制台输入：

```text
connect 服务器局域网IP:27016
```

同机运行客户端和服务端时，不建议使用 Steam 的 `steam://connect` 链接，因为 App 730 现在可能拉起 CS2。直接在 Legacy 客户端控制台使用 `connect`。

## 7. 防火墙

至少允许 `server\srcds.exe` 的入站通信，并放行 UDP 27016。若需要 RCON 或公网部署，应按自己的安全策略额外限制来源地址。

示例（管理员 PowerShell）：

```powershell
New-NetFirewallRule -DisplayName "CSGO Legacy Server UDP 27016" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 27016 -Program "$PWD\server\srcds.exe"
```

## 8. 更新

```powershell
.\update_server.ps1
```

更新脚本会重新验证 App 740，并再次覆盖当前 Release 的 MOD 文件。配置文件最终以仓库的 `config/server.cfg` 为准。

## 9. 数据与备份

运行后产生的数据位于：

```text
server\csgo\addons\sourcemod\data\sqlite
```

升级、迁移前应备份该目录。`v1.0.0` Release 已包含制作发行包时的 SQLite 快照，因此新机器会继承现有 RankMe、皮肤、贴纸、手套和客户端偏好数据。发行包不携带日志、管理员名单或私密密码。

## 10. 常见问题

### 一直显示 Retrying

- 确认服务端监听 UDP 27016。
- 确认客户端和服务端没有占用同一个 client port。
- 确认使用 `connect IP:27016`。
- 检查 Windows 防火墙和代理/TUN 软件。

### Steam 打开了 CS2

不要使用 Steam URI。先手动启动 CS:GO Legacy，再在控制台执行 `connect`。

### `sv_lan 0` 后无法连接

当前 Legacy + App 740 + `-insecure` 环境建议保持 `sv_lan 1`。公网认证需要额外的 GSLT 和兼容的 Steam 票据，不能只改一个 cvar。

### 后台中文乱码

启动脚本已经执行 `chcp 65001`。终端字体仍需支持中文。

### LAN 真人身份或 MOD 数据异常

部署脚本会安装 `000_lan_player_identity.smx`，并统一 RankMe、段位、武器皮肤、贴纸、手套、探员、喷漆和音乐盒的 LAN 身份。修改或升级前必须停止服务器；脚本会把第三方原始 SMX 备份到 `addons\sourcemod\plugins\disabled\lan-identity-originals`。

`James_Hotten` 固定使用 `STEAM_1:0:959533336`，旧 `STEAM_ID_LAN` 数据会以逐表原子事务迁移到该身份，换 IP 或换机器后仍可读取。其他 LAN 玩家按“IP＋昵称”生成自己的身份。迁移失败会写入 SourceMod 错误日志并停止身份插件；修复数据库问题后重启即可幂等重试。该兼容档案只按昵称识别，不等同于安全认证；公网或不受信任的 LAN 环境必须另配密码、白名单或真实 Steam 认证。若需回退，应同时恢复该目录中的原始 SMX、移除 `000_lan_player_identity.smx` 并恢复迁移前的 SQLite 备份，不能只移除身份插件，否则被改过绑定的 MOD 会因缺少 Native 而无法加载。
