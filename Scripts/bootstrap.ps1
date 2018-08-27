param([string] $EnvName = "dev")


$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}


.\Setup-ServicePrincipal2.ps1 -EnvName $EnvName
.\Setup-ContainerRegistry.ps1 -EnvName $EnvName
.\Setup-KubernetesCluster.ps1 -EnvName $EnvName
