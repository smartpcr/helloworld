
Import-Module .\Modules\powershell-yaml\powershell-yaml.psm1 -Force

function Get-EnvironmentSettings {
    param(
        [string] $EnvName = "dev",
        [string] $EnvRootFolder
    )
    
    $values = Get-Content (Join-Path $EnvRootFolder "values.yaml") -Raw | ConvertFrom-Yaml2
    if ($EnvName) {
        $envFolder = Join-Path $EnvRootFolder $EnvName
        $envValueYamlFile =  Join-Path $envFolder "values.yaml"
        if (Test-Path $envValueYamlFile) {
            $envValues = Get-Content $envValueYamlFile -Raw | ConvertFrom-Yaml2
            Copy-YamlObject -fromObj $envValues -toObj $values
        }
    }

    $bootstrapTemplate = Get-Content "$EnvRootFolder\bootstrap.yaml" -Raw
    $bootstrapTemplate = Set-YamlValues -valueTemplate $bootstrapTemplate -settings $values
    $bootstrapValues = $bootstrapTemplate | ConvertFrom-Yaml2

    return $bootstrapValues
}


function Copy-YamlObject {
    param (
        [object] $fromObj,
        [object] $toObj
    )
    
    $fromObj.Keys | ForEach-Object {
        $name = $_ 
        $value = $fromObj.Item($name)
    
        if ($value) {
            $tgtName = $toObj.Keys | Where-Object { $_ -eq $name }
            if (!$tgtName) {
                $toObj.Add($name, $value)
            }
            else {
                $tgtValue = $toObj.Item($tgtName)
                if ($value -is [string] -or $value -is [int] -or $value -is [bool]) {
                    if ($value -ne $tgtValue) {
                        $toObj[$tgtName] = $value
                    }
                }
                else {
                    Copy-YamlObject -fromObj $value -toObj $tgtValue
                }
            }
        }
    }
}

function Set-YamlValues {
    param (
        [object] $valueTemplate,
        [object] $settings
    )

    $regex = New-Object System.Text.RegularExpressions.Regex("\{\{\s*\.Values\.([a-zA-Z\.0-9_]+)\s*\}\}")
    $replacements = New-Object System.Collections.ArrayList
    $match = $regex.Match($valueTemplate)
    while ($match.Success) {
        $toBeReplaced = $match.Value
        $searchKey = $match.Groups[1].Value

        $found = GetPropertyValue -subject $settings -propertyPath $searchKey
        if ($found) {
            if ($found -is [string] -or $found -is [int] -or $found -is [bool]) {
                $replaceValue = $found.ToString()
                $replacements.Add(@{
                        oldValue = $toBeReplaced
                        newValue = $replaceValue
                    })
            }
            else {
                Write-Warning "Invalid value for path '$searchKey': $found"
            }
        }
        else {
            Write-Warning "Unable to find value with path '$searchKey'"
        }
        
        $match = $match.NextMatch()
    }
    
    $replacements | ForEach-Object {
        $oldValue = $_.oldValue 
        $newValue = $_.newValue 
        $valueTemplate = $valueTemplate.Replace($oldValue, $newValue)
    }

    return $valueTemplate
}

function ReplaceValuesInYamlFile {
    param(
        [string] $YamlFile,
        [string] $PlaceHolder,
        [string] $Value 
    )

    $content = ""
    if (Test-Path $YamlFile) {
        $content = Get-Content $YamlFile 
    }

    $pattern = "{{ .Values.$PlaceHolder }}"
    $buffer = New-Object System.Text.StringBuilder
    $content | ForEach-Object {
        $line = $_ 
        if ($line) {
            $line = $line.Replace($pattern, $Value)
            $buffer.AppendLine($line) | Out-Null
        }
    }
    
    $buffer.ToString() | Out-File $YamlFile -Encoding ascii
}

function GetPropertyValue {
    param(
        [object]$subject,
        [string]$propertyPath
    )

    $propNames = $propertyPath.Split(".")
    $currentObject = $subject
    $propnames | ForEach-Object {
        $propName = $_ 
        if ($currentObject.ContainsKey($propName)) {
            $currentObject = $currentObject[$propName]
        }
        else {
            return $null 
        }
    }

    return $currentObject
}