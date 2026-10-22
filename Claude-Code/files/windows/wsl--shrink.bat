@echo off
setlocal EnableExtensions EnableDelayedExpansion
title WSL disk shrink
set "WSL_UTF8=1"

rem WSL disk shrink - reclaim the space a WSL distro's ext4.vhdx keeps after
rem files are deleted inside Linux. Windows does not shrink a virtual disk by
rem itself, so the .vhdx grows to its high-water mark and stays there.
rem
rem Two things are done for every installed distro:
rem   1. sparse mode (wsl --manage --set-sparse true) - the disk gives space
rem      back automatically from now on;
rem   2. one-off compaction with diskpart - reclaims what is already held.
rem
rem Nothing is hardcoded: distro names come from `wsl -l -q`, and the .vhdx
rem paths come from the Lxss registry, so it works for any user name, any
rem install location and any distro name (spaces included).
rem
rem Needs administrator rights - it asks for them itself.
rem Run with /y to skip the confirmation prompt.

rem /y anywhere on the command line skips the confirmation. It has to survive
rem the elevation below, so it is detected once here and carried along.
set "ASSUME_YES=0"
if /i "%~1"=="/y" set "ASSUME_YES=1"
if /i "%~2"=="/y" set "ASSUME_YES=1"

if /i not "%~1"=="elevated" (
    fltmc >nul 2>&1
    if errorlevel 1 (
        echo Requesting administrator rights...
        rem The path goes through the environment rather than the command
        rem string: a path containing a quote or an apostrophe would otherwise
        rem break the PowerShell parsing.
        set "SELF=%~f0"
        set "ARGS=elevated"
        if "!ASSUME_YES!"=="1" set "ARGS=elevated /y"
        powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath $env:SELF -ArgumentList $env:ARGS"
        exit /b
    )
)

echo === WSL disk shrink ===
echo.

where wsl.exe >nul 2>&1
if errorlevel 1 (
    echo WSL is not installed - nothing to shrink.
    pause
    exit /b 1
)

if "!ASSUME_YES!"=="0" (
    echo This shuts down WSL, so every running session ends.
    choice /c YN /n /m "Continue? [Y/N] "
    if errorlevel 2 exit /b 0
    echo.
)

echo [1/3] Shutting down WSL...
wsl.exe --shutdown
timeout /t 5 /nobreak >nul

echo.
echo [2/3] Enabling sparse mode...
set "SPARSE=0"
for /f "usebackq delims=" %%D in (`wsl.exe -l -q`) do (
    rem Keep the name exactly as WSL printed it. Trimming spaces here would
    rem break names like "Ubuntu 22.04" - wsl --manage would not find them.
    set "D=%%D"
    if not "!D!"=="" (
        echo     !D!
        wsl.exe --manage "!D!" --set-sparse true >nul 2>&1
        if not errorlevel 1 set "SPARSE=1"
    )
)
if "!SPARSE!"=="0" echo     sparse mode is not supported by this WSL version - skipping

echo.
echo [3/3] Compacting ext4.vhdx images...
set "FOUND=0"
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss" /s /v BasePath 2^>nul ^| findstr /i "BasePath"') do (
    set "VHDX=%%B\ext4.vhdx"
    if exist "!VHDX!" (
        set "FOUND=1"
        call :ShowSize "before"
        echo     !VHDX!
        >"%TEMP%\wsl_compact.txt" (
            echo select vdisk file="!VHDX!"
            echo attach vdisk readonly
            echo compact vdisk
            echo detach vdisk
            echo exit
        )
        diskpart /s "%TEMP%\wsl_compact.txt" >nul 2>&1
        del "%TEMP%\wsl_compact.txt" >nul 2>&1
        call :ShowSize "after "
    )
)
if "!FOUND!"=="0" echo     no ext4.vhdx found

echo.
echo Done.
pause
exit /b 0

:ShowSize
rem Sizes go through PowerShell: batch arithmetic is 32-bit and overflows on
rem any real WSL disk.
for %%I in ("!VHDX!") do set "BYTES=%%~zI"
for /f "usebackq delims=" %%S in (`powershell -NoProfile -Command "'{0,8:N2} GB' -f (!BYTES!/1GB)"`) do (
    echo            %~1 %%~S
)
exit /b 0
