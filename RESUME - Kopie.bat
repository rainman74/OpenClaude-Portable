@echo off & setlocal enabledelayedexpansion
chcp 65001 >nul
title OpenClaude - Resume Last Session
goto :INIT

:INIT
set "ENGINE_DIR=%~dp0engine\"
set "USB_ROOT=%ENGINE_DIR%..\"
set "DATA_DIR=%USB_ROOT%data"
set "ENV_FILE=%DATA_DIR%\ai_settings.env"
set "NODE_DIR=%ENGINE_DIR%node-win-x64"
set "GIT_DIR=%ENGINE_DIR%git-win-x64"
set "GIT_BASH=%GIT_DIR%\bin\bash.exe"
set "GIT_EXE=%GIT_DIR%\bin\git.exe"
set "OC_BIN=%ENGINE_DIR%node_modules\@gitlawb\openclaude\bin\openclaude"

set "CLAUDE_CONFIG_DIR=%DATA_DIR%\openclaude"
set "PORTABLE_HOME=%DATA_DIR%\home"
set "XDG_CONFIG_HOME=%DATA_DIR%\config"
set "XDG_DATA_HOME=%DATA_DIR%\app_data"
set "XDG_CACHE_HOME=%DATA_DIR%\cache"
set "APPDATA=%DATA_DIR%\app_data"
set "LOCALAPPDATA=%DATA_DIR%\local_app_data"
set "HOME=%PORTABLE_HOME%"
set "USERPROFILE=%PORTABLE_HOME%"

set "PATH=%NODE_DIR%;%GIT_DIR%\cmd;%GIT_DIR%\bin;%GIT_DIR%\usr\bin;%PATH%"
set "CLAUDE_CODE_GIT_BASH_PATH=%GIT_BASH%"
goto :MAIN

:MAIN
if not exist "%NODE_DIR%\node.exe" (
    echo [ERROR] Node.js was not found: %NODE_DIR%\node.exe
    echo Please run START.bat first.
    pause
    exit /b 1
)

if not exist "%GIT_BASH%" (
    echo [ERROR] Git Bash was not found: %GIT_BASH%
    echo Please run START.bat first.
    pause
    exit /b 1
)

if not exist "%GIT_EXE%" (
    echo [ERROR] Git executable was not found: %GIT_EXE%
    echo Please run START.bat first.
    pause
    exit /b 1
)

if not exist "%OC_BIN%" (
    echo [ERROR] OpenClaude was not found: %OC_BIN%
    echo Please run START.bat first.
    pause
    exit /b 1
)

if exist "%ENV_FILE%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%ENV_FILE%") do (
        set "%%A=%%~B"
    )
) else (
    echo [WARN] No provider configuration found: %ENV_FILE%
)

if not "!AI_PROVIDER!" == "anthropic" (
    set "ANTHROPIC_API_KEY="
)

set "SESSION_ID="
set "WORK_DIR="

if "%~1" == "" goto ARGS_DONE

if /i "%~1" == "--cwd" (
    set "WORK_DIR=%~2"
    goto ARGS_DONE
)

if /i "%~1" == "--resume" (
    set "SESSION_ID=%~2"
    if /i "%~3" == "--cwd" (
        set "WORK_DIR=%~4"
    ) else (
        set "WORK_DIR=%~3"
    )
    goto ARGS_DONE
)

if exist "%~1\" (
    set "WORK_DIR=%~1"
    goto ARGS_DONE
)

set "SESSION_ID=%~1"
if /i "%~2" == "--cwd" (
    set "WORK_DIR=%~3"
) else (
    set "WORK_DIR=%~2"
)

:ARGS_DONE
if /i "%~1" == "--resume" (
    if not defined SESSION_ID (
        echo [ERROR] No session ID provided after --resume.
        pause
        exit /b 1
    )
)
if /i "%~1" == "--cwd" (
    if not defined WORK_DIR (
        echo [ERROR] No working directory provided after --cwd.
        pause
        exit /b 1
    )
)
if /i "%~2" == "--cwd" (
    if not defined WORK_DIR (
        echo [ERROR] No working directory provided after --cwd.
        pause
        exit /b 1
    )
)
if /i "%~3" == "--cwd" (
    if not defined WORK_DIR (
        echo [ERROR] No working directory provided after --cwd.
        pause
        exit /b 1
    )
)
if not defined WORK_DIR set "WORK_DIR=%ENGINE_DIR%"

if not exist "!WORK_DIR!\" (
    echo [ERROR] Working directory was not found: !WORK_DIR!
    pause
    exit /b 1
)

set "PROVIDER_ARGS="
if defined AI_PROVIDER set "PROVIDER_ARGS=--provider !AI_PROVIDER!"
set "CMD_ARGS=--dangerously-skip-permissions"

if not "!AI_PROVIDER!" == "ollama" goto SKIP_OLLAMA_START
if not exist "%DATA_DIR%\ollama\ollama.exe" goto SKIP_OLLAMA_START

echo [~] Starting Local Ollama Server...
set "OLLAMA_MODELS=%DATA_DIR%\ollama\data"
start "Ollama Portable" /b /min "%DATA_DIR%\ollama\ollama.exe" serve >nul 2>&1
timeout /t 3 /nobreak >nul
echo [OK] Ollama running!
if not exist "%USB_ROOT%tools\local-proxy.js" goto SKIP_PROXY_START
echo [~] Starting local speed proxy...
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter 'Name = ''node.exe''' | Where-Object { $_.CommandLine -like '*local-proxy.js*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
start "LocalProxy" /b /min "%NODE_DIR%\node.exe" "%USB_ROOT%tools\local-proxy.js"
timeout /t 2 /nobreak >nul
set "OPENAI_BASE_URL=http://localhost:11435/v1"
echo [OK] Speed proxy active.
:SKIP_PROXY_START

:SKIP_OLLAMA_START

pushd "!WORK_DIR!"
if defined SESSION_ID (
    call "%NODE_DIR%\node.exe" "%OC_BIN%" !PROVIDER_ARGS! !CMD_ARGS! --resume "!SESSION_ID!"
    set "OC_STATUS=!ERRORLEVEL!"
) else (
    call "%NODE_DIR%\node.exe" "%OC_BIN%" !PROVIDER_ARGS! !CMD_ARGS! --continue
    set "OC_STATUS=!ERRORLEVEL!"
    if not "!OC_STATUS!" == "0" (
        echo [WARN] No conversation found to continue. Starting a new session in the current working directory...
        call "%NODE_DIR%\node.exe" "%OC_BIN%" !PROVIDER_ARGS! !CMD_ARGS!
        set "OC_STATUS=!ERRORLEVEL!"
    )
)
popd

if not "!AI_PROVIDER!" == "ollama" goto SKIP_OLLAMA_STOP
if not exist "%DATA_DIR%\ollama\ollama.exe" goto SKIP_OLLAMA_STOP
echo.
echo [~] Stopping Local Ollama Server...
taskkill /f /im ollama.exe >nul 2>&1
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter 'Name = ''node.exe''' | Where-Object { $_.CommandLine -like '*local-proxy.js*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
:SKIP_OLLAMA_STOP

pause
goto :END

:END
exit /b !OC_STATUS!
