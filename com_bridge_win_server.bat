@echo off
REM COM Bridge -- Windows launcher
REM Usage: double-click or drag to cmd window
REM Prerequisites: Python 3 + pyserial (run com_bridge_win_setup.bat)

setlocal
set DIR=%~dp0
set COM_PORT=COM4
set BAUD=115200
set TCP_PORT=12345
set PYTHON=

REM ---- Parse arguments ----
if not "%1"=="" set COM_PORT=%1
if not "%2"=="" set BAUD=%2
if not "%3"=="" set TCP_PORT=%3

REM ---- Find Python: check real installations, avoid Store stub ----
if exist "%LOCALAPPDATA%\Programs\Python\Python314\python.exe" goto :found314
if exist "%LOCALAPPDATA%\Programs\Python\Python313\python.exe" goto :found313
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" goto :found312
if exist "C:\Program Files\Python314\python.exe" goto :found314
if exist "C:\Program Files\Python313\python.exe" goto :found313
goto :trypath

:found314
set PYTHON=%LOCALAPPDATA%\Programs\Python\Python314\python.exe
goto :havepython

:found313
set PYTHON=%LOCALAPPDATA%\Programs\Python\Python313\python.exe
goto :havepython

:found312
set PYTHON=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
goto :havepython

:trypath
REM Try Python launcher (avoids Store stub)
where py >nul 2>nul
if %ERRORLEVEL% EQU 0 goto :usepy

REM Fallback: search PATH but skip WindowsApps
for /f "delims=" %%i in ('where python 2^>nul ^| findstr /v /i windowsapps') do set PYTHON=%%i
if not "%PYTHON%"=="" goto :havepython
for /f "delims=" %%i in ('where python3 2^>nul ^| findstr /v /i windowsapps') do set PYTHON=%%i
if not "%PYTHON%"=="" goto :havepython
goto :nopython

:usepy
for /f "delims=" %%i in ('py -3 -c "import sys;print(sys.executable)" 2^>nul') do set PYTHON=%%i
if "%PYTHON%"=="" goto :nopython
goto :havepython

:nopython
echo [ERROR] Python not found. Run com_bridge_win_setup.bat first
pause
exit /b 1

:havepython
echo [OK] Python: %PYTHON%

REM ---- Check pyserial ----
"%PYTHON%" -c "import serial" 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [INFO] Installing pyserial...
    "%PYTHON%" -m pip install pyserial -q
    if %ERRORLEVEL% NEQ 0 (
        echo [ERROR] pyserial install failed. Run: pip install pyserial
        pause
        exit /b 1
    )
    echo [OK] pyserial installed
)

echo.
echo ============================================
echo   COM Bridge -- Windows
echo   Port: %COM_PORT% @ %BAUD% baud
echo   TCP:  :%TCP_PORT%
echo   Stop: Ctrl+C
echo ============================================
echo.

"%PYTHON%" "%DIR%com_bridge.py" %COM_PORT% %BAUD% %TCP_PORT%

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Bridge exited abnormally. Check:
    echo   - Is %COM_PORT% connected?
    echo   - Is another program using %COM_PORT%?
    echo   - Try different port: %0 COM5 9600 12345
    pause
)