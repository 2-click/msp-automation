# Author: J. Runge
# This script can be used to run ping diagnostics
param(
    # Adds a switch for continuous execution
    [switch]$install_as_task,
    [switch]$started_from_taskscheduler,
    [string]$target_list_string
)
# Specify the output file path
$LOG_FILE = "C:\ping_results.txt"


# Require version 7 of powershell
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "This script requires PowerShell 7 or newer. Download here:" -ForegroundColor Red
    Write-Host "https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.4#msi" -ForegroundColor Cyan
    Write-Host "Tip: To start a script with the new powershell (version 7) use pwsh.exe instead of powershell.exe" -ForegroundColor Green
    return
}

if ($null -eq $target_list_string) {
    Write-Host "Please specify a target list." -ForegroundColor Red
    Write-Host "Example: pwsh.exe -File $PSCommandPath -target_list_string `"8.8.8.8,google.com`"" -ForegroundColor Cyan
    return
} else {
    $target_list = $target_list_string -split ","
}

# Install as task
if ($install_as_task) {
    # Check if the current user is in the Administrators role
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not ($isAdmin)) {
        Write-Host "You need to run this script as Administrator if you want to set it up as a task" -ForegroundColor Red
        return
    }

    # Check if script is in a save location
    if ($PSCommandPath.StartsWith("C:\Users")) {
        Write-Host "You need to run this script from a safe and persistent location (For example C:\ping_script.ps1)." -ForegroundColor Red
        return
    } 

    $targetsAsString = $target_list -join ','

    Write-Host "Installing script (pwsh.exe -File $PSCommandPath -target_list_string `"$targetsAsString`") as task..."

    $Action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-File `"$PSCommandPath`" -target_list_string `"$targetsAsString`" -started_from_taskscheduler"
    $Trigger = New-ScheduledTaskTrigger -AtStartup
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName "Ping diagnostics script" -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings
    Write-Host "Script has been installed as a task." -ForegroundColor Green
    Write-Host "Make sure your execution policy allows the execution of this script." -ForegroundColor Yellow
    Write-Host "To test if your execution policy is configured correctly, open up cmd.exe and execute the following command:" -ForegroundColor Yellow
    Write-Host "pwsh.exe -File `"$PSCommandPath`"" -ForegroundColor Cyan

    return
}

if (-not ($started_from_taskscheduler)) {
    Write-Host "Did you know that you can start this script automatically everytime the system boots?" -ForegroundColor Green
    Write-Host "Just run the following command:" -ForegroundColor Green
    Write-Host "pwsh.exe -File $PSCommandPath -install_as_task" -ForegroundColor Cyan
}


# Infinite loop to run continuously
while ($true) {
    Write-Host "Starting diagnostics for $($target_list.count) targets..."
    Write-Host "Log will be saved in C:\"
    $target_list | ForEach-Object -Parallel {
        # Get the current timestamp
        $timestamp = Get-Date -Format "dd.MM.yyyy - HH:mm:ss"

        # Ping the target
        $pingResult = Test-Connection -ComputerName $_ -Count 1 -ErrorAction SilentlyContinue -TimeoutSeconds 1 

        # Prepare the output string
        if ($pingResult) {
            $result = "$timestamp - Ping good - $_ responded in $($pingResult.Latency)ms"
        } else {
            $result = "$timestamp - Ping fail - $_ did not respond in a reasonable time"
        }

        Write-Host $result
        Add-Content -Path $using:LOG_FILE -Value $result 
    } -ThrottleLimit 10

    Start-Sleep -Seconds 3
}
