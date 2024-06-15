# Performance counter gpu usage is not accurate see here https://forums.developer.nvidia.com/t/how-to-evaluate-gpu-utilization-usage-on-windows/245451/5

## Power Plans IDs (Use Without #)
# 381b4222-f694-41f0-9685-ff5bb260df2e = Balanced
# 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c = High performance
# a1841308-3541-4fab-bc81-f71556f20b4a = Power saver

## To Fill
$GPUUsageLimit = 25
$CPUUsageLimit = 25
$UseIdleLimit = $false
$KeepGamingPowerPlan = $false
$UserIdleLimit = 300.0 # 5 minutes
$CheckEverySeconds = 20
$GamingPowerPlanID = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
$IdlePowerPlanID = "381b4222-f694-41f0-9685-ff5bb260df2e"
#$DebugPreference = "Continue"

# https://social.technet.microsoft.com/Forums/en-US/f89267b7-5069-4e57-9970-af80dcc58f8f/get-cpu-usage-faster-with-net-within-powershell-then-using-wmi-or
$counters = New-Object -TypeName System.Diagnostics.PerformanceCounter
$counters.CategoryName='Processor'
$counters.CounterName='% Processor Time'
$counters.InstanceName='_Total'

# So autostart won't be too slow
Start-Sleep -Seconds 20

# https://stackoverflow.com/a/39319540
Add-Type @'
    using System;
    using System.Diagnostics;
    using System.Runtime.InteropServices;
    namespace PInvoke.Win32 {
        public static class UserInput {
            [DllImport("user32.dll", SetLastError=false)]
            private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
            [StructLayout(LayoutKind.Sequential)]
            private struct LASTINPUTINFO {
                public uint cbSize;
                public int dwTime;
            }
            public static DateTime LastInput {
                get {
                    DateTime bootTime = DateTime.UtcNow.AddMilliseconds(-Environment.TickCount);
                    DateTime lastInput = bootTime.AddMilliseconds(LastInputTicks);
                    return lastInput;
                }
            }
            public static TimeSpan IdleTime {
                get {
                    return DateTime.UtcNow.Subtract(LastInput);
                }
            }
            public static int LastInputTicks {
                get {
                    LASTINPUTINFO lii = new LASTINPUTINFO();
                    lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
                    GetLastInputInfo(ref lii);
                    return lii.dwTime;
                }
            }
        }
    }
'@

$DoesNvidiaSMIExists = [System.IO.Directory]::Exists("$env\Windows\System32\nvidia-smi.exe")
$SMICommand = "& '" + "$env\Windows\System32" + "\nvidia-smi.exe`' --query-gpu=utilization.gpu --format=csv,noheader,nounits"
$process_list = Get-Content -Path "$PSScriptRoot\gamingprocess.txt"

function change-powerplan {
    Param ($PowerPlanID)
    if ((powercfg /GetActiveScheme) -notlike ("*" + $PowerPlanID + "*")) {
        powercfg -s $PowerPlanID
        # Disable sleep if GamingPowerPlan, else set to 30 minutes | set monitor sleep to 25 minutes for Gaming, else set to 15 minutes
        if ($PowerPlanID -eq $GamingPowerPlanID) {
            powercfg -change -standby-timeout-ac 0
            powercfg -change -standby-timeout-dc 0
            powercfg -change -monitor-timeout-ac 25
            powercfg -change -monitor-timeout-dc 25
        }
        else {
            powercfg -change -standby-timeout-ac 30
            powercfg -change -standby-timeout-dc 30
            powercfg -change -monitor-timeout-ac 15
            powercfg -change -monitor-timeout-dc 15
        }
        Write-Host "Set Powerplan ID $PowerPlanID" -ForegroundColor Green
    }
}

while ($true){
    Start-Sleep -Seconds $CheckEverySeconds
    cls

    # Keep Gaming Powerplan according to keepplan.txt
    if ($KeepGamingPowerPlan) {
        Write-Host "Keep Powerplan" -ForegroundColor Yellow
        Write-Host "Set Powerplan to Gaming ID $GamingPowerPlanID" -ForegroundColor Green
        change-powerplan $GamingPowerPlanID
        Continue
    }
    foreach ($this_process in $process_list) {
        if($this_process -like '*.exe') {
            $this_process = $this_process.replace('.exe','')
        }
        $process_exists = Get-Process -erroraction 'silentlycontinue' -Name $this_process
        if ($process_exists) {
            Write-Host "$this_process is running" -ForegroundColor Yellow
            Write-Host "Set Powerplan to Gaming ID $GamingPowerPlanID" -ForegroundColor Green
            change-powerplan $GamingPowerPlanID
            break
        }
    }
    if ($process_exists) {
        Write-Host "$this_process is still running" -ForegroundColor Yellow
        continue
    }

    if ($DoesNvidiaSMIExists) {
        [int]$GPULoad = Invoke-Expression -command $SMICommand
    }else {
        # https://superuser.com/a/1632853
        [int]$GPULoad = (((Get-Counter "\GPU Engine(*engtype_3D)\Utilization Percentage").CounterSamples | where CookedValue).CookedValue | measure -sum).sum
    }

    Write-Host
    Write-Host "#######################################################"
    # Write-Host "GPU Usage:" $GPULoad -ForegroundColor Yellow
    # Write-Host "CPU Usage:" $CPULoad -ForegroundColor Yellow

    # Decide with CPU and GPU load if keepplan.txt is false
    $CPULoad = $counters.NextValue()
    $CPULoad = $([math]::Round($CPULoad))
    $IdleSeconds = [PInvoke.Win32.UserInput]::IdleTime.TotalSeconds
    Write-Host ('User IdleTime ' + $IdleSeconds) -ForegroundColor Yellow
    if ($CPULoad -le $CPUUsageLimit) {
        if ($GPULoad -le $GPUUsageLimit) {
            Write-Host "GPU Usage:" $GPULoad -ForegroundColor Yellow
            Write-Host "CPU Usage:" $CPULoad -ForegroundColor Yellow
            Write-Host "CPU AND GPU Load is lower than threshold" -ForegroundColor Yellow
            Write-Host "Set Powerplan Idle ID $IdlePowerPlanID" -ForegroundColor Green
            change-powerplan $IdlePowerPlanID
            # Check user idle time to set $IdlePowerPlanID
            if (($IdleSeconds -ge $UserIdleLimit) -and ($UseIdleLimit)) {
                Write-Host "GPU Usage:" $GPULoad -ForegroundColor Yellow
                Write-Host "CPU Usage:" $CPULoad -ForegroundColor Yellow
                Write-Host "User is idling" -ForegroundColor DarkYellow
                Write-Host "Set Powerplan to Idle ID $IdlePowerPlanID" -ForegroundColor Green
                change-powerplan $IdlePowerPlanID
            }
        }
    }
    elseif ($CPULoad -ge $CPUUsageLimit) {
        if ($GPULoad -ge $GPUUsageLimit) {
            Write-Host "GPU Usage:" $GPULoad -ForegroundColor Yellow
            Write-Host "CPU Usage:" $CPULoad -ForegroundColor Yellow
            Write-Host "CPU AND GPU Load is higher than MaxCPU AND MaxGpu" -ForegroundColor DarkYellow
            Write-Host "Set Powerplan to Gaming ID $GamingPowerPlanID" -ForegroundColor Green
            change-powerplan $GamingPowerPlanID
        }
        elseif (($CPULoad -ge $CPUUsageLimit) -or ($GPULoad -ge $GPUUsageLimit)) {
            Write-Host "GPU Usage:" $GPULoad -ForegroundColor Yellow
            Write-Host "CPU Usage:" $CPULoad -ForegroundColor Yellow
            Write-Host "CPU OR GPU Load is higher than MaxCPU OR MaxGpu" -ForegroundColor DarkYellow
            Write-Host "Set Powerplan to Gaming ID $GamingPowerPlanID" -ForegroundColor Green
            change-powerplan $GamingPowerPlanID
        }
    }
    Write-Host "Sleeping..."
    Write-Host "#######################################################"
}
