function Invoke-PackedJapanesePatch {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateSet('Install','Restore')][string]$Action,
        [Parameter(Mandatory=$true)][string]$GamePath,
        [ValidateSet('zh','zh-TW')][string]$Variant='zh',
        [Parameter(Mandatory=$true)][string]$ProjectRoot)
    $ErrorActionPreference='Stop'
    function Hash($p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
    function Check($p,$hash,$size=-1) {
        if (-not [IO.File]::Exists($p)) { throw "缺少文件：$p" }
        if ($size -ge 0 -and (Get-Item -LiteralPath $p).Length -ne $size) { throw "长度不符：$p" }
        if ((Hash $p) -ne $hash) { throw "校验失败：$p" }
    }
    function Child($root,$relative) {
        $base=[IO.Path]::GetFullPath($root).TrimEnd('\')
        $p=[IO.Path]::GetFullPath((Join-Path $base $relative))
        if (-not $p.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)) { throw '文件路径越界。' }
        $walk=$p
        while ($walk -and $walk.Length -ge $base.Length) {
            if ((Test-Path -LiteralPath $walk) -and ((Get-Item -LiteralPath $walk -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '路径不能包含链接。' }
            if ($walk -eq $base) { break }; $walk=Split-Path $walk -Parent
        }
        $p
    }
    function WriteRegion($destination,$offset,$bytes) {
        $f=[IO.File]::Open($destination,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { if ($offset -lt 0 -or $offset+$bytes.Length -gt $f.Length) { throw '补丁区域越界。' }; $f.Position=$offset;$f.Write($bytes,0,$bytes.Length);$f.Flush($true) } finally {$f.Dispose()}
    }
    $game=[IO.Path]::GetFullPath($GamePath).TrimEnd('\')
    if (Get-Process -Name 'Aion2','Aion2-Win64-Shipping' -ErrorAction SilentlyContinue) { throw '请完全退出游戏。' }
    $steamapps=Split-Path (Split-Path $game -Parent) -Parent
    $acfPath=Join-Path $steamapps 'appmanifest_3393110.acf'
    if (-not (Test-Path -LiteralPath $acfPath -PathType Leaf)) { throw '当前版本仅支持已适配的 Steam 客户端。' }
    $acf=Get-Content -LiteralPath $acfPath -Raw
    if ($acf -notmatch '"buildid"\s+"26429009"') { throw '当前Steam build不是26429009，请先核对游戏版本。' }
    $source=Child $ProjectRoot $Variant
    $meta=Get-Content -LiteralPath (Join-Path $source 'payloads.json') -Raw|ConvertFrom-Json
    if ($meta.InstallationMode -ne 'PackedFontAlias' -or $meta.SteamBuildId -ne '26429009') { throw '安装数据模式或build不匹配。' }
    if ($meta.FontPatchManifest -ne ('font/'+$Variant+'/manifest.json')) { throw '字体清单路径不匹配。' }
    $fontPath=Child $ProjectRoot $meta.FontPatchManifest
    $font=Get-Content -LiteralPath $fontPath -Raw|ConvertFrom-Json
    if ($font.SchemaVersion -ne 1) { throw '不支持的字体清单版本。' }
    $backup=Child $game 'Aion2_Text_Backup/ja-JP/PackedFontAlias'
    $statePath=Join-Path $backup 'state.json'
    $records=@();$pakRelative='Aion2/Content/Paks/L10N/Text/ja-JP/'
    foreach ($r in $meta.OriginalFiles.'ja-JP') {
        if ($r.Name -notmatch '^pakchunk503000-Windows_0_P\.(pak|sig|ucas|utoc)$') { throw '原资源文件名不合法。' }
        $records+= [pscustomobject]@{Relative=$pakRelative+$r.Name;Hash=$r.Hash;Size=$r.Size;Backup=$r.Name+'.bak'}
    }
    if ($records.Count -ne 4 -or @($records.Relative|Select-Object -Unique).Count -ne 4) { throw '必须提供四个原日文资源。' }
    $records+=[pscustomobject]@{Relative=$font.OriginalFile.Path;Hash=$font.OriginalFile.SHA256;Size=$font.OriginalFile.Size;Backup='pakchunk0-Windows.pak.bak'}
    if ($font.OriginalFile.Path.Replace('\','/') -ne 'Aion2/Content/Paks/pakchunk0-Windows.pak') { throw '字体目标路径不合法。' }
    $knownFont=@();$knownPak=@();foreach($v in 'zh','zh-TW') {
        $mp=Child $ProjectRoot ($v+'/payloads.json')
        if (Test-Path -LiteralPath $mp) {
            $m=Get-Content -LiteralPath $mp -Raw|ConvertFrom-Json
            if ($m.SteamBuildId -eq '26429009' -and $m.InstallationMode -eq 'PackedFontAlias') {
                if ($m.FontPatchManifest -ne ('font/'+$v+'/manifest.json')) { throw '字体清单路径不匹配。' }
                $vf=Get-Content -LiteralPath (Child $ProjectRoot $m.FontPatchManifest) -Raw|ConvertFrom-Json
                if ($vf.SchemaVersion -ne 1 -or $vf.OriginalFile.Path -ne $font.OriginalFile.Path -or $vf.OriginalFile.SHA256 -ne $font.OriginalFile.SHA256 -or $vf.OriginalFile.Size -ne $font.OriginalFile.Size -or $vf.PatchedSHA256 -notmatch '^[0-9a-fA-F]{64}$') { throw '字体清单基线不匹配。' }
                $knownPak+= $m.PackedFile.SHA256;$knownFont+=$vf.PatchedSHA256
            }
        }
    }
    $state=$null
    if (Test-Path -LiteralPath $statePath) {
        $state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
        if ($state.SchemaVersion -ne 1 -or $state.BuildId -ne '26429009') { throw '备份版本不匹配，禁止覆盖新版资源。' }
        foreach($r in $records) {
            $s=@($state.Files|Where-Object {$_.Relative -eq $r.Relative -and $_.Hash -eq $r.Hash -and $_.Size -eq $r.Size -and $_.Backup -eq $r.Backup})
            if ($s.Count -ne 1) { throw '备份记录与当前清单不符。' }
            Check (Child $backup $r.Backup) $r.Hash $r.Size
        }
    } elseif ($Action -eq 'Restore') { throw '没有本模式可信备份。' }
    $legacyRoot=Child $game 'Aion2_Text_Backup/ja-JP'
    $legacyState=$null
    $needsLegacy=$false
    if(-not $state){foreach($r in $records|Where-Object {$_.Backup -ne 'pakchunk0-Windows.pak.bak'}){$active=Child $game $r.Relative;if(-not [IO.File]::Exists($active) -or ((Get-Item -LiteralPath $active).Length -eq 0)){$needsLegacy=$true}}}
    if ($needsLegacy -and (Test-Path -LiteralPath (Join-Path $legacyRoot 'state.json'))) {
        $legacyState=Get-Content -LiteralPath (Join-Path $legacyRoot 'state.json') -Raw|ConvertFrom-Json
        if ($legacyState.BuildId -ne '26429009' -or $legacyState.HadDat) { throw '旧备份版本或原外置文本状态不支持安全迁移。' }
        foreach($r in $records|Where-Object {$_.Backup -ne 'pakchunk0-Windows.pak.bak'}) {
            $old=@($legacyState.Files|Where-Object {$_.Name -eq [IO.Path]::GetFileName($r.Relative) -and $_.Hash -eq $r.Hash})
            if($old.Count -ne 1){throw '旧备份记录不匹配当前官方原件。'}
            Check (Child $legacyRoot $r.Backup) $r.Hash $r.Size
        }
    }
    # All active files must be original or one of this exact build's known outputs.
    foreach($r in $records) {
        $path=Child $game $r.Relative
        if (-not [IO.File]::Exists($path)) { if($legacyState -and $r.Backup -ne 'pakchunk0-Windows.pak.bak'){continue};throw '缺少当前新版原文件，请通过Steam验证；不能使用旧备份。' }
        if($legacyState -and $r.Backup -eq 'pakchunk503000-Windows_0_P.pak.bak' -and (Get-Item -LiteralPath $path).Length -eq 0){continue};$h=Hash $path;$allowed=@($r.Hash)
        if ($r.Backup -eq 'pakchunk503000-Windows_0_P.pak.bak') {$allowed+=$knownPak}
        if ($r.Backup -eq 'pakchunk0-Windows.pak.bak') {$allowed+=$knownFont}
        if ($allowed -notcontains $h) { throw "来源不明或版本不符：$path" }
        if (-not $state -and $h -ne $r.Hash) { throw '已有修改文件但缺少本模式可信备份，请恢复官方原版。' }
    }
    $loose=Child $game 'Aion2/Content/L10N/Text/ja-JP/L10NString.dat'
    $looseHash=$null;$looseArchive=$null;$looseMoved=$false
    if (Test-Path -LiteralPath $loose) {
        if ($Action -ne 'Install' -or -not [IO.File]::Exists($loose)) { throw '存在外置日文DAT，请保留并移出游戏文字目录后重试。' }
        $looseHash=Hash $loose
        $looseArchive=Child $backup ('ExternalText/L10NString.'+[guid]::NewGuid().ToString('N')+'.dat.bak')
    }
    if (-not $state) {
        New-Item -ItemType Directory -Path $backup -Force|Out-Null
        foreach($r in $records) {
            $bp=Child $backup $r.Backup
            if (Test-Path -LiteralPath $bp) { Check $bp $r.Hash $r.Size }
            else { $origin=Child $game $r.Relative;if($legacyState -and $r.Backup -ne 'pakchunk0-Windows.pak.bak'){$origin=Child $legacyRoot $r.Backup};Copy-Item -LiteralPath $origin -Destination $bp;Check $bp $r.Hash $r.Size }
        }
        $state=[pscustomobject]@{SchemaVersion=1;BuildId='26429009';Files=$records}
        $state|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $statePath -Encoding UTF8
    }
    $stages=@();$committed=@();$temporary=@();$rollbackErrors=@()
    try {
        foreach($r in $records) {
            $target=Child $game $r.Relative
            $stage=$target+'.'+[guid]::NewGuid().ToString('N')+'.stage.bak'
            $undo=$target+'.'+[guid]::NewGuid().ToString('N')+'.rollback.bak'
            $temporary+=$stage;$temporary+=$undo
            Copy-Item -LiteralPath (Child $backup $r.Backup) -Destination $stage
            $expected=$r.Hash
            if ($Action -eq 'Install' -and $r.Backup -eq 'pakchunk503000-Windows_0_P.pak.bak') {
                $f=$meta.PackedFile
                if ($f.PayloadOffset -ne 53 -or $f.PayloadLength -ne 3836404 -or $f.PayloadHashOffset -ne 28 -or $f.Size -ne 3836918) { throw '不支持的日文包布局。' }
                $dat=Child $source 'ja-JP/L10NString.dat';$payload=@($meta.Files|Where-Object Language -eq 'ja-JP')
                if ($payload.Count -ne 1) { throw '日文payload记录不唯一。' };Check $dat $payload[0].SHA256 $f.PayloadLength
                $bytes=[IO.File]::ReadAllBytes($dat);WriteRegion $stage 53 $bytes
                $sha=[Security.Cryptography.SHA1]::Create();try {$digest=$sha.ComputeHash($bytes)} finally {$sha.Dispose()};WriteRegion $stage 28 $digest
                $expected=$f.SHA256;Check $stage $expected $f.Size
            }
            if ($Action -eq 'Install' -and $r.Backup -eq 'pakchunk0-Windows.pak.bak') {
                $lastEnd=0
                foreach($region in @($font.Regions|Sort-Object Offset)) {
                    if ($region.Offset -lt $lastEnd -or $region.Length -le 0 -or $region.Length -gt 1048576 -or $region.Offset+$region.Length -gt $r.Size) { throw '字体补丁区域重叠或越界。' }
                    $lastEnd=$region.Offset+$region.Length
                    $stream=[IO.File]::OpenRead($stage);try {$stream.Position=$region.Offset;$before=New-Object byte[] $region.Length;$read=0;while($read -lt $before.Length){$n=$stream.Read($before,$read,$before.Length-$read);if(-not $n){throw '读取区域失败。'};$read+=$n}}finally{$stream.Dispose()}
                    $sha=[Security.Cryptography.SHA256]::Create();try{$bh=([BitConverter]::ToString($sha.ComputeHash($before))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
                    if ($bh -ne $region.BeforeSHA256) {throw '字体原区域校验失败。'}
                    $patch=Child $ProjectRoot $region.DataFile;Check $patch $region.AfterSHA256 $region.Length
                    WriteRegion $stage $region.Offset ([IO.File]::ReadAllBytes($patch))
                }
                $expected=$font.PatchedSHA256
            }
            Check $stage $expected $r.Size
            $stages+=[pscustomobject]@{Target=$target;Stage=$stage;Undo=$undo;Expected=$expected;Before=$(if([IO.File]::Exists($target)){Hash $target}else{$null})}
        }
        if (Get-Process -Name 'Aion2','Aion2-Win64-Shipping' -ErrorAction SilentlyContinue) { throw '游戏已启动，操作取消。' }
        foreach($s in $stages) {if($(if([IO.File]::Exists($s.Target)){Hash $s.Target}else{$null}) -ne $s.Before){throw '操作期间文件发生变化。'}}
        if ($looseHash) {
            Check $loose $looseHash
            New-Item -ItemType Directory -Path (Split-Path $looseArchive -Parent) -Force|Out-Null
            [IO.File]::Move($loose,$looseArchive);$looseMoved=$true
            Check $looseArchive $looseHash
        } elseif (Test-Path -LiteralPath $loose) { throw '操作期间出现外置文字表，请重新安装。' }
        foreach($s in $stages) {
            if($null -eq $s.Before){[IO.File]::Move($s.Stage,$s.Target)}else{[IO.File]::Replace($s.Stage,$s.Target,$s.Undo)}
            $committed+=$s
            Check $s.Target $s.Expected
        }
    } catch {
        $failure=$_;$rollbackErrors=@()
        for($i=$committed.Count-1;$i -ge 0;$i--) {
            $s=$committed[$i]
            try {if($null -eq $s.Before){Remove-Item -LiteralPath $s.Target -Force}else{Copy-Item -LiteralPath $s.Undo -Destination $s.Target -Force;Check $s.Target $s.Before}} catch {$rollbackErrors+=$_.Exception.Message}
        }
        if ($looseMoved) {
            try {[IO.File]::Move($looseArchive,$loose);Check $loose $looseHash} catch {$rollbackErrors+=$_.Exception.Message}
        }
        if($rollbackErrors.Count){throw ('操作失败且回滚不完整，请保留rollback.bak和ExternalText备份：'+($rollbackErrors -join '; '))}
        throw $failure
    } finally {
        # Retain rollback files if rollback was incomplete; clean only known owned files otherwise.
        foreach($p in $temporary) {if([IO.File]::Exists($p) -and ($p -notlike '*.rollback.bak' -or -not $rollbackErrors.Count)){Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}}
    }
    [pscustomobject]@{Action=$Action;Language='ja-JP';Backup=$backup;Setting='日本語';LegacyBackup=$false;ArchivedText=$looseArchive}
}
