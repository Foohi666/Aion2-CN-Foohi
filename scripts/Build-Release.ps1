param([string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$info = Get-Content -LiteralPath (Join-Path $project 'version.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($info.version -notmatch '^\d+\.\d+\.\d+$' -or $info.repository -ne 'Foohi666/Aion2-CN-Foohi') { throw '版本清单无效。' }
$history = Get-Content -LiteralPath (Join-Path $project 'CHANGELOG.md') -Raw -Encoding UTF8
$entry = [regex]::Match($history, '(?ms)^## \[' + [regex]::Escape($info.version) + '\] - (\d{4}-\d{2}-\d{2})\r?\n(.+?)(?=^## |\z)')
if (-not $entry.Success -or $entry.Groups[2].Value.Trim().Length -lt 20) { throw '缺少同版本更新记录。' }
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw '需要 Windows 的 .NET Framework 4.x 编译器。' }
$included = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($name in 'version.json','README.md','CHANGELOG.md','SOURCES.md') { $null = $included.Add($name) }
function CheckAsset([string]$Relative, [string]$Hash, [long]$Length = -1) {
    $absolute = [IO.Path]::GetFullPath((Join-Path $project $Relative))
    if (-not $absolute.StartsWith($project.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw '发布文件超出项目目录。' }
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "缺少文件：$Relative" }
    if ($Length -ge 0 -and (Get-Item -LiteralPath $absolute).Length -ne $Length) { throw "文件长度不匹配：$Relative" }
    if ($Hash -and (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash -ne $Hash) { throw "校验失败：$Relative" }
    $null = $included.Add($Relative)
}
foreach ($variant in 'zh','zh-TW') {
    $manifestPath = "$variant/payloads.json"
    CheckAsset $manifestPath ''
    $manifest = Get-Content -LiteralPath (Join-Path $project $manifestPath) -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.SteamBuildId -ne $info.steamBuildId -or $manifest.InstallationMode -ne 'PackedFontAlias') { throw '汉化资源版本不匹配。' }
    $text = @($manifest.Files | Where-Object Language -eq 'ja-JP')
    if ($text.Count -ne 1 -or $manifest.Files.Count -ne 1) { throw '日文文字表记录不唯一。' }
    CheckAsset "$variant/ja-JP/L10NString.dat" $text[0].SHA256 $manifest.PackedFile.PayloadLength
    $fontPath = "font/$variant/manifest.json"
    if ($manifest.FontPatchManifest -ne $fontPath) { throw '字体清单路径不匹配。' }
    CheckAsset $fontPath ''
    $font = Get-Content -LiteralPath (Join-Path $project $fontPath) -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($font.SchemaVersion -ne 1 -or $font.SteamBuildId -ne $info.steamBuildId) { throw '字体版本不匹配。' }
    foreach ($region in $font.Regions) {
        if ($region.DataFile -notmatch ('^font/'+[regex]::Escape($variant)+'/blocks/[A-Za-z0-9_-]+\.bin$')) { throw '字体补丁路径不合法。' }
        CheckAsset $region.DataFile $region.AfterSHA256 $region.Length
    }
    foreach ($asset in $font.AssetFiles) {
        if ($asset.Path -notin @("font/$variant/aliases.json",'font/OFL.txt','font/NOTICE.txt')) { throw '字体附件路径不合法。' }
        CheckAsset $asset.Path $asset.SHA256 $asset.Size
    }
}
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $project 'dist' }
$destination = [IO.Path]::GetFullPath($OutputDirectory)
$null = New-Item -ItemType Directory -Path $destination -Force
$name = 'Foohi-AION2-v' + $info.version
$staging = Join-Path $destination ($name + '-build-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $staging $name
$null = New-Item -ItemType Directory -Path $package -Force
try {
    foreach ($relative in $included) {
        $target = Join-Path $package $relative
        $null = New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force
        Copy-Item -LiteralPath (Join-Path $project $relative) -Destination $target
    }
    $assembly = Join-Path $staging 'AssemblyInfo.cs'
    [IO.File]::WriteAllText($assembly, ('using System.Reflection; [assembly: AssemblyTitle("Foohi AION 2")] [assembly: AssemblyCompany("Foohi")] [assembly: AssemblyVersion("'+$info.version+'.0")] [assembly: AssemblyFileVersion("'+$info.version+'.0")]'), [Text.Encoding]::UTF8)
    $sources = @(Get-ChildItem -LiteralPath (Join-Path $project 'src') -Filter '*.cs' -File | ForEach-Object FullName)
    $binary = Join-Path $package 'Foohi.Aion2.exe'
    & $compiler /nologo /target:winexe /platform:x64 /optimize+ /nowarn:0649 "/out:$binary" /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll /r:System.Core.dll $sources $assembly
    if ($LASTEXITCODE -ne 0) { throw '编译失败。' }
    $archive = Join-Path $destination ($name + '.zip')
    Compress-Archive -LiteralPath $package -DestinationPath $archive -Force
    $digest = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $destination ($name+'.sha256')), $digest+'  '+$name+".zip`n", [Text.Encoding]::ASCII)
    $notes = '## v'+$info.version+' · '+$entry.Groups[1].Value+"`r`n`r`n"+$entry.Groups[2].Value.Trim()
    [IO.File]::WriteAllText((Join-Path $destination ($name+'-release-notes.md')), $notes, [Text.UTF8Encoding]::new($false))
    Write-Output $archive
} finally {
    $resolved = [IO.Path]::GetFullPath($staging)
    if (-not $resolved.StartsWith($destination.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw '构建清理目录越界。' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
