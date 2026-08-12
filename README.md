# CS:GO Legacy BetterBots Server

这是一个 Windows 下的 **CS:GO Legacy（不是 CS2）** 一键部署仓库。

仓库通过 SteamCMD 安装 Dedicated Server App `740`，再从 GitHub Release 下载 BetterBots、SourceMod、MetaMod、BOT 聊天、RankMe、皮肤、贴纸、手套和探员插件覆盖包。

## 一键安装

以 PowerShell 打开仓库目录并运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install_server.ps1
```

默认安装到仓库内的 `server` 目录。首次安装需要下载约 35 GB 的 Valve 游戏文件和约 2 GB 的 MOD 资源，请预留至少 60 GB 空间。

安装完成后运行：

```text
start_server.bat
```

## 已经安装了全新的 App 740 服务器

如果已经通过 SteamCMD 下载好了 CS:GO Legacy Dedicated Server，只需把 MOD、配置和 SQLite 数据应用到现有服务器：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\apply_mods.ps1 -ServerDir "D:\GameServers\CSGOLegacy"
```

`ServerDir` 必须是同时包含 `srcds.exe` 和 `csgo` 目录的服务器根目录。执行前先关闭该服务器；此流程不会重新下载 Valve 基础游戏文件。完成后直接运行目标目录中新生成的 `start_server.bat`。

客户端使用 CS:GO Legacy，并在控制台连接：

```text
connect 服务器IP:27016
```

同一台机器测试通常使用：

```text
connect 192.168.x.x:27016
```

## 更新

```powershell
.\update_server.ps1
```

更新脚本会验证 App 740，然后重新应用当前 Release 的 MOD 覆盖包。

## 配置

- 主配置：[config/server.cfg](config/server.cfg)
- 启动参数：[start_server.bat](start_server.bat)
- 默认游戏端口：`27016`
- 独立 client port：`27006`
- 默认地图：`de_mirage`
- 默认模式：经典竞技
- `sv_lan 1`
- `-insecure`

部署前务必修改 `config/server.cfg` 中的 `rcon_password`。

## 数据范围

Release 覆盖包包含当前 SQLite 玩家数据，可在其他机器继续使用已有 RankMe、皮肤、贴纸、手套和客户端偏好数据。

部署时只校验下载的固定发行压缩包。日志、缓存、崩溃转储以及服务器启动后持续变化的玩家数据等运行期文件，不做逐文件校验。

LAN 真人以“IP＋昵称”生成稳定的合成 Steam2 身份。RankMe、计分板段位、武器皮肤、贴纸、手套、探员、喷漆、音乐盒和相关偏好均按此身份独立保存；正常 Steam 玩家不受影响。在同一张地图中断线重连还会恢复击杀、死亡、助攻、MVP 和贡献分。同 IP、同昵称的同时在线玩家会自动分配独立会话。换图后局内战绩缓存清空，但数据库中的 MOD 配置保留。

旧共享数据明确保留给 `James_Hotten`，该昵称固定使用 `STEAM_1:0:959533336`，换 IP 或换机器也不改变；部署后旧数据迁移到此身份。部署脚本会备份被绑定替换的第三方 SMX；详细行为和回退方式见 [docs/MODS.md](docs/MODS.md) 与 [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)。

不会上传：

- Valve 的基础游戏文件（由 SteamCMD 安装）
- 服务器日志和崩溃转储
- 管理员名单
- 私有数据库密码

MOD 资源归各自作者所有，本仓库不改变第三方插件的原始授权。
