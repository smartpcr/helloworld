
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
