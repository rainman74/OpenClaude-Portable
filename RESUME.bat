@echo off & setlocal EnableDelayedExpansion
chcp 65001 >nul
title OpenClaude - Resume Last Session

set "ENGINE_DIR=%~dp0engine\"
set "USB_ROOT=%ENGINE_DIR%..\"
set "DATA_DIR=%USB_ROOT%data"
set "ENV_FILE=%DATA_DIR%\ai_settings.env"
set "NODE_DIR=%ENGINE_DIR%\node-win-x64"
set "GIT_DIR=%ENGINE_DIR%\git-win-x64"
set "GIT_BASH=%GIT_DIR%\bin\bash.exe"
set "GIT_EXE=%GIT_DIR%\bin\git.exe"
set "OC_BIN=%ENGINE_DIR%\node_modules\@gitlawb\openclaude\bin\openclaude"
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

if not exist "%NODE_DIR%\node.exe" (
    echo [ERROR] Node.js was not found: %NODE_DIR%\node.exe
    pause
    exit /b 1
)

if not exist "%GIT_BASH%" (
    echo [ERROR] Git Bash was not found: %GIT_BASH%
    pause
    exit /b 1
)

if not exist "%GIT_EXE%" (
    echo [ERROR] Git executable was not found: %GIT_EXE%
    pause
    exit /b 1
)

if not exist "%OC_BIN%" (
    echo [ERROR] OpenClaude was not found: %OC_BIN%
    pause
    exit /b 1
)

if exist "%ENV_FILE%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%ENV_FILE%") do (
        set "%%A=%%~B"
    )
)

if /i not "!AI_PROVIDER!"=="anthropic" (
    set "ANTHROPIC_API_KEY="
)

set "SESSION_ID="
set "WORK_DIR="
set "RESUME_DEFINED="
set "CWD_DEFINED="

:PARSE_ARGS
if "%~1"=="" goto ARGS_DONE

if /i "%~1"=="--resume" (
    if defined RESUME_DEFINED (
        echo [ERROR] Duplicate --resume parameter.
        pause
        exit /b 1
    )
    if "%~2"=="" (
        echo [ERROR] Missing session ID after --resume.
        pause
        exit /b 1
    )
    if /i "%~2:~0,2%"=="--" (
        echo [ERROR] Invalid session ID: %~2
        pause
        exit /b 1
    )
    echo(%~2| findstr /r /c:"^[A-Za-z0-9._-][A-Za-z0-9._-]*$" >nul
    if errorlevel 1 (
        echo [ERROR] Invalid session ID format: %~2
        pause
        exit /b 1
    )
    set "SESSION_ID=%~2"
    set "RESUME_DEFINED=1"
    shift
    shift
    goto PARSE_ARGS
)

if /i "%~1"=="--cwd" (
    if defined CWD_DEFINED (
        echo [ERROR] Duplicate --cwd parameter.
        pause
        exit /b 1
    )
    if "%~2"=="" (
        echo [ERROR] Missing working directory after --cwd.
        pause
        exit /b 1
    )
    if /i "%~2:~0,2%"=="--" (
        echo [ERROR] Invalid working directory: %~2
        pause
        exit /b 1
    )
    set "WORK_DIR=%~2"
    set "CWD_DEFINED=1"
    shift
    shift
    goto PARSE_ARGS
)

if not defined RESUME_DEFINED (
    if exist "%~1\" (
        if defined CWD_DEFINED (
            echo [ERROR] Duplicate working directory argument.
            pause
            exit /b 1
        )
        set "WORK_DIR=%~1"
        set "CWD_DEFINED=1"
        shift
        goto PARSE_ARGS
    )
    echo(%~1| findstr /r /c:"^[A-Za-z0-9._-][A-Za-z0-9._-]*$" >nul
    if errorlevel 1 (
        echo [ERROR] Invalid positional session ID: %~1
        pause
        exit /b 1
    )
    set "SESSION_ID=%~1"
    set "RESUME_DEFINED=1"
    shift
    goto PARSE_ARGS
)

if not defined CWD_DEFINED (
    if /i "%~1:~0,2%"=="--" (
        echo [ERROR] Unknown argument: %~1
        pause
        exit /b 1
    )
    set "WORK_DIR=%~1"
    set "CWD_DEFINED=1"
    shift
    goto PARSE_ARGS
)

echo [ERROR] Unknown argument: %~1
pause
exit /b 1

:ARGS_DONE
if not defined WORK_DIR (
    set "WORK_DIR=%ENGINE_DIR%"
)

if "%WORK_DIR%"=="" (
    echo [ERROR] Working directory is empty.
    pause
    exit /b 1
)

if not exist "%WORK_DIR%\" (
    echo [ERROR] Working directory not found: %WORK_DIR%
    pause
    exit /b 1
)

set "PROVIDER_ARGS="
if /i "!AI_PROVIDER!"=="anthropic" set "PROVIDER_ARGS=--provider anthropic"
if /i "!AI_PROVIDER!"=="gemini" set "PROVIDER_ARGS=--provider gemini"
if /i "!AI_PROVIDER!"=="ollama" set "PROVIDER_ARGS=--provider ollama"
if /i "!AI_PROVIDER!"=="nvidia" set "PROVIDER_ARGS=--provider nvidia-nim"
if /i "!AI_PROVIDER!"=="openai" (
    echo !OPENAI_BASE_URL! | findstr /c:"integrate.api.nvidia.com" >nul && set "PROVIDER_ARGS=--provider nvidia-nim"
)

set "MODEL_ARGS="
if defined OPENAI_MODEL set "MODEL_ARGS=--model !OPENAI_MODEL!"
if defined GEMINI_MODEL set "MODEL_ARGS=--model !GEMINI_MODEL!"
if defined ANTHROPIC_MODEL set "MODEL_ARGS=--model !ANTHROPIC_MODEL!"

set "SETTINGS_ARGS=--setting-sources local"
set "CMD_ARGS=--dangerously-skip-permissions"

if /i "!AI_PROVIDER!"=="ollama" (
    if exist "%DATA_DIR%\ollama\ollama.exe" (
        echo [~] Starting Local Ollama Server...
        set "OLLAMA_MODELS=%DATA_DIR%\ollama\data"
        start "Ollama Portable" /b /min "%DATA_DIR%\ollama\ollama.exe" serve >nul 2>&1
        timeout /t 3 /nobreak >nul
        echo [OK] Ollama running!
        if exist "%USB_ROOT%tools\local-proxy.js" (
            echo [~] Starting local speed proxy...
            powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name = 'node.exe'\" | Where-Object { $_.CommandLine -like '*local-proxy.js*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
            start "LocalProxy" /b /min "%NODE_DIR%\node.exe" "%USB_ROOT%tools\local-proxy.js"
            timeout /t 2 /nobreak >nul
            set "OPENAI_BASE_URL=http://localhost:11435/v1"
            echo [OK] Speed proxy active.
        )
    )
)

pushd "%WORK_DIR%" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to enter working directory: %WORK_DIR%
    pause
    exit /b 1
)

if defined SESSION_ID (
    call "%NODE_DIR%\node.exe" "%OC_BIN%" !SETTINGS_ARGS! !PROVIDER_ARGS! !MODEL_ARGS! !CMD_ARGS! --resume "%SESSION_ID%"
    set "OC_STATUS=!ERRORLEVEL!"
) else (
    call "%NODE_DIR%\node.exe" "%OC_BIN%" !SETTINGS_ARGS! !PROVIDER_ARGS! !MODEL_ARGS! !CMD_ARGS! --continue
    set "OC_STATUS=!ERRORLEVEL!"
    if not "!OC_STATUS!"=="0" (
        echo [WARN] No conversation found to continue. Starting a new session...
        call "%NODE_DIR%\node.exe" "%OC_BIN%" !SETTINGS_ARGS! !PROVIDER_ARGS! !MODEL_ARGS! !CMD_ARGS!
        set "OC_STATUS=!ERRORLEVEL!"
    )
)

popd

if /i "!AI_PROVIDER!"=="ollama" (
    if exist "%DATA_DIR%\ollama\ollama.exe" (
        echo.
        echo [~] Stopping Local Ollama Server...
        taskkill /f /im ollama.exe >nul 2>&1
        powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name = 'node.exe'\" | Where-Object { $_.CommandLine -like '*local-proxy.js*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
    )
)

pause
exit /b %OC_STATUS%
