# Author: Dolphin Whisperer
# Created: 2025-09-05
# Description: This script unmounts - waits 10 seconds - then remounts all currently mounted SMB-shares
#
# "May you live in interesting times."
#
#
# --- CONFIG ----------------------------------
$emailFrom = "NIAIDRMLUnixAlerts@niaid.nih.gov"
$emailTo   = "jeremy.bell@nih.gov"
$smtpServer = "post.niaid.nih.gov"
$subject = "SMB Share Remount Failure Alert"
# ---------------------------------------------

# step 1: get currently mounted shares
Write-Host "Checking currently mounted SMB shares..." -ForegroundColor Cyan
$shares = net use | Select-String "OK" | ForEach-Object {
    $parts = ($_ -split '\s{2,}') -ne ""
    [PSCustomObject]@{
        LocalDrive = $parts[1]
        RemotePath = $parts[2]
    }
}

if ($shares.Count -eq 0) {
    Write-Host "No SMB shares are currently mounted." -ForegroundColor Yellow
    exit
}

# step 2: unmount all shares
Write-Host "Unmounting SMB shares..." -ForegroundColor Cyan
foreach ($share in $shares) {
    Write-Host "→ Unmounting $($share.LocalDrive) -> $($share.RemotePath)"
    $result = cmd /c "net use $($share.LocalDrive) /delete /y" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   [FAILED] Could not unmount $($share.LocalDrive)" -ForegroundColor Red
        Write-Host $result
    }
}

# step 3: wait 10 seconds
Write-Host "Waiting 10 seconds..." -ForegroundColor Cyan
Start-Sleep -Seconds 10

# step 4: remount all shares with persistence
Write-Host "Remounting SMB shares..." -ForegroundColor Cyan
$failedShares = @()

foreach ($share in $shares) {
    Write-Host "→ Remounting $($share.LocalDrive) -> $($share.RemotePath) (persistent)"
    $result = cmd /c "net use $($share.LocalDrive) $($share.RemotePath) /persistent:yes" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   [FAILED] Could not remount $($share.LocalDrive)" -ForegroundColor Red
        Write-Host $result
        $failedShares += "$($share.LocalDrive) -> $($share.RemotePath)`nError: $result"
    } else {
        Write-Host "   [OK] Mounted successfully" -ForegroundColor Green
    }
}

# step 5: notify if failures
if ($failedShares.Count -gt 0) {
    $body = @"
The following SMB shares failed to remount:

$($failedShares -join "`n")

Please check the system.
"@
    Write-Host "Sending failure notification email to $emailTo..." -ForegroundColor Yellow
    try {
        Send-MailMessage -From $emailFrom -To $emailTo -Subject $subject -Body $body -SmtpServer $smtpServer
        Write-Host "Notification email sent." -ForegroundColor Green
    } catch {
        Write-Host "   [ERROR] Could not send email: $_" -ForegroundColor Red
    }
} else {
    Write-Host "All SMB shares remounted successfully. No email sent." -ForegroundColor Green
}

Write-Host "Done." -ForegroundColor Cyan
