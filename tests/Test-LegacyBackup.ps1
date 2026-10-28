$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $sourceRoot 'TextPatch.ps1')
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $tempParent ('Aion2-Legacy-Test-' + [guid]::NewGuid().ToString('N'))
# 本脚本只操作下面创建的模拟客户端。
function Get-Process { param($Name) }
function Assert($condition, $message) { if (-not $condition) { throw $message } }
try {
    $game = Join-Path $testRoot 'steamapps\common\AION2'
    $pak = Join-Path $game 'Aion2\Content\Paks\L10N\Text\ja-JP'
    $legacy = Join-Path $game 'Aion2_English_Backup_Safe'
    New-Item -ItemType Directory -Path $pak, $legacy -Force | Out-Null
    $meta = Get-Content -LiteralPath (Join-Path $sourceRoot 'version.json') -Raw | ConvertFrom-Json
    Set-Content -LiteralPath (Join-Path $testRoot 'steamapps\appmanifest_3393110.acf') -Value ('"AppState" { "installdir" "AION2" "buildid" "' + $meta.steamBuildId + '" }')
    $hashes = @{}
    foreach ($extension in 'pak', 'sig', 'ucas', 'utoc') {
        Set-Content -LiteralPath (Join-Path $pak "pakchunk503000-Windows_0_P.$extension") -Value "Japanese original $extension"
        $name = "pakchunk502000-Windows_0_P.$extension"
        Set-Content -LiteralPath (Join-Path $legacy $name) -Value "English backup $extension"
        $hashes[$name] = (Get-FileHash -LiteralPath (Join-Path $legacy $name)).Hash
    }
    Invoke-TextPatch -GameRoot $game -TargetLanguage ja-JP -Action Install -SourceDir (Join-Path $sourceRoot 'zh') | Out-Null
    foreach ($name in $hashes.Keys) {
        Assert (-not (Test-Path -LiteralPath (Join-Path $legacy $name))) 'Japanese install left a mountable English backup.'
        Assert ((Get-FileHash -LiteralPath (Join-Path $legacy ($name + '.bak'))).Hash -eq $hashes[$name]) 'English backup bytes changed.'
    }
    Invoke-TextPatch -GameRoot $game -TargetLanguage ja-JP -Action Restore | Out-Null
    foreach ($extension in 'pak', 'sig', 'ucas', 'utoc') {
        Assert ((Get-Content -LiteralPath (Join-Path $pak "pakchunk503000-Windows_0_P.$extension")) -eq "Japanese original $extension") 'Japanese restoration changed original data.'
    }
    foreach ($name in $hashes.Keys) { Copy-Item -LiteralPath (Join-Path $legacy ($name + '.bak')) -Destination (Join-Path $legacy $name) }
    $conflict = Join-Path $legacy 'pakchunk502000-Windows_0_P.utoc.bak'
    Set-Content -LiteralPath $conflict -Value 'Different backup'
    $caught = $false
    try { Invoke-TextPatch -GameRoot $game -TargetLanguage ja-JP -Action Install -SourceDir (Join-Path $sourceRoot 'zh') | Out-Null }
    catch { $caught = $_.Exception.Message -like '*内容不一致*' }
    Assert $caught 'Conflicting legacy backups were not rejected.'
    foreach ($name in $hashes.Keys) {
        Assert ((Get-FileHash -LiteralPath (Join-Path $legacy $name)).Hash -eq $hashes[$name]) 'Conflict handling changed an original backup.'
    }
    Assert (-not (Test-Path -LiteralPath (Join-Path $game 'Aion2\Content\L10N\Text\ja-JP\L10NString.dat'))) 'Conflict handling installed a patch.'
    Write-Output 'PASS: Japanese install isolates English backups, restores independently, and rejects backup conflicts before changing client data.'
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolved.StartsWith($tempParent + '\', [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notmatch '^Aion2-Legacy-Test-[0-9a-f]{32}$') { throw 'Unsafe fixture cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
