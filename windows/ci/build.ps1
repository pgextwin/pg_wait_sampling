[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PgRoot,
    [Parameter(Mandatory = $true)][string]$UpstreamDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = (Resolve-Path $UpstreamDir).Path
$manifest = Get-Content (Join-Path $PSScriptRoot '../../config/extension.json') -Raw | ConvertFrom-Json
$actual = (& git -C $source rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actual -cne $manifest.upstream.commit) {
    throw 'Upstream identity mismatch'
}

$vswhere = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'MSVC discovery tool missing' }
$vs = @(& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath |
    Select-Object -First 1)
if (-not $vs -or -not $vs[0].Trim()) { throw 'MSVC x64 toolchain missing' }
$devCmd = Join-Path $vs[0].Trim() 'Common7/Tools/VsDevCmd.bat'
if (-not (Test-Path $devCmd)) { throw 'VsDevCmd unavailable' }

# The PostgreSQL module macros and collector declaration export their entry points.
# The upstream _PG_init definition has no explicit export.
@(
    'LIBRARY pg_wait_sampling'
    'EXPORTS'
    '    _PG_init'
    '    pg_wait_sampling_get_current'
    '    pg_wait_sampling_get_history'
    '    pg_wait_sampling_get_profile'
    '    pg_wait_sampling_reset_profile'
) |
    Set-Content -Path (Join-Path $source 'pg_wait_sampling.def') -Encoding ascii

$buildCmd = Join-Path $env:RUNNER_TEMP 'pg-wait-sampling-build.cmd'
@"
@echo off
call "$devCmd" -arch=x64 -host_arch=x64 >nul
if errorlevel 1 exit /b %errorlevel%
pushd "$source"
if errorlevel 1 exit /b %errorlevel%
cl /nologo /O2 /MD /DWIN32 /DWIN32_NO_STATUS /D_CRT_SECURE_NO_WARNINGS ^
 /I"$PgRoot\include\server\port\win32_msvc" ^
 /I"$PgRoot\include\server\port\win32" ^
 /I"$PgRoot\include\server" /I"$PgRoot\include" ^
 /c pg_wait_sampling.c collector.c
if errorlevel 1 exit /b %errorlevel%
link /nologo /DLL /OUT:pg_wait_sampling.dll /DEF:pg_wait_sampling.def ^
 pg_wait_sampling.obj collector.obj "$PgRoot\lib\postgres.lib" "$PgRoot\lib\libintl.lib"
if errorlevel 1 exit /b %errorlevel%
dumpbin /nologo /exports pg_wait_sampling.dll
"@ | Set-Content -Path $buildCmd -Encoding ascii

$buildLog = @(& cmd.exe /d /c $buildCmd 2>&1)
$buildLog | ForEach-Object { Write-Host "$_" }
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $source 'pg_wait_sampling.dll'))) {
    throw 'Pinned native MSVC DLL compile/link failed'
}
