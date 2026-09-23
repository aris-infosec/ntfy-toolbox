<#
.SYNOPSIS
    ntfy sender with live system-info triggers (Windows).

.DESCRIPTION
    Dependencies: none extra for disk/ram/uptime (built into Windows/PowerShell).
    `temp` needs LibreHardwareMonitor running with its web server enabled (localhost:8085).

.EXAMPLE
    .\ntfy_send.ps1
    .\ntfy_send.ps1 -Topic mytopic -Trigger disk
    .\ntfy_send.ps1 -Topic mytopic -Message "custom text"
#>

param(
    [string]$Topic = $env:NTFY_TOPIC,
    [ValidateSet("temp","disk","ram","uptime","done","error","build","backup")]
    [string]$Trigger,
    [string]$Message,
    [string]$Click
)

$NtfyServer = if ($env:NTFY_SERVER) { $env:NTFY_SERVER } else { "https://ntfy.sh" }
$MaxRetries = 3
$RetryDelaySeconds = 2

function Send-Ntfy {
    param($Topic, $Message, $Title = "", $Priority = "default", $Tags = "", $ClickUrl = "")

    $headers = @{ "Title" = $Title; "Priority" = $Priority; "Tags" = $Tags }
    if ($ClickUrl) { $headers["Click"] = $ClickUrl }

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            Invoke-RestMethod -Uri "$NtfyServer/$Topic" -Method Post -Body $Message -Headers $headers | Out-Null
            Write-Host "✅ Sent to '$Topic':"
            Write-Host $Message
            return $true
        } catch {
            Write-Host "⚠️  Attempt $attempt failed ($($_.Exception.Message)), retrying in ${RetryDelaySeconds}s..."
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
    Write-Host "❌ Failed to send after $MaxRetries attempts."
    return $false
}

function Get-DiskInfo {
    $d = Get-PSDrive C
    "Used: {0:N1} GB / {1:N1} GB free" -f ($d.Used/1GB), ($d.Free/1GB)
}

function Get-RamInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $used = $os.TotalVisibleMemorySize - $os.FreePhysicalMemory
    "RAM: {0:N1} GB / {1:N1} GB used" -f ($used/1MB), ($os.TotalVisibleMemorySize/1MB)
}

function Get-UptimeInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $uptime = (Get-Date) - $os.LastBootUpTime
    "Uptime: {0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
}

function Get-TempInfo {
    try {
        Invoke-RestMethod -Uri "http://localhost:8085/data.json" -TimeoutSec 2 | Out-Null
        "See LibreHardwareMonitor web UI at localhost:8085 for full sensor tree"
    } catch {
        "Unavailable - install/run LibreHardwareMonitor with its web server enabled (localhost:8085)"
    }
}

$Triggers = @{
    "temp"    = @{ Title = "🌡️ Temperature"; Priority = "default"; Tags = "thermometer"; Fn = { Get-TempInfo } }
    "disk"    = @{ Title = "💽 Disk Space";   Priority = "default"; Tags = "floppy_disk"; Fn = { Get-DiskInfo } }
    "ram"     = @{ Title = "🧠 RAM Usage";    Priority = "default"; Tags = "brain";       Fn = { Get-RamInfo } }
    "uptime"  = @{ Title = "⏱️ Uptime";       Priority = "low";     Tags = "clock3";      Fn = { Get-UptimeInfo } }
    "done"    = @{ Title = "✅ Done";         Priority = "default"; Tags = "white_check_mark"; Text = "Task finished successfully." }
    "error"   = @{ Title = "🚨 Error";        Priority = "urgent";  Tags = "rotating_light";   Text = "Something went wrong!" }
    "build"   = @{ Title = "🛠️ Build";        Priority = "default"; Tags = "hammer_and_wrench";Text = "Build finished." }
    "backup"  = @{ Title = "💾 Backup";       Priority = "low";     Tags = "floppy_disk";      Text = "Backup completed." }
}

if (-not $Topic) {
    $Topic = Read-Host "Channel (topic) name"
    if (-not $Topic) { Write-Host "No topic given, aborting."; exit 1 }
}

if (-not $Trigger -and -not $Message) {
    $Message = Read-Host "Message (or trigger: $($Triggers.Keys -join ', '))"
    if ($Triggers.ContainsKey($Message.ToLower())) {
        $Trigger = $Message.ToLower()
        $Message = $null
    }
}

if ($Trigger) {
    $preset = $Triggers[$Trigger]
    $text = if ($preset.Fn) { & $preset.Fn } else { $preset.Text }
    Send-Ntfy -Topic $Topic -Message $text -Title $preset.Title -Priority $preset.Priority -Tags $preset.Tags -ClickUrl $Click
} else {
    Send-Ntfy -Topic $Topic -Message $Message -ClickUrl $Click
}
