<#
.SYNOPSIS
Builds Windows Drawterm in Ubuntu under WSL and installs it for the current
Windows user.

.DESCRIPTION
Clones the exact committed HEAD of the current Windows checkout into temporary
WSL-native storage, performs and validates a MinGW-w64 build, saves the build
artifact below build\mingw-wsl, and installs drawterm.exe in a per-user Windows
directory. The script checks prerequisites but does not install packages.

.PARAMETER Distribution
The Ubuntu WSL distribution to use. When omitted, the default WSL distribution
is used.

.PARAMETER InstallDirectory
The Windows destination directory. The default is
%LOCALAPPDATA%\Programs\Drawterm.

.PARAMETER AddToPath
Adds the install directory to the current user's PATH. Existing entries are
preserved, and repeated runs do not duplicate the entry.

.PARAMETER KeepBuildTree
Preserves the temporary WSL checkout after a successful build. Failed build
trees are always preserved for diagnosis.

.EXAMPLE
.\install-windows-wsl.ps1 -AddToPath

.EXAMPLE
.\install-windows-wsl.ps1 -Distribution Ubuntu -AddToPath
#>

#requires -Version 5.1

[CmdletBinding()]
param(
	[string]$Distribution,
	[string]$InstallDirectory,
	[switch]$AddToPath,
	[switch]$KeepBuildTree
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)

	Write-Host ""
	Write-Host "==> $Message"
}

function Invoke-NativeCapture {
	param(
		[string]$FilePath,
		[string[]]$ArgumentList,
		[string]$Description
	)

	$output = @(& $FilePath @ArgumentList 2>&1)
	$exitCode = $LASTEXITCODE
	if($exitCode -ne 0){
		$text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
		throw "$Description failed with exit code $exitCode.$([Environment]::NewLine)$text"
	}
	return $output | ForEach-Object { $_.ToString() }
}

function Test-GitQuiet {
	param(
		[string]$Git,
		[string]$Repository,
		[string[]]$Arguments,
		[string]$Description
	)

	& $Git -C $Repository @Arguments
	$exitCode = $LASTEXITCODE
	if($exitCode -eq 0){
		return $true
	}
	if($exitCode -eq 1){
		return $false
	}
	throw "$Description failed with exit code $exitCode."
}

function Convert-ToWslPath {
	param(
		[string]$Wsl,
		[string]$DistributionName,
		[string]$WindowsPath,
		[string]$Description
	)

	# wsl.exe reconstructs the Linux command line and unescaped backslashes can
	# be consumed before wslpath sees them. Forward slashes are valid in Windows
	# paths and survive that boundary unchanged.
	$portableWindowsPath = $WindowsPath.Replace('\', '/')
	return ((Invoke-NativeCapture -FilePath $Wsl `
		-ArgumentList @("-d", $DistributionName, "--", "wslpath", "-a", "-u", $portableWindowsPath) `
		-Description $Description) -join "").Trim()
}

function Get-OsReleaseValue {
	param(
		[string[]]$Lines,
		[string]$Name
	)

	$prefix = "$Name="
	$line = $Lines | Where-Object { $_.StartsWith($prefix, [StringComparison]::Ordinal) } |
		Select-Object -First 1
	if($null -eq $line){
		return $null
	}
	return $line.Substring($prefix.Length).Trim().Trim('"')
}

function Get-PeInformation {
	param([string]$Path)

	$stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
	$reader = New-Object IO.BinaryReader($stream)
	try {
		if($reader.ReadUInt16() -ne 0x5A4D){
			throw "'$Path' does not have an MZ header."
		}
		$stream.Position = 0x3C
		$peOffset = $reader.ReadInt32()
		if($peOffset -lt 0 -or ($peOffset + 96) -gt $stream.Length){
			throw "'$Path' has an invalid PE header offset."
		}
		$stream.Position = $peOffset
		if($reader.ReadUInt32() -ne 0x00004550){
			throw "'$Path' does not have a PE signature."
		}
		$machine = $reader.ReadUInt16()
		$optionalHeader = $peOffset + 24
		$stream.Position = $optionalHeader
		$magic = $reader.ReadUInt16()
		$stream.Position = $optionalHeader + 16
		$entryPoint = $reader.ReadUInt32()
		$stream.Position = $optionalHeader + 68
		$subsystem = $reader.ReadUInt16()

		[pscustomobject]@{
			Machine = $machine
			OptionalHeaderMagic = $magic
			EntryPoint = $entryPoint
			Subsystem = $subsystem
		}
	} finally {
		$reader.Dispose()
		$stream.Dispose()
	}
}

function Assert-ExpectedDrawtermPe {
	param(
		[string]$Path,
		[string]$Label
	)

	$pe = Get-PeInformation -Path $Path
	if($pe.Machine -ne 0x8664){
		throw "$Label has unexpected PE machine 0x$('{0:X4}' -f $pe.Machine); expected AMD64 (0x8664)."
	}
	if($pe.OptionalHeaderMagic -ne 0x020B){
		throw "$Label is not a PE32+ executable."
	}
	if($pe.Subsystem -ne 3){
		throw "$Label has PE subsystem $($pe.Subsystem); expected Windows CUI (3)."
	}
	if($pe.EntryPoint -eq 0){
		throw "$Label has an empty PE entry point."
	}
	return $pe
}

function Normalize-PathEntry {
	param([string]$Entry)

	if([string]::IsNullOrWhiteSpace($Entry)){
		return ""
	}
	$expanded = [Environment]::ExpandEnvironmentVariables($Entry.Trim().Trim('"'))
	return $expanded.TrimEnd('\', '/')
}

function Test-PathEntry {
	param(
		[string[]]$Entries,
		[string]$Candidate
	)

	$normalizedCandidate = Normalize-PathEntry -Entry $Candidate
	foreach($entry in $Entries){
		if([string]::Equals(
			(Normalize-PathEntry -Entry $entry),
			$normalizedCandidate,
			[StringComparison]::OrdinalIgnoreCase
		)){
			return $true
		}
	}
	return $false
}

$repositoryRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$helperPath = Join-Path $repositoryRoot "scripts\build-windows-wsl.sh"
$buildOutputDirectory = Join-Path $repositoryRoot "build\mingw-wsl"
$artifactPath = Join-Path $buildOutputDirectory "drawterm.exe"
$buildStagingPath = Join-Path $buildOutputDirectory (".drawterm-build-{0}.exe" -f [Guid]::NewGuid().ToString("N"))

if([string]::IsNullOrWhiteSpace($InstallDirectory)){
	$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
	$InstallDirectory = Join-Path $localAppData "Programs\Drawterm"
}
$InstallDirectory = [IO.Path]::GetFullPath($InstallDirectory)
if($InstallDirectory.Contains(";")){
	throw "The installation directory cannot contain a semicolon because it may be added to PATH."
}
$installedPath = Join-Path $InstallDirectory "drawterm.exe"

if(-not (Test-Path -LiteralPath (Join-Path $repositoryRoot ".git"))){
	throw "Run this script from a Git checkout of Drawterm."
}
if(-not (Test-Path -LiteralPath $helperPath)){
	throw "The WSL build helper was not found at '$helperPath'."
}

$gitCommand = Get-Command git.exe -ErrorAction Stop
$wslCommand = Get-Command wsl.exe -ErrorAction Stop

try {
	$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
	$principal = New-Object Security.Principal.WindowsPrincipal($identity)
	if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
		Write-Warning "This per-user installer does not require elevation. Verify that it is installing for the intended Windows account."
	}
} catch {
	Write-Verbose "Could not determine whether PowerShell is elevated: $($_.Exception.Message)"
}

Write-Step "Checking the Windows source checkout"
$trackedWorktreeClean = Test-GitQuiet -Git $gitCommand.Source -Repository $repositoryRoot `
	-Arguments @("diff", "--quiet", "--ignore-submodules", "--") `
	-Description "git diff"
$trackedIndexClean = Test-GitQuiet -Git $gitCommand.Source -Repository $repositoryRoot `
	-Arguments @("diff", "--cached", "--quiet", "--ignore-submodules", "--") `
	-Description "git diff --cached"
if(-not $trackedWorktreeClean -or -not $trackedIndexClean){
	throw "Tracked source changes are present. Commit or restore them before building so the WSL clone matches the selected commit."
}

$statusLines = @(Invoke-NativeCapture -FilePath $gitCommand.Source `
	-ArgumentList @("-C", $repositoryRoot, "status", "--porcelain=v1", "--untracked-files=normal") `
	-Description "git status")
$untracked = @($statusLines | Where-Object { $_ -match '^\?\?' })
if($untracked.Count -gt 0){
	Write-Warning "Untracked files are not included in the WSL build: $($untracked -join ', ')"
}

$sourceCommit = ((Invoke-NativeCapture -FilePath $gitCommand.Source `
	-ArgumentList @("-C", $repositoryRoot, "rev-parse", "HEAD") `
	-Description "git rev-parse HEAD") -join "").Trim()
if($sourceCommit -notmatch '^[0-9a-fA-F]{40}$'){
	throw "Git returned an unexpected commit identifier: '$sourceCommit'."
}
Write-Host "Source commit: $sourceCommit"

Write-Step "Selecting and checking the WSL distribution"
if([string]::IsNullOrWhiteSpace($Distribution)){
	$Distribution = ((Invoke-NativeCapture -FilePath $wslCommand.Source `
		-ArgumentList @("--", "printenv", "WSL_DISTRO_NAME") `
		-Description "WSL default-distribution detection") -join "").Trim()
}
if([string]::IsNullOrWhiteSpace($Distribution)){
	throw "Could not determine the WSL distribution. Pass -Distribution explicitly."
}

$osRelease = @(Invoke-NativeCapture -FilePath $wslCommand.Source `
	-ArgumentList @("-d", $Distribution, "--", "cat", "/etc/os-release") `
	-Description "WSL operating-system detection")
$distributionId = Get-OsReleaseValue -Lines $osRelease -Name "ID"
$distributionVersion = Get-OsReleaseValue -Lines $osRelease -Name "VERSION_ID"
if($distributionId -ne "ubuntu"){
	$detected = if($distributionId){$distributionId}else{"unknown"}
	throw "The automated workflow is currently tested only with Ubuntu under WSL; '$Distribution' reported '$detected'."
}
if([string]::IsNullOrWhiteSpace($distributionVersion)){
	$distributionVersion = "unknown"
}
Write-Host "Distribution: $Distribution (Ubuntu $distributionVersion)"

$repositoryWslPath = Convert-ToWslPath -Wsl $wslCommand.Source `
	-DistributionName $Distribution -WindowsPath $repositoryRoot `
	-Description "Windows source-path translation"
$helperWslPath = Convert-ToWslPath -Wsl $wslCommand.Source `
	-DistributionName $Distribution -WindowsPath $helperPath `
	-Description "WSL helper-path translation"

[IO.Directory]::CreateDirectory($buildOutputDirectory) | Out-Null
$buildStagingWslPath = Convert-ToWslPath -Wsl $wslCommand.Source `
	-DistributionName $Distribution -WindowsPath $buildStagingPath `
	-Description "Windows artifact-path translation"

Write-Step "Building the committed source in WSL"
$wslArguments = @(
	"-d", $Distribution, "--", "bash", $helperWslPath,
	"--source", $repositoryWslPath,
	"--commit", $sourceCommit,
	"--output", $buildStagingWslPath
)
if($KeepBuildTree){
	$wslArguments += "--keep-build-tree"
}

try {
	& $wslCommand.Source @wslArguments
	$buildExitCode = $LASTEXITCODE
	if($buildExitCode -ne 0){
		throw "The WSL build failed with exit code $buildExitCode."
	}
	if(-not (Test-Path -LiteralPath $buildStagingPath)){
		throw "The WSL build completed without producing '$buildStagingPath'."
	}

	$builtPe = Assert-ExpectedDrawtermPe -Path $buildStagingPath -Label "The WSL build artifact"
	$builtHash = (Get-FileHash -LiteralPath $buildStagingPath -Algorithm SHA256).Hash
	Copy-Item -LiteralPath $buildStagingPath -Destination $artifactPath -Force
	$artifactHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash
	if($artifactHash -ne $builtHash){
		throw "The staged Windows artifact does not match the verified WSL build."
	}

	Write-Host "Artifact: $artifactPath"
	Write-Host "SHA-256: $artifactHash"
	Write-Host ("PE entry point: 0x{0:X8}" -f $builtPe.EntryPoint)
	Write-Host "PE subsystem: Windows CUI (3)"
} finally {
	if(Test-Path -LiteralPath $buildStagingPath){
		Remove-Item -LiteralPath $buildStagingPath -Force
	}
}

Write-Step "Installing Drawterm for the current Windows user"
[IO.Directory]::CreateDirectory($InstallDirectory) | Out-Null
$installStagingPath = Join-Path $InstallDirectory (".drawterm-install-{0}.exe" -f [Guid]::NewGuid().ToString("N"))
$backupPath = Join-Path $InstallDirectory (".drawterm-backup-{0}.exe" -f [Guid]::NewGuid().ToString("N"))
$targetPreviouslyExisted = Test-Path -LiteralPath $installedPath
$previousUserPath = [Environment]::GetEnvironmentVariable(
	"Path",
	[EnvironmentVariableTarget]::User
)
$pathChanged = $false
$installCompleted = $false

try {
	Copy-Item -LiteralPath $artifactPath -Destination $installStagingPath
	Assert-ExpectedDrawtermPe -Path $installStagingPath -Label "The installation staging file" | Out-Null
	$installStagingHash = (Get-FileHash -LiteralPath $installStagingPath -Algorithm SHA256).Hash
	if($installStagingHash -ne $artifactHash){
		throw "The installation staging file does not match the verified build artifact."
	}

	if($targetPreviouslyExisted){
		Copy-Item -LiteralPath $installedPath -Destination $backupPath
	}
	Copy-Item -LiteralPath $installStagingPath -Destination $installedPath -Force
	$installedHash = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash
	if($installedHash -ne $artifactHash){
		throw "The installed executable does not match the verified build artifact."
	}

	if($AddToPath){
		$userPathEntries = @($previousUserPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
		if(-not (Test-PathEntry -Entries $userPathEntries -Candidate $InstallDirectory)){
			$newUserPath = (($userPathEntries + $InstallDirectory) -join ";")
			[Environment]::SetEnvironmentVariable(
				"Path",
				$newUserPath,
				[EnvironmentVariableTarget]::User
			)
			$persistedEntries = @(
				[Environment]::GetEnvironmentVariable(
					"Path",
					[EnvironmentVariableTarget]::User
				) -split ';'
			)
			if(-not (Test-PathEntry -Entries $persistedEntries -Candidate $InstallDirectory)){
				throw "The installation directory was not persisted in the user PATH."
			}
			$pathChanged = $true
		}
	}

	$currentEntries = @($env:Path -split ';')
	if(-not (Test-PathEntry -Entries $currentEntries -Candidate $InstallDirectory)){
		$env:Path = "$($env:Path.TrimEnd(';'));$InstallDirectory"
	}
	$resolved = Get-Command drawterm.exe -ErrorAction Stop
	if(-not [string]::Equals(
		[IO.Path]::GetFullPath($resolved.Source),
		[IO.Path]::GetFullPath($installedPath),
		[StringComparison]::OrdinalIgnoreCase
	)){
		throw "The current installer process resolved drawterm.exe to '$($resolved.Source)' instead of '$installedPath'."
	}

	$installCompleted = $true
} catch {
	if($pathChanged){
		[Environment]::SetEnvironmentVariable(
			"Path",
			$previousUserPath,
			[EnvironmentVariableTarget]::User
		)
	}
	if($targetPreviouslyExisted -and (Test-Path -LiteralPath $backupPath)){
		Copy-Item -LiteralPath $backupPath -Destination $installedPath -Force
	} elseif(-not $targetPreviouslyExisted -and (Test-Path -LiteralPath $installedPath)){
		Remove-Item -LiteralPath $installedPath -Force
	}
	throw
} finally {
	if(Test-Path -LiteralPath $installStagingPath){
		Remove-Item -LiteralPath $installStagingPath -Force
	}
	if(Test-Path -LiteralPath $backupPath){
		Remove-Item -LiteralPath $backupPath -Force
	}
}

if(-not $installCompleted){
	throw "The installation did not complete."
}

Write-Host "Installed: $installedPath"
Write-Host "SHA-256: $artifactHash"
if($AddToPath){
	if($pathChanged){
		Write-Host "Added to the user PATH: $InstallDirectory"
	} else {
		Write-Host "Already on the user PATH: $InstallDirectory"
	}
	Write-Host "Open a new Windows Terminal session before invoking drawterm by name."
} else {
	Write-Host "PATH was not changed. Re-run with -AddToPath to add the installation directory."
}
