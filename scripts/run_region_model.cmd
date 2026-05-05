@echo off
setlocal

if "%~1"=="" (
  echo Usage: scripts\run_region_model.cmd ^<region_name^>
  exit /b 1
)

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "REPO_ROOT=%%~fI"

if defined VE_RSCRIPT (
  set "RSCRIPT=%VE_RSCRIPT%"
) else (
  set "RSCRIPT=Rscript"
)

echo Using Rscript: %RSCRIPT%
"%RSCRIPT%" "%SCRIPT_DIR%run_region_model.R" "%~1"
exit /b %ERRORLEVEL%
