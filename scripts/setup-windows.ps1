param(
    [string]$InstallPath = "$PSScriptRoot\\..\\.tools\\nuget",
    [switch]$AddToUserPath
)

$InstallPath = (Resolve-Path -Path $InstallPath -ErrorAction SilentlyContinue).Path -or $InstallPath
if (-not (Test-Path -Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
}

$nugetUrl = 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe'
$nugetExe = Join-Path $InstallPath 'nuget.exe'

Write-Host "Downloading nuget.exe to $nugetExe ..."
Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetExe -UseBasicParsing
Write-Host "Downloaded nuget.exe"

if ($AddToUserPath) {
    $current = [Environment]::GetEnvironmentVariable('Path','User')
    if (-not ($current -and $current.Split(';') -contains $InstallPath)) {
        Write-Host "Adding $InstallPath to user PATH (setx)..."
        $new = if ($current) { "$current;$InstallPath" } else { $InstallPath }
        setx PATH "$new" | Out-Null
        Write-Host "Added. You may need to restart your shell or IDE to pick up the change."
    } else {
        Write-Host "$InstallPath already present in user PATH"
    }
} else {
    Write-Host "Run with -AddToUserPath to add to user PATH permanently."
}
