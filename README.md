# Windows-PowerPlan-Switcher
Automatically change the powerplan according to CPU and GPU load, idle time, processes or manual override

The original source is from [ComputerBase](https://www.computerbase.de/forum/threads/skript-windows-powerplan-switcher-for-nvidia.1830609/).

# How to use
Just adjust the parameters (explained below) and you are good to go.  
`power-manager.ps1` is the main script. Use the Create-Task.bat, to setup a task in the Taskplaner.

## Config
### $CPUUsageLimit
CPU Load, which needs to fall bellow this value to set energy saving or go higher to set gaming plan.

### $GPUUsageLimit
GPU Load, which needs to fall bellow this value to set energy saving or go higher to set gaming plan.

### $UseIdleLimit [$true or $false]
Enable or disable to check for user idle time.

### $UserIdleLimit
Float, seconds. Amount of time the user should be idling to set powersaving plan.

### $GamingPowerPlanID
Use `powercfg /L` to get the IDs of the power plans.  
This powerplan is set if CPU load and GPU load is higher than `$CPUUsageLimit` and `$GPUUsageLimit`, mouse and keyboard inputs are not older than `$UserIdleLimit`, at least one process from `gameprocess.txt` is running or "True" is written in `keepplan.txt` (read below).

### $IdlePowerPlanID
This powerplan is set, if none of the above apply.

### $KeepGamingPowerPlan
* `true`  
Will keep the gaming-plan until you run the script again with `false`
* `false`  
Will disable the fixed powerplan and make it CPU load, GPU load and idle time dependant again

## Programs to keep gaming-plan
Enter the processes in `gamingprocess.txt`. If one of these processes are running, gaming-plan will be kept.
