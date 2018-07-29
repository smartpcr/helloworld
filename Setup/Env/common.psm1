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
                Write-Host "Adding $($name) to terget object"
                $toObj.Add($name, $value)
            }
            else {
                Write-Host "Overwrite prop: name=$($name), value=$($value)"
                $tgtValue = $toObj.Item($tgtName)
                if ($value -is [string] -or $value -is [int] -or $value -is [bool]) {
                    if ($value -ne $tgtValue) {
                        Write-Host "Change value from $($tgtValue) to $($value)"
                        $toObj[$tgtName] = $value
                    }
                }
                else {
                    Write-Host "Copy object $($name)"
                    Copy-YamlObject -fromObj $value -toObj $tgtValue
                }
            }
        }
    }
}

function Set-Values {
    param (
        [object] $valueTemplate,
        [object] $settings
    )

    $regex = New-Object System.Text.RegularExpressions.Regex("\{\{\s*\.Values\.(\w+)\s*\}\}")
    $match = $regex.Match($valueTemplate)
    while ($match.Success) {
        $toBeReplaced = $match.Value
        $searchKey = $match.Groups[1].Value
        $found = $settings.Keys | Where-Object { $_ -eq $searchKey }
        if ($found) {
            $replaceValue = $settings.Item($found)
            Write-Host "Replace $toBeReplaced with $replaceValue"
            $valueTemplate = ([string]$valueTemplate).Replace($toBeReplaced, $replaceValue)
            $match = $regex.Match($valueTemplate)
        }
        else {
            $match = $match.NextMatch()
        }
    }

    return $valueTemplate
}