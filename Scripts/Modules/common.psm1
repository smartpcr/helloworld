
function Test-IsAdmin {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = new-object System.Security.Principal.WindowsPrincipal($wid)
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    $isAdmin = $prp.IsInRole($adm)
    return $isAdmin
}

function Test-NetCoreInstalled () {
    try {
        $dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
        $isInstalled = $false
        if ($dotnetCmd) {
            $isInstalled = Test-Path($dotnetCmd.Source)
        }
        return $isInstalled
    }
    catch {
        return $false 
    }
}

function Test-AzureCliInstalled() {
    try {
        $azCmd = Get-Command az -ErrorAction SilentlyContinue
        if ($azCmd) {
            $azVersionConent = az --version
            $azVersionString = $azVersionConent[0]
            if ($azVersionString -match "\(([\.0-9]+)\)") {
                $version = $matches[1]
                $currentVersion = [System.Version]::new($version)
                $requiredVersion = [System.Version]::new("2.0.36") # aks enable-rbac is introduced in this version
                if ($currentVersion -lt $requiredVersion) {
                    return $false
                }
            }
            else {
                return $false 
            }
            return Test-Path $azCmd.Source 
        }
    }
    catch {}
    return $false 
}

function Test-ChocoInstalled() {
    try {
        $chocoVersion = Invoke-Expression "choco -v" -ErrorAction SilentlyContinue
        return ($chocoVersion -ne $null)
    }
    catch {}
    return $false 
}

function Test-DockerInstalled() {
    try {
        $dockerVer = Invoke-Expression "docker --version" -ErrorAction SilentlyContinue
        return ($dockerVer -ne $null)
    }
    catch {}
    return $false 
}

function Get-WindowsVersion {
    (Get-WmiObject win32_operatingsystem).caption
    #(Get-WmiObject -class Win32_OperatingSystem).Version
}

function Install-Docker() {
    $winVer = Get-WindowsVersion
    if (($winVer -like "*Windows Server 2016*") -or ($winVer -like "*Windows Server 2019*")) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
        Install-Module -Name DockerMsftProvider -Force
        Install-Package -Name docker -ProviderName DockerMsftProvider -Force

        # install docker-compose 
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $dockerComposeVersion = "1.23.2"
        $dockerComposeInstallFile = "$Env:ProgramFiles\docker\docker-compose.exe"
        Invoke-WebRequest "https://github.com/docker/compose/releases/download/$dockerComposeVersion/docker-compose-Windows-x86_64.exe" -UseBasicParsing -OutFile $dockerComposeInstallFile
    }
    else {
        Write-Host "Installing docker ce for windows.."
        $dockerForWindow = "https://download.docker.com/win/stable/Docker%20for%20Windows%20Installer.exe"
        $tempFile = "C:\users\$env:username\downloads\Docker for Windows Installer.exe"
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($dockerForWindow, $tempFile)
        Start-Process $tempFile -Wait 
        Remove-Item $tempFile -Force 
    }
}