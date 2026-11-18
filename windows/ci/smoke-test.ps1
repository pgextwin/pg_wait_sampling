[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PgRoot,
    [Parameter(Mandatory = $true)][int]$PgPort,
    [Parameter(Mandatory = $true)][int]$PostgreSqlMajor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$data = Join-Path $env:RUNNER_TEMP "pg_wait_sampling-$PostgreSqlMajor-data"
$log = Join-Path $env:RUNNER_TEMP "pg_wait_sampling-$PostgreSqlMajor.log"

& "$PgRoot/bin/initdb.exe" -D $data -U postgres -A trust --encoding=UTF8 --no-locale
if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }

$started = $false
try {
    & "$PgRoot/bin/pg_ctl.exe" -D $data -l $log -o "-p $PgPort -c listen_addresses=127.0.0.1 -c shared_preload_libraries=pg_wait_sampling" start
    if ($LASTEXITCODE -ne 0) { throw 'Preload startup failed' }
    $started = $true

    & "$PgRoot/bin/psql.exe" -h 127.0.0.1 -p $PgPort -U postgres -d postgres -X -v ON_ERROR_STOP=1 `
        -c 'SET statement_timeout = 30000' `
        -c 'CREATE EXTENSION pg_wait_sampling' `
        -c "SELECT extversion FROM pg_extension WHERE extname = 'pg_wait_sampling'" `
        -c 'SELECT pg_sleep(0.25)' `
        -c 'SELECT count(*) AS current_waits FROM pg_wait_sampling_get_current(pg_backend_pid())' `
        -c 'SELECT count(*) AS history_samples FROM pg_wait_sampling_history' `
        -c 'SELECT count(*) AS profile_rows FROM pg_wait_sampling_profile'
    if ($LASTEXITCODE -ne 0) { throw 'pg_wait_sampling SQL smoke failed' }
    Write-Host "PASS: pg_wait_sampling PG$PostgreSqlMajor functional smoke test"
} finally {
    if (Test-Path $log) { Get-Content $log -Tail 80 }
    if ($started) { & "$PgRoot/bin/pg_ctl.exe" -D $data -m immediate stop }
}
