function SetTerraformValue {
    param (
        [string] $valueFile, 
        [string] $name, 
        [string] $value)

    $content = Get-Content $valueFile 
    $regex = New-Object System.Text.RegularExpressions.Regex("$name\s*=\s*""?([^""]*)\""?")
    $buffer = New-Object System.Text.StringBuilder
    $content | ForEach-Object {
        $line = $_ 
        $line = $regex.Replace($line, $replaceValue)
        $buffer.AppendLine($line) | Out-Null
    }
    $buffer.ToString() | Out-File $valueFile
}