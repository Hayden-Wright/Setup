@echo off
cd /d "%~dp0"
Title InputSwitch
 
::filedll
 
set filedll=%windir%\system32\InputSwitch.dll
takeown /F %filedll% /A
icacls %filedll% /grant:r "*S-1-5-32-544":f
icacls %filedll% /setowner "*S-1-5-32-544" /C /L /Q
icacls %filedll% /grant:r "*S-1-5-32-545":rx
icacls %filedll% /grant:r "*S-1-5-18":f
icacls %filedll% /inheritance:r
taskkill /f /im explorer.exe
PING -n 2 -w 1000 127.0.0.1 > nul
copy ".\InputSwitch.dll.returnbox" %filedll% /Y
PING -n 2 -w 1000 127.0.0.1 > nul
start "" %windir%\explorer.exe
@pause
goto :eof