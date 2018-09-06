param([string] $EnvName = "dev")


$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}

Invoke-Expression "$scriptFolder\Setup-ServicePrincipal2.ps1 -EnvName $EnvName" 
Invoke-Expression "$scriptFolder\Setup-ContainerRegistry.ps1 -EnvName $EnvName" 
Invoke-Expression "$scriptFolder\Setup-AksCluster.ps1 -EnvName $EnvName" 
