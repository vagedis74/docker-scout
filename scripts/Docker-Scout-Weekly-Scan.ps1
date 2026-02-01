#Requires -Version 5.1
<#
.SYNOPSIS
    Weekly Docker Scout vulnerability scan for all active images.
.DESCRIPTION
    Scans all images used by running containers plus tagged local images.
    Outputs results to a timestamped report file.
#>

$ErrorActionPreference = 'Continue'
$ReportDir = "$env:USERPROFILE\Documents\docker-scout-reports"
$Timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$ReportFile = Join-Path $ReportDir "scout-scan-$Timestamp.txt"

# Ensure report directory exists
if (-not (Test-Path $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

function Write-Report {
    param([string]$Text)
    $Text | Tee-Object -FilePath $ReportFile -Append
}

Write-Report "============================================"
Write-Report "  Docker Scout Weekly Scan - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Report "============================================"
Write-Report ""

# Collect images to scan: running containers + tagged images
$runningImages = docker ps --format "{{.Image}}" 2>&1 | Sort-Object -Unique
$taggedImages = docker images --format "{{.Repository}}:{{.Tag}}" 2>&1 |
    Where-Object { $_ -notmatch '<none>' } |
    Sort-Object -Unique

$allImages = ($runningImages + $taggedImages) | Sort-Object -Unique

Write-Report "Images to scan: $($allImages.Count)"
Write-Report "---"
$allImages | ForEach-Object { Write-Report "  $_" }
Write-Report ""

$summary = @()

foreach ($image in $allImages) {
    Write-Report "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Report "Scanning: $image"
    Write-Report "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    $scanOutput = docker scout quickview $image 2>&1 | Out-String
    Write-Report $scanOutput

    # Extract vulnerability counts from quickview output
    $critical = if ($scanOutput -match '(\d+)C') { $matches[1] } else { '0' }
    $high = if ($scanOutput -match '(\d+)H') { $matches[1] } else { '0' }
    $medium = if ($scanOutput -match '(\d+)M') { $matches[1] } else { '0' }
    $low = if ($scanOutput -match '(\d+)L') { $matches[1] } else { '0' }

    $summary += [PSCustomObject]@{
        Image    = $image
        Critical = $critical
        High     = $high
        Medium   = $medium
        Low      = $low
    }

    Write-Report ""
}

Write-Report "============================================"
Write-Report "  SUMMARY"
Write-Report "============================================"
$summaryTable = $summary | Format-Table -AutoSize | Out-String
Write-Report $summaryTable

# Check for critical/high and flag them
$hasIssues = $summary | Where-Object { [int]$_.Critical -gt 0 -or [int]$_.High -gt 0 }
if ($hasIssues) {
    Write-Report "WARNING: $($hasIssues.Count) image(s) have critical or high vulnerabilities."
    Write-Report "Run 'docker scout cves <image> --only-fixed --only-severity critical,high' for fix details."
} else {
    Write-Report "All images are free of critical and high vulnerabilities."
}

Write-Report ""
Write-Report "Full report saved to: $ReportFile"

# Update Scout environment records for pushed images
Write-Report ""
Write-Report "Updating Docker Scout environment records..."
$envMappings = @{
    'production' = @(
        'vagedis74/vagedis:claude-proxy-latest',
        'vagedis74/vagedis:mcp-desktop-commander',
        'vagedis74/vagedis:mcp-github-chat'
    )
}
foreach ($env in $envMappings.Keys) {
    foreach ($img in $envMappings[$env]) {
        $result = docker scout environment $env $img --org vagedis74 --platform linux/amd64 2>&1 | Out-String
        Write-Report "  [$env] $img - recorded"
    }
}

# Clean up reports older than 90 days
Get-ChildItem -Path $ReportDir -Filter "scout-scan-*.txt" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) } |
    Remove-Item -Force

Write-Report "Reports older than 90 days have been cleaned up."
