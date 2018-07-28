<#
    this script retrieve settings based on target environment
    1) create azure resource group
    2) create key vault
    3) create certificate and add to key vault
    4) create service principle with cert auth
    5) grant permission to service principle
        a) key vault
        b) resource group
#>
param([string] $envName = "dev")

$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}


Install-Module powershell-yaml
Import-Module "$scriptFolder\common.psm1" -Force

$values = Get-Content "$scriptFolder\values.yaml" -Raw | ConvertFrom-Yaml
if ($envName) {
    $envValueYamlFile = "$scriptFolder\$envName\values.yaml"
    if (Test-Path $envValueYamlFile) {
        $envValues = Get-Content $envValueYamlFile -Raw | ConvertFrom-Yaml
        Copy-YamlObject -fromObj $envValues -toObj $values
    }
}