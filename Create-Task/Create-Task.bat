@echo off

:: Run as Admin
FSUTIL DIRTY query %SYSTEMDRIVE% >nul || (
    PowerShell.exe "Start-Process -FilePath %COMSPEC% -Args '/C CHDIR /D %CD% & "%0"' -Verb RunAs"
    EXIT
)

:: Get Parent Directory Path
for %%? in ("%~dp0..") do set parent=%%~f?
echo %parent%\ is your parent directory

%windir%\System32\schtasks.exe /create /tn "AutoPowerPlanSwitcher" /ru %USERNAME% /RL HIGHEST /Sc ONLOGON /tr "'%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe' -noprofile -nologo -windowstyle hidden -ExecutionPolicy Bypass \"%parent%\power-manager.ps1\"

:: English Systems
FOR /F %%I IN ('%windir%\System32\schtasks.exe /QUERY /FO LIST /TN "AutoPowerPlanSwitcher" ^| FIND /C "Running"') DO (
    IF %%I == 0 (SET STATUS=Running) Else (SET Status=Ready)
    ECHO %%I
)
ECHO %STATUS%

if "%STATUS%" == "Ready" (
    "%windir%\System32\schtasks.exe" /run /tn "AutoPowerPlanSwitcher"
)

:: German Systems
FOR /F %%I IN ('%windir%\System32\schtasks.exe /QUERY /FO LIST /TN "AutoPowerPlanSwitcher" ^| FIND /C "Bereit"') DO (
    IF %%I == 0 (SET STATUS=Running) Else (SET Status=Ready)
    ECHO %%I
)
ECHO %STATUS%

if "%STATUS%" == "Ready" (
    "%windir%\System32\schtasks.exe" /run /tn "AutoPowerPlanSwitcher"
)

pause
