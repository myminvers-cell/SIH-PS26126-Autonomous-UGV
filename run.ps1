Set-Location -Path $PSScriptRoot
if (Test-Path "$PSScriptRoot\godot.exe") {
    Start-Process "$PSScriptRoot\godot.exe"
} else {
    Start-Process "C:\Users\Sanjeet\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
}
