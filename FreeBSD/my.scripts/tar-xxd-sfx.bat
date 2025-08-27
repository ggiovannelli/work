@echo off
REM tar-xxd-sfx.bat - Super simple version

if "%~1"=="" echo Usage: %0 [-u^|-w^|-d] files... & exit /b

REM Check if xxd is available
where xxd >nul 2>&1
if errorlevel 1 (
    echo Error: xxd not found in PATH
    echo.
    echo Please install xxd from one of these sources:
    echo - Standalone xxd: https://github.com/ckormanyos/xxd/releases
    echo - UnxUtils: http://unxutils.sourceforge.net/
    echo.
    exit /b 1
)

REM Default values
set T=windows
set F=%*

REM Check for options and adjust file list
if "%~1"=="-u" (
    set T=unix
    set F=%~2 %~3 %~4 %~5 %~6 %~7 %~8 %~9
)
if "%~1"=="-w" (
    set T=windows
    set F=%~2 %~3 %~4 %~5 %~6 %~7 %~8 %~9
)
if "%~1"=="-d" (
    set T=dual
    set F=%~2 %~3 %~4 %~5 %~6 %~7 %~8 %~9
)

set G=%TEMP%\a%RANDOM%.gz
set H=%TEMP%\a%RANDOM%.hex

echo # %date% %time% %COMPUTERNAME% %F%
echo.

tar -czf "%G%" %F% 2>nul
xxd -p -c 9999 "%G%" > "%H%"

if not "%T%"=="windows" (
    echo # For Unix/Linux:
    echo ^( xxd -p -r ^| tar -zxvf - ^) ^<^<EOF
    xxd -p -c 56 "%G%"
    echo EOF
)

if "%T%"=="dual" echo.

if not "%T%"=="unix" (
    echo # For Windows with xxd:
    for /f "delims=" %%i in ('type "%H%"') do (
        echo echo %%i ^| xxd -p -r ^| tar -zxvf -
    )
)

del "%G%" "%H%" 2>nul
