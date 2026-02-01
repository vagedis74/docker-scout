#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Finds and removes ghost Twingate network interfaces.
.DESCRIPTION
    Searches for Twingate network adapters that are in a non-functioning state
    (disconnected, not present, or errored) and offers to remove them after
    user confirmation.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-GhostTwingateInterfaces {
    $ghostInterfaces = @()

    # Method 1: PnP devices matching Twingate that are not OK
    Write-Host "Searching for ghost Twingate PnP devices..." -ForegroundColor Cyan
    try {
        $pnpDevices = Get-PnpDevice -FriendlyName "*Twingate*" -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -ne 'OK' }
        foreach ($dev in $pnpDevices) {
            $ghostInterfaces += [PSCustomObject]@{
                Name         = $dev.FriendlyName
                InstanceId   = $dev.InstanceId
                Status       = $dev.Status
                Class        = $dev.Class
                Source       = 'PnpDevice'
            }
        }
    } catch {
        Write-Warning "Could not query PnP devices: $_"
    }

    # Method 2: Hidden network adapters matching Twingate that are disabled/disconnected
    Write-Host "Searching for ghost Twingate network adapters..." -ForegroundColor Cyan
    try {
        $netAdapters = Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
            Where-Object {
                $_.InterfaceDescription -like "*Twingate*" -or $_.Name -like "*Twingate*"
            } |
            Where-Object {
                $_.Status -notin @('Up')
            }
        foreach ($adapter in $netAdapters) {
            # Avoid duplicates if already found via PnP
            $alreadyFound = $ghostInterfaces | Where-Object {
                $_.InstanceId -eq $adapter.PnPDeviceID
            }
            if (-not $alreadyFound) {
                $ghostInterfaces += [PSCustomObject]@{
                    Name         = "$($adapter.Name) ($($adapter.InterfaceDescription))"
                    InstanceId   = $adapter.PnPDeviceID
                    Status       = $adapter.Status
                    Class        = 'Net'
                    Source       = 'NetAdapter'
                }
            }
        }
    } catch {
        Write-Warning "Could not query network adapters: $_"
    }

    # Method 3: Check for leftover Twingate entries via devcon-style WMI query
    Write-Host "Searching for non-present Twingate devices via WMI..." -ForegroundColor Cyan
    try {
        $wmiDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.Name -like "*Twingate*" -or $_.Description -like "*Twingate*") -and
                $_.Status -ne 'OK'
            }
        foreach ($dev in $wmiDevices) {
            $alreadyFound = $ghostInterfaces | Where-Object {
                $_.InstanceId -eq $dev.DeviceID
            }
            if (-not $alreadyFound) {
                $ghostInterfaces += [PSCustomObject]@{
                    Name         = $dev.Name
                    InstanceId   = $dev.DeviceID
                    Status       = $dev.Status
                    Class        = $dev.PNPClass
                    Source       = 'WMI'
                }
            }
        }
    } catch {
        Write-Warning "Could not query WMI: $_"
    }

    return $ghostInterfaces
}

function Remove-GhostInterface {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Interface
    )

    Write-Host "  Removing: $($Interface.Name) [$($Interface.InstanceId)]" -ForegroundColor Yellow

    # Try pnputil first (preferred on modern Windows)
    try {
        $result = & pnputil /remove-device "$($Interface.InstanceId)" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    Removed successfully via pnputil." -ForegroundColor Green
            return $true
        }
    } catch {}

    # Fallback: disable and remove via PnP cmdlet
    try {
        $device = Get-PnpDevice -InstanceId $Interface.InstanceId -ErrorAction Stop
        Disable-PnpDevice -InstanceId $Interface.InstanceId -Confirm:$false -ErrorAction Stop
        & pnputil /remove-device "$($Interface.InstanceId)" 2>&1 | Out-Null
        Write-Host "    Removed successfully via PnP disable + remove." -ForegroundColor Green
        return $true
    } catch {
        Write-Warning "    Failed to remove $($Interface.Name): $_"
        return $false
    }
}

# --- Main ---
Write-Host ""
Write-Host "=== Ghost Twingate Interface Cleanup ===" -ForegroundColor White
Write-Host ""

$ghosts = Get-GhostTwingateInterfaces

if ($ghosts.Count -eq 0) {
    Write-Host ""
    Write-Host "No ghost Twingate interfaces found. System is clean." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "Found $($ghosts.Count) ghost Twingate interface(s):" -ForegroundColor Yellow
Write-Host ""
$ghosts | Format-Table -Property Name, Status, Class, InstanceId -AutoSize -Wrap
Write-Host ""

$response = Read-Host "Do you want to remove these ghost interfaces? (y/N)"
if ($response -notin @('y', 'Y', 'yes', 'Yes', 'YES')) {
    Write-Host "Aborted. No changes were made." -ForegroundColor Cyan
    exit 0
}

Write-Host ""
Write-Host "Removing ghost interfaces..." -ForegroundColor Cyan
$removed = 0
$failed = 0

foreach ($ghost in $ghosts) {
    if (Remove-GhostInterface -Interface $ghost) {
        $removed++
    } else {
        $failed++
    }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor White
Write-Host "  Removed: $removed" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "  Failed:  $failed" -ForegroundColor Red
}
Write-Host ""
