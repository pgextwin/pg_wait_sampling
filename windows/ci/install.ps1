[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PgRoot,

    [Parameter(Mandatory = $true)]
    [string]$UpstreamDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$control = Join-Path $UpstreamDir "pg_wait_sampling.control"
$extensionDir = Join-Path $PgRoot "share\extension"

if (-not (Test-Path $control -PathType Leaf)) {
    throw "Required pg_wait_sampling file was not found: $control"
}
if (-not (Test-Path $extensionDir -PathType Container)) {
    throw "PostgreSQL extension directory was not found: $extensionDir"
}

$sqlFiles = @(Get-ChildItem -Path $UpstreamDir -File -Filter "pg_wait_sampling--*.sql")
if ($sqlFiles.Count -ne 2) {
    throw "Expected 2 pg_wait_sampling SQL files, found $($sqlFiles.Count)."
}

Copy-Item $control (Join-Path $extensionDir "pg_wait_sampling.control") -Force
foreach ($sqlFile in $sqlFiles) {
    Copy-Item $sqlFile.FullName (Join-Path $extensionDir $sqlFile.Name) -Force
}

Write-Host "Installed native pg_wait_sampling control and $($sqlFiles.Count) SQL files into $extensionDir"

Copy-Item (Join-Path $UpstreamDir "pg_wait_sampling.dll") (Join-Path $PgRoot "lib/pg_wait_sampling.dll") -Force
