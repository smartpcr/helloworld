param([string] $EnvName = "dev")


$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}

& $scriptFolder\Setup-ServicePrincipal2.ps1 -EnvName $EnvName 
& $scriptFolder\Setup-ContainerRegistry.ps1 -EnvName $EnvName
& $scriptFolder\Setup-AksCluster.ps1 -EnvName $EnvName
