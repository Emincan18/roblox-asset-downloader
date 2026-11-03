@echo off
set "DEST=%LOCALAPPDATA%\Roblox\Plugins"
if not exist "%DEST%" mkdir "%DEST%"
copy /y "%~dp0studio-plugin\AssetDownloader.lua" "%DEST%\AssetDownloader.lua" >nul
echo Plugin installiert nach %DEST%
echo Roblox Studio neu starten. Tab PLUGINS, Knopf "Asset Downloader".
pause
