$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}
Import-Module "$scriptFolder\modules\common.psm1" -Force

if (-not (Test-IsAdmin)) {
    throw "You need to run this script as administrator"
}

# install chocolatey 
if (-not (Test-ChocoInstalled)) {
    Write-Host "Installing chocolate..."
    Set-ExecutionPolicy Bypass -Scope Process -Force; 
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

    choco install firacode -Y
}
else {
    Write-Host "Chocolate already installed"
}

# install .net core
if (-not (Test-NetCoreInstalled)) {
    Write-Host "Installing .net core..."
    $netSdkDownloadLink = "https://download.microsoft.com/download/D/0/4/D04C5489-278D-4C11-9BD3-6128472A7626/dotnet-sdk-2.1.301-win-gs-x64.exe"
    $tempFile = "C:\users\$env:username\downloads\dotnetsdk.exe"
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($netSdkDownloadLink, $tempFile)
    Start-Process $tempFile -Wait 
    Remove-Item $tempFile -Force 
}
else {
    Write-Host ".net core is already installed"
}

if (-not (Test-AzureCliInstalled)) {
    Write-Host "Installing azure cli..."
    $azureCliDownloadLink = "https://aka.ms/installazurecliwindows"
    $tempFile = "C:\users\$env:username\downloads\azcli.msi"
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($azureCliDownloadLink, $tempFile)
    Start-Process $tempFile -Wait 
    Remove-Item $tempFile -Force 
}
else {
    Write-Host "az cli is already installed"
}

if (-not (Test-DockerInstalled)) {
    Write-Host "Installing docker ce for windows.."
    $dockerForWindow = "https://download.docker.com/win/stable/Docker%20for%20Windows%20Installer.exe"
    $tempFile = "C:\users\$env:username\downloads\Docker for Windows Installer.exe"
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($dockerForWindow, $tempFile)
    Start-Process $tempFile -Wait 
    Remove-Item $tempFile -Force 
}

# kubectl must be installed before minikube
Write-Host "Installing kubectl..."
choco install kubernetes-cli -y

# install heml
Write-Host "Installing helm..."
choco install kubernetes-helm -y