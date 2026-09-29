$ErrorActionPreference = "Stop"

$projectDir = $PSScriptRoot
$godot = Join-Path $projectDir "godot.exe"
$windowsDir = Join-Path $projectDir "builds\windows"
$windowsOutput = Join-Path $windowsDir "SIH UGV.exe"

if (-not (Test-Path -LiteralPath $godot -PathType Leaf)) {
	throw "Godot 4.7.2 editor executable was not found at '$godot'."
}

New-Item -ItemType Directory -Force -Path $windowsDir | Out-Null

Write-Host "Importing project resources..."
& $godot --headless --editor --path $projectDir --import --quit
if (-not $?) {
	throw "Godot resource import failed."
}

Write-Host "Exporting single-file Windows game..."
$exportStarted = Get-Date
if (Test-Path -LiteralPath $windowsOutput) {
	Remove-Item -LiteralPath $windowsOutput -Force
}
& $godot --headless --editor --path $projectDir --export-release "Windows Desktop" $windowsOutput
$exportDeadline = (Get-Date).AddMinutes(3)
$builtExecutable = $null
do {
	Start-Sleep -Seconds 1
	$builtExecutable = Get-Item -LiteralPath $windowsOutput -ErrorAction SilentlyContinue
} until (($builtExecutable -and $builtExecutable.Length -gt 50MB -and $builtExecutable.LastWriteTime -ge $exportStarted) -or (Get-Date) -ge $exportDeadline)
if (-not $builtExecutable -or $builtExecutable.Length -le 50MB -or $builtExecutable.LastWriteTime -lt $exportStarted) {
	throw "Windows export failed. The expected standalone executable was not produced."
}

Write-Host "Build complete."
Write-Host "Windows: $windowsOutput"
