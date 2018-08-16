function SetTerraformValue {
    param (
        [string] $valueFile, 
        [string] $name, 
        [string] $value)

    $content = Get-Content $valueFile 
    $regex = New-Object System.Text.RegularExpressions.Regex("$name\s*=\s*""?([^""]*)\""?")
    $replaceValue = "$name = ""$value"""
    $buffer = New-Object System.Text.StringBuilder

    $match = $regex.Match($content)
    if ($match.Success) {
        $content | ForEach-Object {
            $line = $_ 
            if ($line -and $line.Length -gt 0) {
                $line = $regex.Replace($line, $replaceValue)
                $buffer.AppendLine($line) | Out-Null
            }
        }
    }
    else {
        $buffer.AppendLine($content)
        $buffer.AppendLine($replaceValue)
    }

    $buffer.ToString().Trim() | Out-File $valueFile -Encoding ascii
    terraform fmt $valueFile
}