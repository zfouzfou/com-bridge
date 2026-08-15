@echo off
REM COM Bridge -- Windows dependency installer
REM Usage: double-click or run from cmd

setlocal
set DIR=%~dp0
set PYTHON=

echo ============================================
echo   COM Bridge -- Windows Dependency Installer
echo ============================================
echo.

REM ---- Find Python: check real installations, avoid Store stub ----
if exist "%LOCALAPPDATA%\Programs\Python\Python314\python.exe" goto :found314
if exist "%LOCALAPPDATA%\Programs\Python\Python313\python.exe" goto :found313
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" goto :found312
if exist "C:\Program Files\Python314\python.exe" goto :found314
if exist "C:\Program Files\Python313\python.exe" goto :found313
if exist "C:\Program Files\Python312\python.exe" goto :found312
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
echo [Step 1] Installing Python 3...
echo.
echo Downloading Python 3.14 installer...
curl -L -o "%TEMP%\python-3.14-installer.exe" https://www.python.org/ftp/python/3.14.7/python-3.14.7-amd64.exe
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Download failed. Please install manually:
    echo   https://www.python.org/downloads/
    echo.
    echo IMPORTANT: Check "Add Python to PATH" during installation
    goto :eof
)
echo Running installer (please check "Add Python to PATH")...
start /wait "" "%TEMP%\python-3.14-installer.exe"
echo.
echo Close this window and re-run com_bridge_win_server.bat after installation
goto :eof

:havepython
echo [Step 1] Python found: %PYTHON%

echo [Step 2] Installing pyserial...
"%PYTHON%" -m pip install pyserial -q
if %ERRORLEVEL% EQU 0 (
    echo [Step 2] pyserial installed successfully
) else (
    echo [Step 2] WARNING: pyserial install failed, try: pip install pyserial
)

echo.
echo ============================================
echo   Done! Run com_bridge_win_server.bat to launch the bridge
echo ============================================
echo.
pause