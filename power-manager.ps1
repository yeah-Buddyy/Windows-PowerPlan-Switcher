# Performance counter gpu usage is not accurate see here https://forums.developer.nvidia.com/t/how-to-evaluate-gpu-utilization-usage-on-windows/245451/5

## Power Plans IDs (Use Without #)
# 381b4222-f694-41f0-9685-ff5bb260df2e = Balanced
# 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c = High performance
# a1841308-3541-4fab-bc81-f71556f20b4a = Power saver
# e9a42b02-d5df-448d-aa00-03f14749eb61 = Ultimate Power

## To Fill
# If true, it checks if a fullscreen D3D application is running; if so, it switches to the gaming power plan; else it uses the GPU and CPU usage limit method
$detectD3DFullScreen = $true
$GPUUsageLimit = 25
$CPUUsageLimit = 25
# If true, it will switch to Idle Power Plan if there is no user input for 300.0 (5 minutes).
$UseIdleLimit = $false
$UserIdleLimit = 300.0 # 5 minutes
# Force keep Gaming Power Plan
$KeepGamingPowerPlan = $false
$CheckEverySeconds = 20
# This will try to detect and, if found, use the Ultimate Windows Power Plan guid instead of the $GamingPowerPlanID variable
# You need to add it if you have not already done so. powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
$detectAndUseUltimatePowerPlan = $false
# Your Guid to your Gaming Power Plan. Find with command powercfg /list
$GamingPowerPlanID = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
# Default Balanced Profile
$IdlePowerPlanID = "381b4222-f694-41f0-9685-ff5bb260df2e"

# So autostart won't be too slow
Start-Sleep -Seconds 20

if ($detectAndUseUltimatePowerPlan) {
    # get ultimate power plan guid
    $powercfgList = powercfg.exe /list
    $powerPlan = @()

    foreach ($line in $powercfgList) {
        # extract guid manually to avoid lang issues
        if ($line -match ':') {
            $parse = $line -split ':'
            if ($parse -imatch "Ultimat") {
                $index = $parse[1].Trim().indexof('(')
                $guid = $parse[1].Trim().Substring(0, $index)
                $guid = $guid.Trim()
                $powerPlan += $guid
            }
        }
    }
    if ($powerPlan.Count -eq 1) {
        # Use the Ultimate Power Plan Guid instead of the GamingPowerPlanID variable.
        $GamingPowerPlanID = $powerPlan
    } elseif ($powerPlan.Count -gt 1) {
        Write-Host "You have more than one power plan with Ultimat in the name, make sure there is only one with that name."
        Pause
        exit
    } else {
        Write-Host "No Power Plan found that includes Ultimat in its name"
        Pause
        exit
    }
}

if ($GamingPowerPlanID -eq "") {
    Write-Host "Please specify a Gaming Power Plan Guid"
    Pause
    exit
}

if ($IdlePowerPlanID -eq "") {
    Write-Host "Please specify a Idle Power Plan Guid"
    Pause
    exit
}

$powercfgList = powercfg.exe /list
$powerPlanGaming = @()
$powerPlanIdle = @()

foreach ($line in $powercfgList) {
    # extract guid manually to avoid lang issues
    if ($line -match ':') {
        $parse = $line -split ':'
        if ($parse -imatch "$GamingPowerPlanID") {
            $index = $parse[1].Trim().indexof('(')
            $guid = $parse[1].Trim().Substring(0, $index)
            $guid = $guid.Trim()
            if ($guid -eq $GamingPowerPlanID) {
                $powerPlanGaming += $guid
            }
        }
        if ($parse -imatch "$IdlePowerPlanID") {
            $index = $parse[1].Trim().indexof('(')
            $guid = $parse[1].Trim().Substring(0, $index)
            $guid = $guid.Trim()
            if ($guid -eq $IdlePowerPlanID) {
                $powerPlanIdle += $guid
            }
        }
    }
}
if ($powerPlanGaming.Count -ne 1) {
    Write-Host "Your Gaming Power Plan Guid does not exist"
    Pause
    exit
}
if ($powerPlanIdle.Count -ne 1) {
    Write-Host "Your Idle Power Plan Guid does not exist"
    Pause
    exit
}

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

     # Check user idle time to set $IdlePowerPlanID
    if ($UseIdleLimit) {
        $IdleSeconds = [PInvoke.Win32.UserInput]::IdleTime.TotalSeconds
        Write-Host ('User IdleTime ' + $IdleSeconds) -ForegroundColor Yellow
    }

    if ($UseIdleLimit) {
        if ($IdleSeconds -ge $UserIdleLimit) {
            Write-Host "User is idling, Set Powerplan to Idle ID $IdlePowerPlanID"
            change-powerplan $IdlePowerPlanID
            continue
        }
    }

    if ($detectD3DFullScreen) {
        $detectD3DFullScreenJob = Start-Job -ScriptBlock {
            Add-Type -TypeDefinition @"
            using System;
            using System.Runtime.InteropServices;
        
            public enum QUERY_USER_NOTIFICATION_STATE {
                QUNS_NOT_PRESENT = 1,
                QUNS_BUSY = 2,
                QUNS_RUNNING_D3D_FULL_SCREEN = 3,
                QUNS_PRESENTATION_MODE = 4,
                QUNS_ACCEPTS_NOTIFICATIONS = 5,
                QUNS_QUIET_TIME = 6
            };
        
            public class UserWindows {
                [DllImport("shell32.dll")]
                public static extern int SHQueryUserNotificationState(out QUERY_USER_NOTIFICATION_STATE pquns);
            }
"@
    
            function Get-UserNotificationState {
                # Initialize variables
                $state = [QUERY_USER_NOTIFICATION_STATE]::QUNS_NOT_PRESENT
                $hresult = [UserWindows]::SHQueryUserNotificationState([ref]$state)
        
                if ($hresult -ge 0) {
                    # Map the enum values (integers) to user-friendly descriptions
                    switch ([int]$state) {
                        1 { $description = "Not Present" }
                        2 { $description = "Busy" }
                        3 { $description = "Running D3D Full Screen" }
                        4 { $description = "Presentation Mode" }
                        5 { $description = "Accepts Notifications" }
                        6 { $description = "Quiet Time" }
                        default { $description = "Unknown State" }
                    }
        
                    # Return a formatted output
                    Write-Host "User Notification State: $description"
                    return @{
                        'State' = $state
                        'Description' = $description
                        'HRESULT' = $hresult
                    }
                }
                else {
                    # Handle errors when HRESULT is less than 0
                    Write-Host "Failed to query user notification state. HRESULT: $hresult" -ForegroundColor Red
                    return @{
                        'State' = $null
                        'Description' = "Error"
                        'HRESULT' = $hresult
                    }
                }
            }
            Get-UserNotificationState
        }

        try {
            Wait-Job -Job $detectD3DFullScreenJob | Out-Null
            $jobResult = Receive-Job -Job $detectD3DFullScreenJob
            $jobResult | Out-Null
            Write-Host "State: $($jobResult.State), Description: $($jobResult.Description), HRESULT: $($jobResult.HRESULT)"

            if ($($jobResult.Description) -eq "Running D3D Full Screen") {
                Write-Host "FullScreen D3D application detected, Powerplan set to Gaming ID $GamingPowerPlanID"
                change-powerplan $GamingPowerPlanID
                continue
            } elseif ($($jobResult.Description) -eq "Not Present" -or $($jobResult.Description) -eq "Busy" -or $($jobResult.Description) -eq "Presentation Mode" -or $($jobResult.Description) -eq "Accepts Notifications" -or $($jobResult.Description) -eq "Quiet Time") {
                Write-Host "No FullScreen D3D application detected, continue checking CPU and GPU load"
                # change-powerplan $IdlePowerPlanID
                # continue
            } elseif ($($jobResult.Description) -eq "Unknown State") {
                Write-Host "Unknown state, continue checking CPU and GPU load"
            } else {
                Write-Warning "Could not detect D3D FullScreen application, continue checking CPU and GPU load"
            }
        } finally {
            Remove-Job -Job $detectD3DFullScreenJob -Force
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
                $gpuLoad = (((Get-Counter "\GPU Engine(*engtype_3D)\Utilization Percentage").CounterSamples | Where-Object CookedValue).CookedValue | Measure-Object -sum).sum
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
            Start-Sleep -Seconds 1
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
        if ($CPULoad -ne "Error retrieving CPU load") {
            # Display the CPU load
            #Write-Host "CPU Usage: $CPULoad%"
        } else {
            Write-Warning "Failed to retrieve CPU load."
        }

    } finally {
        # Clean up jobs
        Remove-Job -Job $gpuJob, $cpuJob -Force
    }

    # Decide with CPU and GPU load

    if ($CPULoad -le $CPUUsageLimit) {
        if ($GPULoad -le $GPUUsageLimit) {
            write-results -CPULoad $CPULoad -GPULoad $GPULoad -LoadMessage "CPU AND GPU Load is lower than threshold" -PlanMessage "Set Powerplan Idle ID $IdlePowerPlanID"
            change-powerplan $IdlePowerPlanID
            continue
        }
    }

    if ($CPULoad -ge $CPUUsageLimit) {
        if ($GPULoad -ge $GPUUsageLimit) {
            write-results -CPULoad $CPULoad -GPULoad $GPULoad -LoadMessage "CPU AND GPU Load is higher than CPU AND GPU threshold" -PlanMessage "Set Powerplan to Gaming ID $GamingPowerPlanID"
            change-powerplan $GamingPowerPlanID
            continue
        }
    }

    if ($CPULoad -ge $CPUUsageLimit) {
        write-results -CPULoad $CPULoad -GPULoad $GPULoad -LoadMessage "CPU Load is higher than CPU threshold" -PlanMessage "Set Powerplan to Gaming ID $GamingPowerPlanID"
        change-powerplan $GamingPowerPlanID
        continue
    }

    if ($GPULoad -ge $GPUUsageLimit) {
        write-results -CPULoad $CPULoad -GPULoad $GPULoad -LoadMessage "GPU Load is higher than GPU threshold" -PlanMessage "Set Powerplan to Gaming ID $GamingPowerPlanID"
        change-powerplan $GamingPowerPlanID
        continue
    }
}
