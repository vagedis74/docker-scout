#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Checks for ghost Twingate adapters and removes them.
.DESCRIPTION
    Finds all Twingate PnP devices, identifies ghost adapters (Error, Degraded,
    or Unknown status, or duplicates beyond the first OK adapter), and removes them.
#>

[CmdletBinding()]
param(
    [switch]$DryRun
)

$allTwingate = Get-PnpDevice | Where-Object {
    $_.FriendlyName -like '*Twingate*' -and $_.Class -eq 'Net'
}

if (-not $allTwingate) {
    Write-Host "No Twingate network adapters found." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($allTwingate.Count) Twingate network adapter(s):" -ForegroundColor Cyan
$allTwingate | Format-Table Status, Class, FriendlyName, InstanceId -AutoSize | Out-Host

$active = $allTwingate | Where-Object { $_.Status -eq 'OK' } | Select-Object -First 1
$ghosts = $allTwingate | Where-Object { $_.InstanceId -ne $active.InstanceId }

if (-not $ghosts) {
    Write-Host "No ghost adapters found. Only one active Twingate adapter present." -ForegroundColor Green
    exit 0
}

Write-Host "$($ghosts.Count) ghost adapter(s) detected:" -ForegroundColor Yellow
$ghosts | Format-Table Status, Class, FriendlyName, InstanceId -AutoSize | Out-Host

foreach ($ghost in $ghosts) {
    # Safety check: only remove Twingate network adapters
    if ($ghost.FriendlyName -notlike '*Twingate*' -or $ghost.Class -ne 'Net') {
        Write-Host "SKIPPED (not a Twingate network adapter): $($ghost.FriendlyName)" -ForegroundColor Red
        continue
    }

    if ($DryRun) {
        Write-Host "[DRY RUN] Would remove: $($ghost.FriendlyName) ($($ghost.InstanceId))" -ForegroundColor DarkYellow
    } else {
        Write-Host "Disabling: $($ghost.FriendlyName) ($($ghost.InstanceId))..." -ForegroundColor Yellow
        $ghost | Disable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue

        Write-Host "Removing: $($ghost.FriendlyName) ($($ghost.InstanceId))..." -ForegroundColor Yellow
        pnputil /remove-device $ghost.InstanceId

        if ($LASTEXITCODE -eq 0) {
            Write-Host "Removed successfully." -ForegroundColor Green
        } else {
            Write-Host "Failed to remove $($ghost.InstanceId)." -ForegroundColor Red
        }
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
