[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$UpstreamDir,

    [Parameter(Mandatory = $true)]
    [string]$UpstreamRepository,

    [Parameter(Mandatory = $true)]
    [string]$UpstreamRef,

    [Parameter(Mandatory = $true)]
    [string]$UpstreamVersion,

    [Parameter(Mandatory = $true)]
    [int]$PostgreSqlMajor,

    [Parameter(Mandatory = $true)]
    [string]$PostgreSqlMinor,

    [string]$DistDir = "dist"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$manifest = Get-Content (Join-Path $PSScriptRoot "../../config/extension.json") -Raw | ConvertFrom-Json
$upstreamSha = (& git -C $UpstreamDir rev-parse HEAD).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or
    $upstreamSha -cne ([string]$manifest.upstream.commit).ToLowerInvariant() -or
    $UpstreamRepository -cne [string]$manifest.upstream.repository -or
    $UpstreamRef -cne [string]$manifest.upstream.ref -or
    $UpstreamVersion -cne [string]$manifest.upstream.version -or
    $PostgreSqlMajor -notin @(15, 16, 17, 18, 19)) {
    throw "Package identity mismatch for pg_wait_sampling."
}

$assetName = "pg_wait_sampling-$UpstreamRef-pg$PostgreSqlMajor-windows-x64"
$stage = Join-Path $DistDir $assetName
$zipPath = Join-Path $DistDir "$assetName.zip"

if (Test-Path $stage) {
    Remove-Item $stage -Recurse -Force
}
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

New-Item -ItemType Directory -Force -Path (Join-Path $stage "share\extension") | Out-Null

Copy-Item (Join-Path $UpstreamDir "pg_wait_sampling.control") (Join-Path $stage "share\extension\pg_wait_sampling.control") -Force
$sqlFiles = @(Get-ChildItem -Path $UpstreamDir -File -Filter "pg_wait_sampling--*.sql")
if ($sqlFiles.Count -ne 2) {
    throw "Expected 2 pg_wait_sampling SQL files, found $($sqlFiles.Count)."
}
foreach ($sqlFile in $sqlFiles) {
    Copy-Item $sqlFile.FullName (Join-Path $stage "share\extension\$($sqlFile.Name)") -Force
}

New-Item -ItemType Directory -Force -Path (Join-Path $stage "lib") | Out-Null
Copy-Item (Join-Path $UpstreamDir "pg_wait_sampling.dll") (Join-Path $stage "lib/pg_wait_sampling.dll") -Force
# Windows Git checkout may use CRLF; distribute the exact pinned LICENSE blob.
& git -C $UpstreamDir -c core.autocrlf=false checkout-index --force -- LICENSE
if ($LASTEXITCODE -ne 0) { throw "Could not restore exact upstream LICENSE bytes." }
Copy-Item (Join-Path $UpstreamDir "LICENSE") (Join-Path $stage "LICENSE") -Force
if (Test-Path (Join-Path $UpstreamDir "README.md")) {
    Copy-Item (Join-Path $UpstreamDir "README.md") (Join-Path $stage "UPSTREAM-README.md") -Force
}

@"
pg_wait_sampling Windows package
==============================

Upstream repository: $UpstreamRepository
Upstream ref:        $UpstreamRef
Upstream commit:     $upstreamSha
pg_wait_sampling version: $UpstreamVersion
SQL default_version: 1.1
PostgreSQL major:    $PostgreSqlMajor
PostgreSQL tested:   $PostgreSqlMinor
Architecture:        Windows x64
Compiler:            MSVC x64
License:             PostgreSQL; see LICENSE

This is an unofficial pgextwin Windows package built from the official pg_wait_sampling source.
Requires shared_preload_libraries=pg_wait_sampling.
"@ | Set-Content -Path (Join-Path $stage "PACKAGE-INFO.txt") -Encoding utf8

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -CompressionLevel Optimal
if (-not (Test-Path $zipPath)) {
    throw "Expected package was not produced: $zipPath"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $zipPath).Path)
try {
    $items = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    foreach ($required in @("lib/pg_wait_sampling.dll", "share/extension/pg_wait_sampling.control", "LICENSE", "PACKAGE-INFO.txt")) {
        if ($items -cnotcontains $required) {
            throw "ZIP entry missing: $required"
        }
    }
}
finally {
    $archive.Dispose()
}
