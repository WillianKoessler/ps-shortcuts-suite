@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "ROOT_DIR=%~d0"

call :setup_logging "WARN"

call :debug "ROOT - Figuring if is transient"
echo %cmdcmdline% | find /i " /c " >nul
if not errorlevel 1 (
    call :debug "ROOT - Is transient"
    set "TRANSIENT=1"
) else (
    call :debug "ROOT - Not transient"
    set "TRANSIENT=0"
)

set "CMD=%~1"
call :info "ROOT - Command: %CMD%"
if /I "%CMD%"=="new"       goto :new
if /I "%CMD%"=="list"      goto :list
if /I "%CMD%"=="install"   goto :install
if /I "%CMD%"=="uninstall" goto :uninstall
if /I "%CMD%"=="help"      goto :help
if not defined CMD         goto :help

echo Unknown command: %CMD%
goto :help

:new
    if "%~2"=="" (
        call :debug "NEW - No source was passed to create shortcut."
        goto :new_usage
    )

    set "SRC=%~f2"
    if not exist "%SRC%" (
        call :error "NEW - Source not found: '%SRC%'"
        exit /b 1
    )
    call :info "NEW - Source: '%SRC%'"

    set "NAME=%~3"
    if not defined NAME set "NAME=%~n2"
    call :info "NEW - Target name: '%NAME%'"

    set "LINKDIR=%~dp0"
    call :info "NEW - Link directory: '%LINKDIR%'"

    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$src=$env:SRC; $dir=$env:LINKDIR; $name=$env:NAME; $link=Join-Path $dir ($name + '.lnk');" ^
    "$ws=New-Object -ComObject WScript.Shell;" ^
    "$sc=$ws.CreateShortcut($link);" ^
    "$sc.TargetPath=$src;" ^
    "$sc.WorkingDirectory=(Split-Path -Parent $src);" ^
    "$sc.Save()"

    IF %ERRORLEVEL% EQU 0 exit /b 0
    set err=%ERRORLEVEL%

    call :error "NEW - Failed to create new shortcut."
    exit /b %err%

:new_usage
    call :debug "NEW_USAGE - Displaying usage information"
    echo Usage: %~n0 new ^<source^> [name]
    exit /b 1

:list
    set "LINKDIR=%~dp0"
    call :info "LIST - Listing existing commands in directory: '%LINKDIR%'"

    powershell -NoProfile -Command ^
    "$items = Get-ChildItem -LiteralPath $env:LINKDIR -File | Where-Object { $_.Name -notlike '%~nx0' -and -not $_.Name.StartsWith('_') } | Sort-Object Name;" ^
    "if([Console]::IsOutputRedirected){ $items | ForEach-Object { $_.Name } } else { if($items.Count -gt 0) { $items | Format-Wide Name -AutoSize; } else { Write-Host 'No Shortcuts Available' } }"
    if "%TRANSIENT%"=="1" (
        call :info "LIST - Transient console. Pausing execution..."
        pause
    )
    exit /b %errorlevel%

:install
    set "TARGET=%~f2"
    if "%TARGET%"=="" (
        call :warn "No directory was provided."
        set "TARGET=%ROOT_DIR%\shortcuts"
    )

    echo Installing system at "%TARGET%"
    
    if exist "%TARGET%" (
        call :error "'%TARGET%' already exists. Choose a new empty directory."
        exit /b 1
    )
    call :info "INSTALL - Target: '%TARGET%'"

    mkdir "%TARGET%" >nul 2>&1
    if errorlevel 1 (
        call :warn "INSTALL - Unable to create directory. Elevating priviledges"
        call :elevate
        exit /b
    )

    call :debug "INSTALL - Copying '%~nx0' to target"
    copy "%~f0" "%TARGET%\%~nx0" >nul
    if errorlevel 1 (
        call :error "INSTALL - Could not copy '%~nx0' into '%TARGET%'."
        exit /b 1
    )

    call :info "INSTALL - Adding target to environment PATH"
    call :add_user_path "%TARGET%"
    if errorlevel 1 (
        call :error "INSTALL - Unable to add target to environment PATH."
        exit /b 1
    )

    call :debug "INSTALL - Displaying success information"
    echo Installed to "%TARGET%".
    echo New Run dialogs should pick it up after the environment refresh.
    exit /b 0

:install_usage
    call :debug "INSTALL_USAGE - Displaying usage information"
    echo Usage: %~n0 install ^<directory^>
    exit /b 1

:uninstall
    echo Uninstalling %~n0

    set "SELF_DIR=%~dp0"
    call :info "UNINSTALL - Installation directory: '%SELF_DIR%'"

    call :remove_user_path "%SELF_DIR%"
    if errorlevel 1 (
        call :error "UNINSTALL - Unable to uninstall script from '%SELF_DIR%'"
        exit /b 1
    )

    echo Removed "%SELF_DIR%" from PATH.
    echo The folder was not deleted.
    exit /b 0

:add_user_path
    set "ADD_DIR=%~f1"

    call :info "ADD_USER_PATH - Adding directory '%ADD_DIR%' to user PATH"

    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$dir = [IO.Path]::GetFullPath($env:ADD_DIR).TrimEnd('\');" ^
    "$current = [Environment]::GetEnvironmentVariable('Path','User');" ^
    "$parts = @(); if ($current) { $parts = $current -split ';' | Where-Object { $_ -and $_.Trim() } }" ^
    "$exists = $false; foreach($p in $parts){ if(([IO.Path]::GetFullPath($p).TrimEnd('\')) -ieq $dir){ $exists = $true; break } }" ^
    "if(-not $exists){ $new = ($parts + $dir) -join ';'; [Environment]::SetEnvironmentVariable('Path',$new,'User') }"

    exit /b %errorlevel%

:remove_user_path
    set "DEL_DIR=%~f1"

    call :info "REMOVE_USER_PATH - Removing directory '%DEL_DIR%' from user PATH"

    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$dir = [IO.Path]::GetFullPath($env:DEL_DIR).TrimEnd('\');" ^
    "$current = [Environment]::GetEnvironmentVariable('Path','User');" ^
    "if([string]::IsNullOrWhiteSpace($current)){ exit 0 }" ^
    "$parts = $current -split ';' | Where-Object { $_ -and $_.Trim() };" ^
    "$filtered = foreach($p in $parts){ if(([IO.Path]::GetFullPath($p).TrimEnd('\')) -ine $dir){ $p } }" ^
    "[Environment]::SetEnvironmentVariable('Path', ($filtered -join ';'), 'User')"

    exit /b %errorlevel%

:elevate
    call :info "ELEVATE - Asking for elevated priviledges."
    set "params=%*"
    call :info "ELEVATE - Parameters: '%params%'"

    set "vbs=%temp%\%~n0_getadmin_%random%%random%.vbs"
    call :info "ELEVATE - Temporary VBS script: '%vbs%'"

    call :debug "ELEVATE - Setting up VBS content."
    > "%vbs%" echo Set UAC = CreateObject("Shell.Application")
    >>"%vbs%" echo UAC.ShellExecute "cmd.exe", "/c ""%~f0"" %params:"=""%", "", "runas", 1
    
    call :info "ELEVATE - Calling temporary VBS script..."
    "%vbs%"

    call :info "ELEVATE - Removing temporary VBS script..."
    del "%vbs%" >nul 2>&1

    exit /b 0

:help
    call :debug "HELP - Displaying help information"
    echo Usage:
    echo   st new ^<source^> [name]    Creates a new link for the suite
    echo   st list                   Lists every link available from this suite
    echo   st install [directory]    Creates the directory and adds to PATH (Optional: [directory])
    echo   st uninstall              Removes the directory from PATH

    if "%TRANSIENT%"=="1" (
        call :debug "Transient console. Pausing execution..."
        pause
    )

    exit /b 1

:setup_logging
    if /I "%~1"=="debug" (
        set LOG_LEVEL=4
    ) else if /I "%~1"=="info" (
        set LOG_LEVEL=3
    ) else if /I "%~1"=="warn" (
        set LOG_LEVEL=2
    ) else if /I "%~1"=="error" (
        set LOG_LEVEL=1
    ) else (
        set LOG_LEVEL=0
    )

    exit /b 1

:log
    if %~1 EQU 1 (
        if %LOG_LEVEL% GEQ 1 (
            echo [ERROR] %~2
        )
    ) else if %~1 EQU 2 (
        if %LOG_LEVEL% GEQ 2 (
            echo [WARNING] %~2
        )
    ) else if %~1 EQU 3 (
        if %LOG_LEVEL% GEQ 3 (
            echo [INFO] %~2
        )
    ) else if %~1 EQU 4 (
        if %LOG_LEVEL% GEQ 4 (
            echo [DEBUG] %~2
        )
    )
    exit /b 1

:debug
    call :log 4 %1
    exit /b 1

:info
    call :log 3 %1
    exit /b 1

:warn
    call :log 2 %1
    exit /b 1

:error
    call :log 1 %1
    exit /b 1

