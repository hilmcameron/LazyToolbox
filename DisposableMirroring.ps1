#Requires -Version 3.0
<#
.SYNOPSIS
    One-way folder sync using Robocopy. Mirrors source to destination.
.DESCRIPTION
    PowerShell wrapper for Robocopy /MIR sync. Includes parameters, logging, and log rotation.
    This version configures Robocopy for verbose logging within its log file.
    *** WARNING: /MIR DELETES FILES/FOLDERS IN DESTINATION NOT IN SOURCE. ***
.PARAMETER SourcePath Source directory (UNC recommended). Mandatory.
.PARAMETER DestinationPath Destination directory. Content can be DELETED/overwritten. Mandatory.
.PARAMETER LogBasePath Base directory for logs. Subfolder created per sync pair. Mandatory.
.PARAMETER RobocopyThreads [Optional] Robocopy /MT value. Default 8.
.PARAMETER MaxLogFilesToKeep [Optional] Number of logs to keep per pair. Default 5.
.EXAMPLE
    .\ServerSync.ps1 -SourcePath "\\ServerA\Share" -DestinationPath "D:\Mirror" -LogBasePath "C:\Logs"
.EXAMPLE
    .\ServerSync.ps1 -SourcePath "\\SrvA\Data" -DestinationPath "\\SrvB\DataMirror" -LogBasePath "C:\TaskLogs" -RobocopyThreads 16 -MaxLogFilesToKeep 10
.NOTES
    Version: 1.4 | Requires Robocopy in PATH. Run task as privileged account with network/NTFS permissions (or -NoProfile Context).
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$DestinationPath,
    [Parameter(Mandatory=$true)][string]$LogBasePath,
    [Parameter(Mandatory=$false)][ValidateRange(1,128)][int]$RobocopyThreads = 8,
    [Parameter(Mandatory=$false)][ValidateRange(1,100)][int]$MaxLogFilesToKeep = 5
)

$ErrorActionPreference = "Stop" # Exit script on terminating errors unless caught
$startTime = Get-Date
$robocopyExe = "robocopy.exe"
$logPrefix = "SyncLog_"

# Generate Log Paths (Error handling via $ErrorActionPreference='Stop')
$safeSourceLeaf = (Split-Path -Path $SourcePath -Leaf) -replace '[\\/:*?"<>| ]', '_'
$safeDestLeaf = (Split-Path -Path $DestinationPath -Leaf) -replace '[\\/:*?"<>| ]', '_'
$logDirectory = Join-Path -Path $LogBasePath -ChildPath "Sync_${safeSourceLeaf}_to_${safeDestLeaf}"
$logFile = Join-Path -Path $logDirectory -ChildPath "$($logPrefix)$($startTime.ToString('yyyyMMdd_HHmmss')).log"

if (-not (Test-Path -Path $logDirectory -PathType Container)) {
    try {
        $null = New-Item -Path $logDirectory -ItemType Directory -Force
        Write-Host "$(Get-Date -Format 'u') [INFO] Created log directory: $logDirectory" # Initial log message to console only
    } catch {
        Write-Error "$(Get-Date -Format 'u') [FATAL] Failed to create log directory '$logDirectory'. Error: $($_.Exception.Message)"
        exit 99
    }
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timeStamp [$Level] $Message"
    # Attempt Append (less critical failure than initial creation)
    try { Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue } catch {}
    # Output critical messages to host/stderr
    if ($Level -match "WARN|ERROR|FATAL") { Write-Host $logEntry -ForegroundColor @{"WARN"="Yellow"; "ERROR"="Red"; "FATAL"="Magenta"}[$Level] }
    elseif ($Level -eq "DEBUG") { Write-Host $logEntry -ForegroundColor Cyan }
    # else { Write-Host $logEntry } # Optional: Output INFO to host too
}

Write-Log -Message "===== Script Started ====="
Write-Log -Message "Source      : $SourcePath"
Write-Log -Message "Destination : $DestinationPath"
Write-Log -Message "Log File    : $logFile" -Level "DEBUG"

$robocopyArgs = @(
    $SourcePath, $DestinationPath, # Source and Destination
    # Core Options
    "/MIR",                         # Mirror Mode (/E + /PURGE) - DELETES extra files!
    "/SEC",                         # Copy NTFS Security (/COPY:DATS)
    "/DCOPY:T",                     # Copy Directory Timestamps
    "/ZB",                          # Use Restartable & Backup modes
    # Performance & Retry
    "/R:2",                         # Retries on failed copies
    "/W:5",                         # Wait time between retries
    "/MT:$RobocopyThreads",         # Multi-threaded copying
    # Filtering
    "/XJD",                         # Exclude Junction points for Directories
    "/XJF",                         # Exclude Junction points for Files
    # Logging Control - Configured for Detail
    "/NP",                          # No Progress percentage (still useful to keep logs cleaner from % updates)
    "/UNICODE",                     # Output log as Unicode text
    "/LOG:$logFile"                 # Log output to file (OVERWRITE current file)
    # Removed: /NFL, /NDL, /NC, /NJH, /NJS to get detailed logs
    # Consider adding /TS (Include source file Timestamps) and /FP (Include Full Path names) if needed
    # Optional: /TEE                # Output to console AND log file (for debugging)
)

# Execute Robocopy
$exitCode = 0
Write-Log -Message "Starting Robocopy (Detailed Logging Enabled)..."
try {
    & $robocopyExe $robocopyArgs
    $exitCode = $LASTEXITCODE
    # Note: Robocopy itself has now written detailed info to $logFile
    Write-Log -Message "Robocopy process finished. Exit Code: $exitCode" # Add script context after Robocopy output
} catch {
    $exitCode = 97 # Script error trying to run Robocopy
    Write-Log -Message "FATAL: Failed to execute Robocopy. Error: $($_.Exception.Message)" -Level "FATAL"
}

$finalStatus = "Unknown Status"
$finalLogLevel = "INFO"
switch ($exitCode) {
    { $_ -ge 0 -and $_ -le 7 } { $finalStatus = "Success or Info (RC=$exitCode): Robocopy completed. Check log details above if RC > 1." }
    { $_ -ge 8 -and $_ -le 15} { $finalStatus = "Warning (RC=$exitCode): Robocopy completed but some files failed to copy. Check log details above."; $finalLogLevel = "WARN" }
    { $_ -ge 16 }              { $finalStatus = "Error (RC=$exitCode): Serious Robocopy error occurred. Check log details above."; $finalLogLevel = "ERROR" }
    97                         { $finalStatus = "FATAL: PowerShell failed to start Robocopy."; $finalLogLevel = "FATAL" }
    99                         { $finalStatus = "FATAL: Failed to create log directory."; $finalLogLevel = "FATAL" }
    default                    { $finalStatus = "ERROR: Unexpected Exit Code ($exitCode)."; $finalLogLevel = "ERROR" }
}
Write-Log -Message "Final Script Status: $finalStatus" -Level $finalLogLevel

Write-Log -Message "Performing log rotation (Keeping $MaxLogFilesToKeep)..." -Level "DEBUG"
try {
    $oldLogs = Get-ChildItem -Path $logDirectory -Filter "$($LogPrefix)*.log" -File | Sort-Object Name -Descending | Select-Object -Skip $MaxLogFilesToKeep
    if ($oldLogs) {
        Write-Log -Message "Deleting $($oldLogs.Count) old log(s)." -Level "WARN"
        $oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue # Don't let rotation failure stop script exit
    }
} catch { Write-Log -Message "Error during log rotation: $($_.Exception.Message)" -Level "ERROR" }

$duration = (Get-Date) - $startTime
Write-Log -Message "Script execution duration: $($duration.ToString())" -Level "DEBUG"
Write-Log -Message "===== Script Finished ====="
exit $exitCode
