param(
	[string]$CpuHost = "127.0.0.1",
	[string]$AuthServer = "127.0.0.1",
	[string]$User = "glenda",
	[string]$Password = $env:PASS,
	[string]$Exe = (Join-Path $PSScriptRoot "build\msvc\drawterm.exe"),
	[string]$Log = (Join-Path $PSScriptRoot "build\msvc\drawterm-test.log"),
	[int]$TimeoutSeconds = 60,
	[switch]$NoVerbose
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Exe)) {
	throw "drawterm.exe was not found at '$Exe'. Build it first with: nmake /f NMakefile.msvc"
}

if ([string]::IsNullOrEmpty($Password)) {
	$Password = "cleartext"
}

$logDir = Split-Path -Parent $Log
if (-not [string]::IsNullOrEmpty($logDir)) {
	New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}
Remove-Item -LiteralPath $Log -ErrorAction SilentlyContinue

$oldPass = $env:PASS
$oldLog = $env:DRAWTERM_LOG

try {
	$env:PASS = $Password
	$env:DRAWTERM_LOG = $Log

	$args = @()
	if (-not $NoVerbose) {
		$args += "-v"
	}
	$args += @("-h", $CpuHost, "-a", $AuthServer, "-u", $User)

	Write-Host "Running: $Exe $($args -join ' ')"
	Write-Host "Log: $Log"

	$p = Start-Process -FilePath $Exe -ArgumentList $args -PassThru
	if ($TimeoutSeconds -le 0) {
		Write-Host "Waiting for drawterm to exit. Close the drawterm window when the test is done."
		$p.WaitForExit()
	} elseif (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
		Write-Host "Timed out after $TimeoutSeconds seconds; stopping process $($p.Id)."
		Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
		$p.WaitForExit()
	}
	$hexExit = "0x{0:X8}" -f ([BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$p.ExitCode), 0))
	Write-Host "Exit code: $($p.ExitCode) ($hexExit)"

	if (Test-Path -LiteralPath $Log) {
		Write-Host ""
		Write-Host "---- drawterm log ----"
		Get-Content -LiteralPath $Log
	} else {
		Write-Host "No log file was written."
	}
} finally {
	$env:PASS = $oldPass
	$env:DRAWTERM_LOG = $oldLog
}
