function SetTerraformValue {
    param (
        [string] $valueFile, 
        [string] $name, 
        [string] $value)

    $content = ""
    if (Test-Path $valueFile) {
        $content = Get-Content $valueFile 
    }
    
    $regex = New-Object System.Text.RegularExpressions.Regex("$name\s*=\s*""?([^""]*)\""?")
    $replaceValue = "$name = ""$value"""
    $buffer = New-Object System.Text.StringBuilder

    if ($null -eq $content -or $content.Trim().Length -eq 0) {
        $buffer.AppendLine($replaceValue) | Out-Null
    }
    else {
        $match = $regex.Match($content)
        if ($match.Success) {
            $content | ForEach-Object {
                $line = $_ 
                if ($line) {
                    $line = $regex.Replace($line, $replaceValue)
                    $buffer.AppendLine($line) | Out-Null
                }
            }
        }
        else {
            $content | ForEach-Object {
                $line = $_ 
                if ($line) {
                    $buffer.AppendLine($line) | Out-Null
                }
            }
            $buffer.AppendLine($replaceValue) | Out-Null
        }
    }

    $buffer.ToString() | Out-File $valueFile
}