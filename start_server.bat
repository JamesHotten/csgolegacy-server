@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0server"
set "SteamAppId=740"
set "SteamGameId=740"

if not exist "srcds.exe" (
    echo [ERROR] CS:GO Legacy server is not installed. Run install_server.ps1 first.
    pause
    exit /b 1
)

echo Starting CS:GO Legacy BetterBots server...
srcds.exe -game csgo -console -usercon -condebug -conclearlog -tickrate 128 -ip 0.0.0.0 -port 27016 -clientport 27006 -insecure -maxplayers_override 20 +game_type 0 +game_mode 1 +map de_mirage +exec server.cfg

endlocal
