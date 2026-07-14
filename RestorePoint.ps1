param(
    [string]$Description = "Restorepoint",
    [int]$KeepLast = 5,
    [char]$Drive = 'C'
)

# Admin check
$admin = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host "ERROR: Run as Administrator!" -ForegroundColor Red
    exit 1
}

Write-Host "Admin rights confirmed." -ForegroundColor Green

# Log setup
$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logPath = Join-Path $env:TEMP "$scriptName-$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Message"
    [IO.File]::AppendAllText($logPath, "$line`r`n", [Text.Encoding]::UTF8)
    Write-Host $line -ForegroundColor $Color
}

Write-Log "Script started. Description='$Description', KeepLast=$KeepLast, Drive=$Drive" "Cyan"

# 1. Count existing shadow copies (by counting GUIDs)
Write-Log "Counting existing shadow copies on drive $Drive..." "Yellow"
$forArg = "/for=${Drive}:"
$shadowsRaw = vssadmin list shadows $forArg 2>&1

$shadowCount = 0
foreach ($line in $shadowsRaw) {
    if ($line -match '\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}') {
        $shadowCount++
    }
}
Write-Log "Total shadow copies found: $shadowCount" "Gray"

# 2. Purge extra copies, leaving exactly $KeepLast
if ($shadowCount -le $KeepLast) {
    Write-Log "No purge needed (count <= KeepLast)." "Cyan"
} else {
    $toDelete = $shadowCount - $KeepLast
    Write-Log "Will delete $toDelete oldest shadow copies to leave exactly $KeepLast." "Yellow"

    $deleted = 0
    $errors = 0

    for ($i = 1; $i -le $toDelete; $i++) {
        Write-Log "Deleting oldest shadow copy (attempt $i of $toDelete)..." "Yellow"
        $delResult = vssadmin delete shadows /for=${Drive}: /oldest /quiet 2>&1
        $success = ($delResult -match 'successfully deleted') -or ($delResult -match 'was deleted')

        if ($success) {
            Write-Log "Deleted oldest shadow copy successfully (attempt $i)." "Green"
            $deleted++
        } else {
            # Если нет явной ошибки — считаем OK (vssadmin бывает молча удаляет)
            if ($delResult -notmatch 'error|invalid|fail') {
                Write-Log "Shadow copy deletion result (no explicit error): attempt $i" "Yellow"
                $deleted++
            } else {
                Write-Log "Explicit error on attempt ${i}: ${delResult}" "Red"
                $errors++
            }
        }
    }
    Write-Log "Purge finished. Deleted=$deleted, Errors=$errors" "Yellow"
}

# 3. Create restore point (ONLY AFTER purge)
Write-Log "Creating restore point after purge..." "Yellow"
try {
    Checkpoint-Computer -Description $Description -RestorePointType APPLICATION_INSTALL -ErrorAction Stop
    Write-Log "Restore point created successfully." "Green"
} catch {
    Write-Log "Failed to create restore point. Error: $_" "Red"
    Write-Host "WARNING: Restore point creation failed." -ForegroundColor Yellow
}

Write-Log "Log file: $logPath" "Cyan"
Write-Host "Done. Check log in: $logPath" -ForegroundColor Cyan
