$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$output=Join-Path $taskRoot 'build/desktop/RemoteTestHost.exe'
& $compiler /nologo /target:exe /warnaserror+ /reference:System.Security.dll "/out:$output" (Join-Path $PSScriptRoot 'remote_host.cs') (Join-Path $taskRoot 'Desktop/CompanionServer.cs') (Join-Path $taskRoot 'Desktop/ConnectionSettings.cs') (Join-Path $taskRoot 'Desktop/RemoteProtocol.cs') (Join-Path $taskRoot 'Desktop/RemoteBroker.cs')
if($LASTEXITCODE -ne 0){throw 'Remote test-host compilation failed.'}
