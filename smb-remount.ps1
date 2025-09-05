#!/bin/bash
# Author: Dolphin Whisperer
# Created: 2025-09-05
# Description: This script unmounts - waits 10 seconds - then remounts all currently mounted SMB-shares
#
# "May you live in interesting times."
#
#
# step 1: capture current net use mappings
$shares = net use | Select-String "OK" | ForEach-Object {
    $parts = ($_ -split '\s{2,}') -ne ""
    [PSCustomObject]@{
        LocalDrive = $parts[1]
        RemotePath = $parts[2]
    }
}

if ($shares.Count -eq 0) {
    Write-Host "No SMB shares are currently mounted."
    exit
}

# step 2: unmount all shares
Write-Host "Unmounting SMB shares..."
foreach ($share in $shares) {
    Write-Host "Unmounting $($share.LocalDrive) -> $($share.RemotePath)"
    cmd /c "net use $($share.LocalDrive) /delete /y" | Out-Null
}

# step 3: wait 10 seconds
Write-Host "Waiting 10 seconds..."
Start-Sleep -Seconds 10

# step 4: remount all shares with persistence
Write-Host "Remounting SMB shares..."
foreach ($share in $shares) {
    Write-Host "Remounting $($share.LocalDrive) -> $($share.RemotePath) (persistent)"
    cmd /c "net use $($share.LocalDrive) $($share.RemotePath) /persistent:yes" | Out-Null
}

Write-Host "Done."
