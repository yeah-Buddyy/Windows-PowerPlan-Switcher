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

$NvidiaSMI = [System.IO.File]::Exists("$env:WinDir\System32\nvidia-smi.exe")
$SMICommand = "& '" + "$env:WinDir\System32" + "\nvidia-smi.exe`' --query-gpu=utilization.gpu --format=csv,noheader,nounits"
if ([System.IO.File]::Exists("$PSScriptRoot\gamingprocess.txt")) {
    if ((Get-Item "$PSScriptRoot\gamingprocess.txt").Length -gt 0) {
        $process_list = Get-Content -Path "$PSScriptRoot\gamingprocess.txt"
    }
}

# Define the write-results function
function write-results {
    Param (
        [int]$CPULoad,
        [int]$GPULoad,
        [string]$LoadMessage,
        [string]$PlanMessage
    )

    Write-Host "GPU Usage:" $GPULoad "%" -ForegroundColor Yellow
    Write-Host "CPU Usage:" $CPULoad "%" -ForegroundColor Yellow
    Write-Host $LoadMessage -ForegroundColor Yellow
    Write-Host $PlanMessage -ForegroundColor Green
}

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
    [System.Console]::Clear()

    # Keep Gaming Powerplan according to $KeepGamingPowerPlan
    if ($KeepGamingPowerPlan) {
        Write-Host "Keep Powerplan" -ForegroundColor Yellow
        Write-Host "Set Powerplan to Gaming ID $GamingPowerPlanID" -ForegroundColor Green
        change-powerplan $GamingPowerPlanID
        Continue
    }
    if ($process_list) {
        foreach ($myprocess in $process_list) {
            $this_process = $myprocess.ToLower()
            if($this_process -like '*.exe') {
                $this_process = $this_process.replace('.exe','')
            }
            $process_exists = Get-Process -ErrorAction 'SilentlyContinue' -Name $this_process
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
    }

    # Start the GPU load job
    $gpuJob = Start-Job -ScriptBlock {
        param ($NvidiaSMI, $SMICommand)
        try {
            if ($NvidiaSMI) {
                # Run Nvidia SMI command
                $gpuLoad = Invoke-Expression -command $SMICommand
            } else {
                # Fallback method to get GPU load using Get-Counter
                $gpuLoad = (((Get-Counter "\GPU Engine(*engtype_3D)\Utilization Percentage").CounterSamples | where CookedValue).CookedValue | measure -sum).sum
            }
            # Return GPU load
            return [math]::Round($gpuLoad)
        } catch {
            Write-Error "Error retrieving GPU load: $_"
            return "Error retrieving GPU load"
        }
    } -ArgumentList $NvidiaSMI, $SMICommand

    # Start the CPU load job
    $cpuJob = Start-Job -ScriptBlock {
        try {
            # https://social.technet.microsoft.com/Forums/en-US/f89267b7-5069-4e57-9970-af80dcc58f8f/get-cpu-usage-faster-with-net-within-powershell-then-using-wmi-or
            $counters = New-Object -TypeName System.Diagnostics.PerformanceCounter
            $counters.CategoryName='Processor'
            $counters.CounterName='% Processor Time'
            $counters.InstanceName='_Total'

            # First call to get an initial value
            $null = $counters.NextValue()
            # To correctly retrieve the current CPU usage percentage using PerformanceCounter, you typically need to call NextValue() twice, with a short delay in between, to get a meaningful result:
            Start-Sleep -Milliseconds 500
            # Second call to get the actual CPU load
            $CPULoad = $counters.NextValue()
            $CPULoad = [math]::Round($CPULoad)

            # Return CPU load
            return $CPULoad
        } catch {
            Write-Error "Error retrieving CPU load: $_"
            return "Error retrieving CPU load"
        }
    }

    try {
        # Wait for both jobs to complete
        Wait-Job -Job $gpuJob, $cpuJob | Out-Null  # Suppress output from Wait-Job

        # Retrieve GPU load result
        $GPULoad = Receive-Job -Job $gpuJob

        # Check if GPU load retrieval was successful
        if ($GPULoad -ne "Error retrieving GPU load") {
            # Display the GPU load
            #Write-Host "GPU Usage: $GPULoad%"
        } else {
            Write-Warning "Failed to retrieve GPU load."
        }

        # Retrieve CPU load result
        $CPULoad = Receive-Job -Job $cpuJob

        # Check if CPU load retrieval was successful
        if ($GPULoad -ne "Error retrieving CPU load") {
            # Display the CPU load
            #Write-Host "CPU Usage: $CPULoad%"
        } else {
            Write-Warning "Failed to retrieve CPU load."
        }

    } finally {
        # Clean up jobs
        Remove-Job -Job $gpuJob, $cpuJob -Force
    }

    Write-Host
    Write-Host "#######################################################"
    # Decide with CPU and GPU load if $KeepGamingPowerPlan is false
    if ($UseIdleLimit) {
        $IdleSeconds = [PInvoke.Win32.UserInput]::IdleTime.TotalSeconds
        Write-Host ('User IdleTime ' + $IdleSeconds) -ForegroundColor Yellow
    }
    if ($CPULoad -le $CPUUsageLimit) {
        if ($GPULoad -le $GPUUsageLimit) {
            write-results -CPULoad $CPULoad -GPULoad $GPULoad -LoadMessage "CPU AND GPU Load is lower than threshold" -PlanMessage "Set Powerplan Idle ID $IdlePowerPlanID"
            change-powerplan $IdlePowerPlanID
            # Check user idle time to set $IdlePowerPlanID
            if (($IdleSeconds -ge $UserIdleLimit) -and ($UseIdleLimit)) {
                write-results -CPULoad $CPULoad -GPULoad $GPULoad -LoadMessage "User is idling" -PlanMessage "Set Powerplan to Idle ID $IdlePowerPlanID"
                change-powerplan $IdlePowerPlanID
            }
        }
    }
    elseif ($CPULoad -ge $CPUUsageLimit) {
        if ($GPULoad -ge $GPUUsageLimit) {
            write-results -CPULoad $CPULoad -GPULoad $GPULoad -LoadMessage "CPU AND GPU Load is higher than CPU AND GPU threshold" -PlanMessage "Set Powerplan to Gaming ID $GamingPowerPlanID"
            change-powerplan $GamingPowerPlanID
        }
        elseif (($CPULoad -ge $CPUUsageLimit) -or ($GPULoad -ge $GPUUsageLimit)) {
            write-results -CPULoad $CPULoad -GPULoad $GPULoad -LoadMessage "CPU OR GPU Load is higher than CPU OR GPU threshold" -PlanMessage "Set Powerplan to Gaming ID $GamingPowerPlanID"
            change-powerplan $GamingPowerPlanID
        }
    }
    Write-Host "Sleeping..."
    Write-Host "#######################################################"
}
