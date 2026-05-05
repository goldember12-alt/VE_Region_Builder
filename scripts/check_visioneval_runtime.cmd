@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "REPO_ROOT=%%~fI"

if defined VE_RSCRIPT (
  set "RSCRIPT=%VE_RSCRIPT%"
) else (
  set "RSCRIPT=Rscript"
)

echo Using Rscript: %RSCRIPT%
"%RSCRIPT%" "%SCRIPT_DIR%check_visioneval_runtime.R"
exit /b %ERRORLEVEL%
