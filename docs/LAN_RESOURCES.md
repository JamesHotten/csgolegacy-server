# 局域网资源下载

`start_server.bat` 在启动游戏服务器前运行 `lan_resources.ps1`，通过 TCP `27080` 提供只读游戏资源，并生成 `csgo/cfg/lan_resources.cfg`。`server.cfg` 执行此文件，将 `sv_downloadurl` 设置为本机局域网 IPv4 地址。已有服务通过实际文件内容与响应标记校验后复用，重复启动不会再开一个资源服务。

无需 Python、Web 服务器或公网域名；使用 Windows 自带 PowerShell。资源服务在后台运行，可跨游戏服务器重启复用。首次为其他电脑部署时，Windows 防火墙需要允许局域网访问 TCP `27080`，游戏连接仍使用原 UDP `27016`。不要把 HTTP 地址设成 `127.0.0.1`，否则其他电脑会下载自己的回环地址。

其他电脑需要下载时，在服务器上用**管理员 PowerShell**执行一次（仅允许本地子网）：

```powershell
New-NetFirewallRule -Name CSGOLegacy-LAN-Resources-TCP -DisplayName "CSGO Legacy LAN resources (TCP 27080)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 27080 -RemoteAddress LocalSubnet -Profile Any
```

手动启动或指定网卡（服务器运行时也可执行）：

```powershell
.\lan_resources.ps1 -ServerDir "D:\CSGOServer\server" -BindAddress "192.168.100.100"
```

随后在服务器控制台执行 `exec lan_resources`，新连接即可使用 HTTP 下载。网卡地址变化后，重跑脚本并重新执行该配置。日志位于 `csgo/addons/sourcemod/data/lan-resources/`。

仅提供 `materials`、`models`、`sound`、`maps`、`particles`、`resource/flash` 中明确允许的资源类型，不列目录，不提供 `.cfg`、`.sq3`、`.smx` 或源码，拒绝目录跳转与重解析点。

回退：服务器执行 `sv_downloadurl ""`，并从 `server.cfg` 移除 `exec lan_resources` 即可恢复原下载方式。客户端已有资源不受影响；缺少自定义队标的客户端可能再次遇到原生传输停滞。该服务不修改队标 ID、图形内容、BOT 战术或玩家数据库。
