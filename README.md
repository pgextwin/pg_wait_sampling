# pg_wait_sampling on Windows

This pgextwin pilot tests upstream pg_wait_sampling v1.1.11 at commit
`7e3a5fc937393596c0a51c5881dd63d7208408d1` on PostgreSQL 15–18 for Windows x64.
The PR workflow builds with MSVC against the standard PostgreSQL Windows
installation. Upstream documents missing PostgreSQL exports as a Windows
build limitation.

The smoke test starts a disposable PostgreSQL server with
`shared_preload_libraries=pg_wait_sampling`, runs `CREATE EXTENSION pg_wait_sampling`,
and queries the current waits, history, and profile. The extension SQL
version is 1.1.

The upstream PostgreSQL License is included in [LICENSE](LICENSE).
