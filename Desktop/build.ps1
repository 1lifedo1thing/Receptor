$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot 'build/desktop'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The .NET Framework 4.x C# compiler is required.' }
$applicationSource = Join-Path $PSScriptRoot 'Program.cs'
$serverSource = Join-Path $PSScriptRoot 'CompanionServer.cs'
$settingsSource = Join-Path $PSScriptRoot 'ConnectionSettings.cs'
$executablePath = Join-Path $outputDirectory 'ReceptorDesktop.exe'
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /debug- /warnaserror+ /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Xml.dll /reference:System.Security.dll "/out:$executablePath" (Join-Path $PSScriptRoot '*.cs')
if ($LASTEXITCODE -ne 0) { throw 'Desktop build failed.' }
Write-Output "Built $outputDirectory/ReceptorDesktop.exe"
