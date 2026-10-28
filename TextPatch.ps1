# 文字语言替换；中文数据与资源回退方式来自 duoluoyuji/Aion2-Steam-CN。

function Get-TextTarget {
    param([ValidateSet('en-US', 'ja-JP', 'ko-KR')][string]$TargetLanguage)
    if ($TargetLanguage -eq 'en-US') {
        return [pscustomobject]@{ Code = 'en-US'; Name = '英文'; Setting = 'English'; Chunk = '502000'; HeaderMask = '282ae15223ea7dbb98f2e464702b4717' }
    }
    if ($TargetLanguage -eq 'ja-JP') {
        return [pscustomobject]@{ Code = 'ja-JP'; Name = '日文'; Setting = '日本語'; Chunk = '503000'; HeaderMask = 'fbecca52ae966e20457aca2cf3d75e9a' }
    }
    return [pscustomobject]@{ Code = 'ko-KR'; Name = '韩文'; Setting = '한국어'; Chunk = '501000'; HeaderMask = 'b667077c64099f6ac713904d597c1ab7' }
}

function Get-TextBackupFile {
    param([string]$Directory, [string]$Name)
    $safePath = Join-Path $Directory ($Name + '.bak')
    if (Test-Path -LiteralPath $safePath -PathType Leaf) { return $safePath }
    return (Join-Path $Directory $Name)
}

function Convert-LegacyTextBackupExtensions {
    param([string]$Root)
    $directory = Join-Path $Root 'Aion2_English_Backup_Safe'
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return }
    if ((Get-Item -LiteralPath $directory).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw '旧英文备份目录不能是链接。'
    }
    $pending = @(foreach ($extension in 'pak', 'sig', 'ucas', 'utoc') {
        $path = Join-Path $directory "pakchunk502000-Windows_0_P.$extension"
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $safe = $path + '.bak'
            $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            if ((Test-Path -LiteralPath $safe) -and
                (Get-FileHash -LiteralPath $safe -Algorithm SHA256).Hash -ne $hash) {
                throw "旧英文备份存在内容不一致的同名文件：$path"
            }
            [pscustomobject]@{ Path = $path; Safe = $safe; Hash = $hash }
        }
    })
    foreach ($item in $pending) {
        if (Test-Path -LiteralPath $item.Safe) { Remove-Item -LiteralPath $item.Path }
        else { Rename-Item -LiteralPath $item.Path -NewName ([IO.Path]::GetFileName($item.Safe)) }
        if ((Get-FileHash -LiteralPath $item.Safe -Algorithm SHA256).Hash -ne $item.Hash) {
            throw "旧英文备份改名后校验失败：$($item.Safe)"
        }
    }
}

function Update-TextBackupForBuild {
    param($Root, $PakDir, $DatPath, $BackupDir, $Language, $BuildId, $Names, $PayloadInfo)
    $old = Get-Content -LiteralPath (Join-Path $BackupDir 'state.json') -Raw | ConvertFrom-Json
    $expected = @($PayloadInfo.OriginalFiles.$Language)
    if ($old.Language -ne $Language -or @($old.Files).Count -ne 4 -or
        $old.HadDat -isnot [bool] -or $expected.Count -ne 4) {
        throw '升级所需的备份记录或新版原文件校验信息不完整；未改动客户端。'
    }
    $switchPak = Join-Path $Root "Aion2\Content\Paks\Aion2_CN_Text_${Language}_1_P.pak"
    if (Test-Path -LiteralPath $switchPak) { throw '检测到附加语言资源包，请先检查并核验游戏文件。' }
    $sources = @{}
    foreach ($name in $Names) {
        $oldRecord = @($old.Files | Where-Object Name -eq $name)
        $newRecord = @($expected | Where-Object Name -eq $name)
        $backup = Get-TextBackupFile $BackupDir $name
        if ($oldRecord.Count -ne 1 -or $newRecord.Count -ne 1 -or
            $newRecord[0].Hash -notmatch '^[0-9a-fA-F]{64}$' -or
            -not (Test-Path -LiteralPath $backup -PathType Leaf) -or
            (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $oldRecord[0].Hash) {
            throw "升级备份校验失败：$name；未改动客户端。"
        }
        $current = Join-Path $PakDir $name
        if (-not (Test-Path -LiteralPath $current -PathType Leaf) -or (Get-Item -LiteralPath $current).Length -eq 0) {
            $current = $backup
        }
        if ((Get-FileHash -LiteralPath $current -Algorithm SHA256).Hash -ne $newRecord[0].Hash) {
            throw "缺少新版原文件 $name；请先通过 Steam 验证游戏文件，不能用旧资源代替。"
        }
        $sources[$name] = $current
        $rawBackup = Join-Path $BackupDir $name
        if ((Test-Path -LiteralPath $rawBackup) -and
            (Get-FileHash -LiteralPath $rawBackup -Algorithm SHA256).Hash -ne $oldRecord[0].Hash) {
            throw "旧备份存在不一致文件：$name"
        }
    }
    if ($old.HadDat -and (-not (Test-Path -LiteralPath (Join-Path $BackupDir 'original.dat')) -or
        (Get-FileHash -LiteralPath (Join-Path $BackupDir 'original.dat') -Algorithm SHA256).Hash -ne $old.DatHash)) {
        throw '原有文字表备份损坏；未改动客户端。'
    }
    if (Test-Path -LiteralPath $DatPath) {
        $known = @($PayloadInfo.PreviousFiles | Where-Object Language -eq $Language | ForEach-Object SHA256)
        $known += @($PayloadInfo.Files | Where-Object Language -eq $Language | ForEach-Object SHA256)
        if ($old.HadDat) { $known += $old.DatHash }
        if ((Get-FileHash -LiteralPath $DatPath -Algorithm SHA256).Hash -notin $known) {
            throw '现有文字表来源不明，未覆盖；请先检查该文件。'
        }
    }
    $id = [Guid]::NewGuid().ToString('N')
    $parent = Join-Path $Root 'Aion2_Text_Backup'
    $stage = Join-Path $parent ("Staging-" + $id)
    $history = Join-Path $parent 'History'
    $archive = Join-Path $history ("$Language-" + $id)
    # 所有目录移动均限定在本客户端的备份根目录内。
    $boundary = [IO.Path]::GetFullPath($parent).TrimEnd('\') + '\'
    foreach ($path in @($BackupDir, $stage, $archive)) {
        if (-not [IO.Path]::GetFullPath($path).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) { throw '备份路径不合法。' }
    }
    if ((Get-Item -LiteralPath $BackupDir).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '备份目录不能是链接。' }
    New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
    foreach ($name in $Names) {
        $dest = Join-Path $stage ($name + '.bak')
        Copy-Item -LiteralPath $sources[$name] -Destination $dest
        if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne ($expected | Where-Object Name -eq $name).Hash) {
            throw "新版备份复制校验失败：$name"
        }
    }
    if ($old.HadDat) { Copy-Item -LiteralPath (Join-Path $BackupDir 'original.dat') -Destination (Join-Path $stage 'original.dat') }
    [pscustomobject]@{ Language=$Language; BuildId=$BuildId; Files=$expected; HadDat=$old.HadDat; DatHash=$old.DatHash } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage 'state.json') -Encoding UTF8
    # 历史备份同样使用 .bak，避免被游戏当作可挂载资源。
    foreach ($name in $Names) {
        $raw = Join-Path $BackupDir $name
        $safe = Join-Path $BackupDir ($name + '.bak')
        if (Test-Path -LiteralPath $raw) {
            if (Test-Path -LiteralPath $safe) { Remove-Item -LiteralPath $raw }
            else { Move-Item -LiteralPath $raw -Destination $safe }
        }
    }
    New-Item -ItemType Directory -Path $history -Force | Out-Null
    Move-Item -LiteralPath $BackupDir -Destination $archive
    try { Move-Item -LiteralPath $stage -Destination $BackupDir }
    catch { Move-Item -LiteralPath $archive -Destination $BackupDir; throw }
}

function Invoke-TextPatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GameRoot,
        [Parameter(Mandatory)][ValidateSet('en-US', 'ja-JP', 'ko-KR')][string]$TargetLanguage,
        [Parameter(Mandatory)][ValidateSet('Install', 'Restore')][string]$Action,
        [string]$SourceDir
    )

    $ErrorActionPreference = 'Stop'
    if ($Action -eq 'Install' -and $TargetLanguage -ne 'ja-JP') {
        throw '当前版本仅提供日文入口汉化；旧版英文、韩文汉化可使用还原操作。'
    }
    $target = Get-TextTarget $TargetLanguage
    $root = (Resolve-Path -LiteralPath $GameRoot).ProviderPath.TrimEnd('\')
    $pakDir = Join-Path $root "Aion2\Content\Paks\L10N\Text\$TargetLanguage"
    if (-not (Test-Path -LiteralPath $pakDir -PathType Container)) {
        throw "客户端缺少 $TargetLanguage 文字资源：$pakDir"
    }
    if (Get-Process -Name Aion2, Aion2-Win64-Shipping -ErrorAction SilentlyContinue) {
        throw '请完全关闭 AION 2 后再安装或还原。'
    }
    $looseDir = Join-Path $root "Aion2\Content\L10N\Text\$TargetLanguage"
    $datPath = Join-Path $looseDir 'L10NString.dat'
    $stem = "pakchunk$($target.Chunk)-Windows_0_P"
    $names = @(@('pak', 'sig', 'ucas', 'utoc') | ForEach-Object { "$stem.$_" })
    $backupDir = Join-Path $root "Aion2_Text_Backup\$TargetLanguage"
    $statePath = Join-Path $backupDir 'state.json'
    $buildId = ''
    $steamApps = Split-Path (Split-Path $root -Parent) -Parent
    foreach ($appId in @('3393110', '4972320')) {
        $manifestPath = Join-Path $steamApps "appmanifest_$appId.acf"
        if (Test-Path -LiteralPath $manifestPath) {
            $manifestText = Get-Content -LiteralPath $manifestPath -Raw
            $folderName = Split-Path $root -Leaf
            if ($manifestText -match ('"installdir"\s+"' + [regex]::Escape($folderName) + '"') -and
                $manifestText -match '"buildid"\s+"([^"]+)"') {
                $buildId = $Matches[1]
                break
            }
        }
    }

    if ($Action -eq 'Install') {
        $srcDat = Join-Path $SourceDir 'L10NString.dat'
        if ($TargetLanguage -ne 'en-US') { $srcDat = Join-Path (Join-Path $SourceDir $TargetLanguage) 'L10NString.dat' }
        if (-not (Test-Path -LiteralPath $srcDat -PathType Leaf) -or (Get-Item -LiteralPath $srcDat).Length -lt 1000) {
            throw "中文数据表缺失或不完整：$srcDat"
        }
        $sourceBytes = [IO.File]::ReadAllBytes($srcDat)
        # L10N v2 的文件头使用语言相关掩码；正文也须按该语言重新编码。
        $header = New-Object byte[] 16
        for ($i = 0; $i -lt 16; $i++) {
            $header[$i] = $sourceBytes[4 + $i] -bxor [Convert]::ToByte($target.HeaderMask.Substring($i * 2, 2), 16)
        }
        $packed = [BitConverter]::ToInt32($header, 0)
        $mode = [BitConverter]::ToInt32($header, 4)
        $aligned = [BitConverter]::ToInt32($header, 8)
        $rawSize = [BitConverter]::ToInt32($header, 12)
        if ([BitConverter]::ToInt32($sourceBytes, 0) -ne 2 -or $mode -ne 2 -or $packed -le 0 -or
            $aligned -lt ([long]$packed + 32) -or $aligned % 16 -ne 0 -or $rawSize -le 0 -or
            ([long]$aligned + 20) -ne $sourceBytes.Length) {
            throw "汉化文件头不适用于 $TargetLanguage；请使用该语言专用数据。"
        }
        $payloadInfoPath = Join-Path $SourceDir 'payloads.json'
        if (-not (Test-Path -LiteralPath $payloadInfoPath)) { throw '缺少汉化数据校验信息，请完整解压工具包。' }
        $payloadInfo = Get-Content -LiteralPath $payloadInfoPath -Raw | ConvertFrom-Json
        $payloadRecord = @($payloadInfo.Files | Where-Object Language -eq $TargetLanguage)
        $sourceHash = (Get-FileHash -LiteralPath $srcDat -Algorithm SHA256).Hash
        if ($payloadRecord.Count -ne 1 -or $payloadRecord[0].SHA256 -ne $sourceHash) {
            throw '汉化数据校验失败；请重新解压完整工具包。'
        }
        if ($buildId -and $buildId -ne $payloadInfo.SteamBuildId) {
            throw '游戏已更新，当前汉化数据尚未验证适配该 Steam 版本；请更新汉化包。'
        }
        if ($buildId -and (Test-Path -LiteralPath $statePath)) {
            $previousState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            if ($previousState.BuildId -and $previousState.BuildId -ne $buildId) {
                Update-TextBackupForBuild $root $pakDir $datPath $backupDir $TargetLanguage $buildId $names $payloadInfo
            }
        }
    }
    # 兼容原项目已经安装的英文汉化；旧备份没有版本记录，保留原目录。
    $legacyDir = Join-Path $root 'Aion2_English_Backup_Safe'
    $pakPath = Join-Path $pakDir "$stem.pak"
    $useLegacy = $TargetLanguage -eq 'en-US' -and -not (Test-Path -LiteralPath $backupDir) -and
        (Test-Path -LiteralPath $legacyDir -PathType Container) -and
        ($Action -eq 'Restore' -or ((Test-Path -LiteralPath $pakPath) -and (Get-Item -LiteralPath $pakPath).Length -eq 0))
    if ($useLegacy) {
        $backupDir = $legacyDir
        $records = @(foreach ($name in $names) {
            $backup = Get-TextBackupFile $backupDir $name
            if (-not (Test-Path -LiteralPath $backup -PathType Leaf) -or (Get-Item -LiteralPath $backup).Length -eq 0) {
                throw "旧版英文备份不完整：$name；未改动客户端。"
            }
            [pscustomobject]@{ Name = $name; Hash = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash }
        })
        $state = [pscustomobject]@{ Language = 'en-US'; BuildId = ''; Files = $records; HadDat = $false; DatHash = '' }
    } elseif (-not (Test-Path -LiteralPath $statePath)) {
        if ($Action -eq 'Restore') { throw "没有 $($target.Name) 的完整备份，未改动客户端。" }
        if (Test-Path -LiteralPath $backupDir) { throw "备份目录不完整，请先检查：$backupDir" }
        foreach ($name in $names) {
            $file = Join-Path $pakDir $name
            if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -eq 0) {
                throw "无法备份原版资源 $name；请先通过启动器验证游戏文件。"
            }
        }
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        $records = @(foreach ($name in $names) {
            $original = Join-Path $pakDir $name
            $backup = Join-Path $backupDir ($name + '.bak')
            Copy-Item -LiteralPath $original -Destination $backup
            $hash = (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
            if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $hash) { throw "备份校验失败：$name" }
            [pscustomobject]@{ Name = $name; Hash = $hash }
        })
        $hadDat = Test-Path -LiteralPath $datPath -PathType Leaf
        $datHash = ''
        if ($hadDat) {
            Copy-Item -LiteralPath $datPath -Destination (Join-Path $backupDir 'original.dat')
            $datHash = (Get-FileHash -LiteralPath $datPath -Algorithm SHA256).Hash
            if ((Get-FileHash -LiteralPath (Join-Path $backupDir 'original.dat') -Algorithm SHA256).Hash -ne $datHash) {
                throw '原有文字表备份校验失败。'
            }
        }
        [pscustomobject]@{
            Language = $TargetLanguage; BuildId = $buildId; Files = $records
            HadDat = [bool]$hadDat; DatHash = $datHash
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding UTF8
    }

    if (-not $useLegacy) { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json }
    if ($state.Language -ne $TargetLanguage -or @($state.Files).Count -ne 4 -or $state.HadDat -isnot [bool]) {
        throw "备份记录不匹配：$statePath"
    }
    if ($buildId -and $state.BuildId -and $buildId -ne $state.BuildId) {
        throw '游戏已更新，旧备份不能用于当前版本。请先验证游戏文件，移走对应语言旧备份，再使用匹配版本的汉化数据。'
    }
    if ($state.BuildId -and -not $buildId) {
        throw '无法读取当前 Steam 游戏版本，不能确认备份适用性；请检查游戏库清单。'
    }
    foreach ($name in $names) {
        $record = @($state.Files | Where-Object { $_.Name -eq $name })
        $backup = Get-TextBackupFile $backupDir $name
        if ($record.Count -ne 1 -or -not (Test-Path -LiteralPath $backup -PathType Leaf) -or
            (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $record[0].Hash) {
            throw "备份损坏或不完整：$name；未改动客户端。"
        }
    }
    if ($state.HadDat -and (-not (Test-Path -LiteralPath (Join-Path $backupDir 'original.dat')) -or
        (Get-FileHash -LiteralPath (Join-Path $backupDir 'original.dat') -Algorithm SHA256).Hash -ne $state.DatHash)) {
        throw '原有文字表备份损坏；未改动客户端。'
    }
    foreach ($name in $names) {
        $path = Join-Path $pakDir $name
        if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 0 -and
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne ($state.Files | Where-Object Name -eq $name).Hash) {
            throw '当前语言资源与备份版本不一致；请先验证游戏文件并检查对应语言备份。'
        }
    }

    # 清理早期测试版登记过的附加包；未知文件保持不动。
    $switchPak = Join-Path $root "Aion2\Content\Paks\Aion2_CN_Text_${TargetLanguage}_1_P.pak"
    $switchStatePath = Join-Path $backupDir 'switch-pak.json'
    $switchState = $null
    if (Test-Path -LiteralPath $switchStatePath) {
        $switchState = Get-Content -LiteralPath $switchStatePath -Raw | ConvertFrom-Json
        if ($switchState.Language -ne $TargetLanguage -or @($switchState.Hashes).Count -lt 1 -or
            @($switchState.Hashes | Where-Object { $_ -notmatch '^[0-9A-Fa-f]{64}$' }).Count -gt 0) {
            throw '语言切换补丁记录损坏；未改动客户端。'
        }
        if ($switchState.BuildId -and $switchState.BuildId -ne $buildId) {
            throw '游戏版本与语言切换补丁记录不一致；请先核验游戏文件和备份。'
        }
    }
    if (Test-Path -LiteralPath $switchPak) {
        if (-not $switchState -or (Get-FileHash -LiteralPath $switchPak -Algorithm SHA256).Hash -notin $switchState.Hashes) {
            throw "语言切换补丁不属于当前备份记录，未覆盖或删除：$switchPak"
        }
    }
    # 旧英文备份也会被跨语言扫描，需要一并隔离。
    Convert-LegacyTextBackupExtensions -Root $root
    # 备份使用 .bak 扩展名，避免切换语言时被扫描为可加载的游戏资源。
    foreach ($name in $names) {
        $oldBackup = Join-Path $backupDir $name
        if (Test-Path -LiteralPath $oldBackup) {
            if ((Get-FileHash -LiteralPath $oldBackup -Algorithm SHA256).Hash -ne
                ($state.Files | Where-Object Name -eq $name).Hash) { throw "备份损坏或不完整：$name；未改动客户端。" }
        }
    }
    foreach ($name in $names) {
        $oldBackup = Join-Path $backupDir $name
        $safeBackup = Join-Path $backupDir ($name + '.bak')
        if (Test-Path -LiteralPath $oldBackup) {
            if (Test-Path -LiteralPath $safeBackup) { Remove-Item -LiteralPath $oldBackup }
            else { Move-Item -LiteralPath $oldBackup -Destination $safeBackup }
        }
    }

    # 记录将要修改的文件，写入失败时恢复到本次操作前。
    $before = @{}
    $paths = @($names | ForEach-Object { Join-Path $pakDir $_ }) + @($datPath, $switchPak)
    foreach ($path in $paths) {
        $before[$path] = if (Test-Path -LiteralPath $path -PathType Leaf) {
            @{ Bytes = [IO.File]::ReadAllBytes($path); Hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
        } else { $null }
    }
    try {
        if (Test-Path -LiteralPath $switchPak) { Remove-Item -LiteralPath $switchPak -Force }
        if ($Action -eq 'Install') {
            New-Item -ItemType Directory -Path $looseDir -Force | Out-Null
            [IO.File]::WriteAllBytes($datPath, $sourceBytes)
            foreach ($extension in @('sig', 'ucas', 'utoc')) {
                $path = Join-Path $pakDir "$stem.$extension"
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
            }
            [IO.File]::WriteAllBytes($pakPath, [byte[]]@())
            if ((Get-FileHash -LiteralPath $datPath -Algorithm SHA256).Hash -ne
                $sourceHash) { throw '中文数据写入校验失败。' }
        } else {
            foreach ($name in $names) {
                Copy-Item -LiteralPath (Get-TextBackupFile $backupDir $name) -Destination (Join-Path $pakDir $name) -Force
            }
            if ($state.HadDat) {
                New-Item -ItemType Directory -Path $looseDir -Force | Out-Null
                Copy-Item -LiteralPath (Join-Path $backupDir 'original.dat') -Destination $datPath -Force
            } elseif (Test-Path -LiteralPath $datPath) {
                Remove-Item -LiteralPath $datPath -Force
            }
            foreach ($name in $names) {
                if ((Get-FileHash -LiteralPath (Join-Path $pakDir $name) -Algorithm SHA256).Hash -ne
                    ($state.Files | Where-Object Name -eq $name).Hash) { throw "还原校验失败：$name" }
            }
            if ($state.HadDat) {
                if ((Get-FileHash -LiteralPath $datPath -Algorithm SHA256).Hash -ne $state.DatHash) { throw '原有文字表还原校验失败。' }
            } elseif (Test-Path -LiteralPath $datPath) { throw '汉化数据表未能移除。' }
        }
    } catch {
        $failure = $_.Exception.Message
        $rollbackErrors = @()
        foreach ($path in $paths) {
            try {
                if ($null -eq $before[$path]) {
                    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
                } elseif (-not (Test-Path -LiteralPath $path) -or
                    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $before[$path].Hash) {
                    [IO.File]::WriteAllBytes($path, $before[$path].Bytes)
                }
            } catch { $rollbackErrors += $path }
        }
        if ($rollbackErrors.Count) { throw "$failure；部分文件未能自动恢复，请使用备份 $backupDir 还原。" }
        throw "$failure；已恢复到本次操作前的文件状态。"
    }
    [pscustomobject]@{ Action = $Action; Language = $TargetLanguage; Backup = $backupDir; Setting = $target.Setting; LegacyBackup = $useLegacy }
}
