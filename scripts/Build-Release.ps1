param([string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$metadata = Get-Content -LiteralPath (Join-Path $root 'version.json') -Raw | ConvertFrom-Json
$version = [string]$metadata.version
if ($version -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$') { throw 'version.json 中的版本号无效。' }
if ($metadata.repository -ne 'Foohi666/Aion2-CN-Foohi') { throw '发布仓库不匹配。' }
$log = Get-Content -LiteralPath (Join-Path $root 'CHANGELOG.md') -Raw -Encoding UTF8
$pattern = '(?ms)^## \[' + [regex]::Escape($version) + '\] - (\d{4}-\d{2}-\d{2})\r?\n(.*?)(?=^## |\z)'
$section = [regex]::Match($log, $pattern)
if (-not $section.Success -or $section.Groups[2].Value.Trim().Length -lt 20) { throw "缺少 v$version 的版本更新记录，停止打包。" }
$notes = "## v$version · $($section.Groups[1].Value)`r`n`r`n" + $section.Groups[2].Value.Trim()
$files = @('App.ps1','Aion2CNTool.ps1','TextPatch.ps1','Update.ps1','version.json','README.md','CHANGELOG.md','启动汉化工具.bat')
foreach ($variant in 'zh','zh-TW') {
    $manifest = Get-Content -LiteralPath (Join-Path $root "$variant\payloads.json") -Raw | ConvertFrom-Json
    if ($manifest.SteamBuildId -ne $metadata.steamBuildId -or @($manifest.Files).Count -ne 1) { throw "$variant 的数据版本或文件数量不匹配。" }
    $files += "$variant\payloads.json"
    foreach ($language in 'ja-JP') {
        $path = "$variant\$language\L10NString.dat"
        $record = @($manifest.Files | Where-Object Language -eq $language)
        if ($record.Count -ne 1 -or (Get-FileHash -LiteralPath (Join-Path $root $path)).Hash -ne $record[0].SHA256) { throw "汉化文件校验失败：$path" }
        $files += $path
    }
}
foreach ($name in $files) {
    $path = Join-Path $root $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "缺少发布文件：$name" }
    if ($name.EndsWith('.ps1')) {
        $tokens = $null
        $parseErrors = $null
        [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors.Count) { throw "脚本语法检查失败：$name；$($parseErrors[0].Message)" }
    }
}
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'dist' }
$output = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output -Force | Out-Null
$baseName = "Aion2-CN-Foohi-v$version"
$stage = Join-Path $output ($baseName + '-stage-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $stage $baseName
New-Item -ItemType Directory -Path $package -Force | Out-Null
foreach ($name in $files) {
    $dest = Join-Path $package $name
    New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root $name) -Destination $dest
}
$zip = Join-Path $output ($baseName + '.zip')
Compress-Archive -LiteralPath $package -DestinationPath $zip -Force
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $output ($baseName + '.sha256')), ($hash + '  ' + $baseName + '.zip' + "`n"), [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $output ($baseName + '-release-notes.md')), $notes, (New-Object Text.UTF8Encoding($false)))
# 临时打包目录仅在验证其位于本次输出目录下后清理。
if (-not [IO.Path]::GetFullPath($stage).StartsWith($output.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '临时目录超出输出路径。' }
Remove-Item -LiteralPath $stage -Recurse -Force
Write-Output $zip
