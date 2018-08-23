param([string] $EnvName = "dev")

$envFolder = $PSScriptRoot
if (!$envFolder) {
    $envFolder = Get-Location
}

Set-Location $envFolder

.\Setup-ServicePrincipal2.ps1 -EnvName $EnvName
.\Setup-ContainerRegistry.ps1 -EnvName $EnvName
.\Setup-KubernetesCluster.ps1 -EnvName $EnvName
