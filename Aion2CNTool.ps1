# -*- coding: utf-8 -*-
# AION 2 (Steam / PURPLE 正式版) 简繁双语一键汉化与还原工具
# 原作者: B站@吃素的佩奇
# 二次升级作者: Foohi
# 原项目: https://github.com/duoluoyuji/Aion2-Steam-CN
# 项目主页: https://github.com/Foohi666/Aion2-CN-Foohi

param(
    [switch]$Install,
    [switch]$Restore,
    [string]$Lang = "",
    [ValidateSet('en-US', 'ja-JP', 'ko-KR')][string]$TargetLanguage = 'en-US'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ToolDir        = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
. (Join-Path $ToolDir 'TextPatch.ps1')
. (Join-Path $ToolDir 'Update.ps1')
$VersionInfo = Get-Content -LiteralPath (Join-Path $ToolDir 'version.json') -Raw | ConvertFrom-Json
$ZhDir          = Join-Path $ToolDir 'zh'
$ZhTwDir        = Join-Path $ToolDir 'zh-TW'
$LangName       = '简体中文'
$ActiveSourceDir = $ZhDir
if ($Lang -eq 'zh-TW' -or $Lang -eq 'tw' -or $Lang -eq 'cht') {
    $ActiveSourceDir = $ZhTwDir
    $LangName = '繁体中文'
}
$CurrentVersion = [string]$VersionInfo.version
# 3393110 为 Steam 正式服 AppID，4972320 为 Steam Playtest 测试服 AppID
$AppIds         = @('3393110', '4972320')

# ==================== 控制台作者署名横幅 ====================
function Show-Banner {
    Write-Host "========================================================================" -ForegroundColor Magenta
    Write-Host "      AION 2 (Steam / PURPLE 正式版) 简繁双语一键汉化工具 v$CurrentVersion" -ForegroundColor Cyan
    Write-Host "      原作者：B站@吃素的佩奇 | 二次升级作者：Foohi" -ForegroundColor Gray
    Write-Host "      项目主页: https://github.com/Foohi666/Aion2-CN-Foohi" -ForegroundColor Gray
    Write-Host "      【声明】本工具完全免费分享，仅供交流学习，严禁倒卖牟利！" -ForegroundColor Red
    Write-Host "========================================================================" -ForegroundColor Magenta
    Write-Host ""
}

# ==================== 扫描全盘所有已安装的 AION 2 版本 ====================
function Get-AllGameRoots {
    $detected = @()
    $fixedDrives = (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null -and $_.Root }).Root

    # ---------------- 1. 扫描 Steam 游戏库 ----------------
    $steamRoots = @()
    foreach ($d in $fixedDrives) {
        $candidates = @(
            (Join-Path $d 'SteamLibrary\steamapps'),
            (Join-Path $d 'steamapps'),
            (Join-Path $d 'Program Files (x86)\Steam\steamapps'),
            (Join-Path $d 'Program Files\Steam\steamapps'),
            (Join-Path $d 'Steam\steamapps')
        )
        foreach ($c in $candidates) {
            if (Test-Path $c) { $steamRoots += $c }
        }
    }

    try {
        $reg = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
        if ($reg -and $reg.SteamPath) {
            $regApps = Join-Path $reg.SteamPath 'steamapps'
            if (Test-Path $regApps) { $steamRoots += $regApps }
        }
    } catch {}

    $steamRoots = $steamRoots | Select-Object -Unique

    foreach ($r in $steamRoots) {
        foreach ($aid in $AppIds) {
            $acf = Join-Path $r "appmanifest_$aid.acf"
            if (Test-Path $acf) {
                try {
                    $txt = Get-Content $acf -Raw -ErrorAction SilentlyContinue
                    if ($txt -match '"installdir"\s+"([^"]+)"') {
                        $gameAbs = Join-Path (Join-Path $r 'common') $matches[1]
                        if (Test-Path (Join-Path $gameAbs 'Aion2\Content\Paks\L10N')) {
                            $label = if ($aid -eq '3393110') { "Steam 国际正式版" } else { "Steam 测试服版" }
                            if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $gameAbs.ToLower() })) {
                                $detected += [PSCustomObject]@{
                                    Platform = $label
                                    Path     = $gameAbs
                                    Type     = "Steam"
                                }
                            }
                        }
                    }
                } catch {}
            }
        }

        $common = Join-Path $r 'common'
        if (Test-Path $common) {
            $hits = Get-ChildItem $common -Directory -ErrorAction SilentlyContinue | Where-Object {
                Test-Path (Join-Path $_.FullName 'Aion2\Content\Paks\L10N')
            }
            foreach ($h in $hits) {
                if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $h.FullName.ToLower() })) {
                    $detected += [PSCustomObject]@{
                        Platform = "Steam 游戏库 ($($h.Name))"
                        Path     = $h.FullName
                        Type     = "Steam"
                    }
                }
            }
        }
    }

    # ---------------- 2. 三重增强：扫描 NCSoft PURPLE (紫P) 客户端 ----------------
    # 增强 1：从 plaync 官方注册表枚举 BaseDir
    $playncRegKeys = @(
        "HKLM:\SOFTWARE\plaync",
        "HKLM:\SOFTWARE\WOW6432Node\plaync",
        "HKCU:\SOFTWARE\plaync"
    )
    foreach ($rk in $playncRegKeys) {
        try {
            if (Test-Path $rk) {
                $subKeys = Get-ChildItem -Path $rk -ErrorAction SilentlyContinue
                foreach ($sk in $subKeys) {
                    $props = Get-ItemProperty -Path $sk.PSPath -ErrorAction SilentlyContinue
                    if ($props -and $props.BaseDir) {
                        $bPath = $props.BaseDir.ToString().TrimEnd('\')
                        if (Test-Path (Join-Path $bPath 'Aion2\Content\Paks\L10N')) {
                            if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $bPath.ToLower() })) {
                                $detected += [PSCustomObject]@{
                                    Platform = "NCSoft PURPLE 国际服 (注册表定位)"
                                    Path     = $bPath
                                    Type     = "PURPLE"
                                }
                            }
                        }
                    }
                }
            }
        } catch {}
    }

    # 增强 2：从 Windows 软件卸载列表中精确匹配 AION 2 / PURPLE 安装目录
    $uninstallRegKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($uk in $uninstallRegKeys) {
        try {
            if (Test-Path $uk) {
                $subKeys = Get-ChildItem -Path $uk -ErrorAction SilentlyContinue
                foreach ($sk in $subKeys) {
                    $props = Get-ItemProperty -Path $sk.PSPath -ErrorAction SilentlyContinue
                    if ($props) {
                        $dName = $props.DisplayName
                        $iLoc = $props.InstallLocation
                        if ($dName -and ($dName -like "*AION*" -or $dName -like "*Purple*") -and $iLoc) {
                            $cleanLoc = $iLoc.ToString().TrimEnd('\')
                            if (Test-Path (Join-Path $cleanLoc 'Aion2\Content\Paks\L10N')) {
                                if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $cleanLoc.ToLower() })) {
                                    $detected += [PSCustomObject]@{
                                        Platform = "NCSoft PURPLE 国际服 (系统识别)"
                                        Path     = $cleanLoc
                                        Type     = "PURPLE"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch {}
    }

    # 增强 3：全盘常见默认路径深度匹配池
    foreach ($d in $fixedDrives) {
        $purpleCandidates = @(
            (Join-Path $d 'AION 2'),
            (Join-Path $d 'Aion2'),
            (Join-Path $d 'Games\AION 2'),
            (Join-Path $d 'Games\Aion2'),
            (Join-Path $d 'PurpleGames\AION 2'),
            (Join-Path $d 'PurpleGames\Aion2'),
            (Join-Path $d 'Purple\Games\AION 2'),
            (Join-Path $d 'NC\AION 2'),
            (Join-Path $d 'NCSOFT\AION 2'),
            (Join-Path $d 'NCSOFT\Purple\Games\AION 2'),
            (Join-Path $d 'Program Files\NCSOFT\Purple\AION 2'),
            (Join-Path $d 'Program Files (x86)\NCSOFT\Purple\AION 2')
        )
        foreach ($pc in $purpleCandidates) {
            if (Test-Path (Join-Path $pc 'Aion2\Content\Paks\L10N')) {
                if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $pc.ToLower() })) {
                    $detected += [PSCustomObject]@{
                        Platform = "NCSoft PURPLE 国际服 (磁盘扫描)"
                        Path     = $pc
                        Type     = "PURPLE"
                    }
                }
            }
        }
    }

    return $detected
}

# 手动选择游戏目录保底
function Select-GameFolder {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "未自动检测到游戏安装位置。`n请手动选择 AION 2 游戏根目录（包含 Aion2 文件夹的那一层，名字通常为 AION 2 或 AION 2 Playtest）："
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -eq 'OK') {
        $sel = $dlg.SelectedPath
        if (Test-Path (Join-Path $sel 'Aion2\Content\Paks\L10N')) {
            return $sel
        } else {
            [System.Windows.Forms.MessageBox]::Show("所选目录不是有效的 AION 2 游戏根目录！`n该目录下必须包含 Aion2 文件夹。", "错误 - B站@吃素的佩奇", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return $null
        }
    }
    return $null
}

# ==================== 智能版本决策与多版本选择窗口 ====================
function Select-TargetGameRoots {
    param([string]$ActionName = "汉化")

    $all = @(Get-AllGameRoots)

    # 场景 0: 全盘未搜到任何版本 -> 弹窗手动选择
    if ($all.Count -eq 0) {
        Write-Host "未能自动定位到游戏安装路径，请在弹出的窗口中手动指定..." -ForegroundColor Yellow
        $manual = Select-GameFolder
        if ($manual) {
            return @($manual)
        }
        return @()
    }

    # 场景 1: 只检测到 1 个版本 -> 直接自动采用，无需用户费神多点一次
    if ($all.Count -eq 1) {
        Write-Host "-> 检测到唯一安装版本: $($all[0].Platform) [$($all[0].Path)]" -ForegroundColor Green
        return @($all[0].Path)
    }

    # 场景 2: 检测到 2 个或以上不同版本 (例如同时存在 Steam 与 PURPLE) -> 弹出交互窗口让用户勾选
    Write-Host ">>> 检测到电脑中安装了多个不同版本的 AION 2 ($($all.Count) 个)，正在弹出选择窗口..." -ForegroundColor Cyan

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "AION 2 游戏版本选择 - B站@吃素的佩奇"
    $formHeight = 310 + ($all.Count * 45)
    $form.Size = New-Object System.Drawing.Size(650, $formHeight)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 28)
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)

    # 顶部横幅
    $banner = New-Object System.Windows.Forms.Panel
    $banner.Dock = 'Top'
    $banner.Height = 70
    $banner.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 45)
    $form.Controls.Add($banner)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "检测到多个游戏版本，请选择要【$ActionName】的目标："
    $title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 12, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(100, 200, 255)
    $title.Location = New-Object System.Drawing.Point(20, 14)
    $title.AutoSize = $true
    $banner.Controls.Add($title)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = "您可以在下方选择其中一个版本，或选择「同时处理全部版本」"
    $subtitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $subtitle.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 190)
    $subtitle.Location = New-Object System.Drawing.Point(22, 42)
    $subtitle.AutoSize = $true
    $banner.Controls.Add($subtitle)

    # 中部列表单选区
    $body = New-Object System.Windows.Forms.Panel
    $body.Dock = 'Fill'
    $body.Padding = New-Object System.Windows.Forms.Padding(25, 15, 25, 10)
    $form.Controls.Add($body)
    $form.Controls.SetChildIndex($body, 0)

    $radioList = @()
    $y = 15

    for ($i = 0; $i -lt $all.Count; $i++) {
        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Text = "$($all[$i].Platform)  |  $($all[$i].Path)"
        $rb.Location = New-Object System.Drawing.Point(25, $y)
        $rb.Size = New-Object System.Drawing.Size(580, 36)
        $rb.ForeColor = [System.Drawing.Color]::FromArgb(235, 235, 240)
        $rb.Tag = @($all[$i].Path)
        if ($i -eq 0) { $rb.Checked = $true } # 默认高亮排在第一顺位的版本
        $body.Controls.Add($rb)
        $radioList += $rb
        $y += 42
    }

    # 选项：同时处理全部版本 (两端均生效)
    $rbAll = New-Object System.Windows.Forms.RadioButton
    $rbAll.Text = "★ 同时${ActionName}以上全部客户端"
    $rbAll.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
    $rbAll.Location = New-Object System.Drawing.Point(25, $y)
    $rbAll.Size = New-Object System.Drawing.Size(580, 36)
    $rbAll.ForeColor = [System.Drawing.Color]::FromArgb(255, 215, 0)
    $allPaths = @($all | ForEach-Object { $_.Path })
    $rbAll.Tag = $allPaths
    $body.Controls.Add($rbAll)
    $radioList += $rbAll

    # 底部按钮栏
    $btnRow = New-Object System.Windows.Forms.Panel
    $btnRow.Dock = 'Bottom'
    $btnRow.Height = 60
    $btnRow.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 36)
    $form.Controls.Add($btnRow)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "确认执行"
    $btnOk.DialogResult = 'OK'
    $btnOk.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $btnOk.FlatStyle = 'Flat'
    $btnOk.Location = New-Object System.Drawing.Point(390, 14)
    $btnOk.Size = New-Object System.Drawing.Size(110, 32)
    $btnRow.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "取消"
    $btnCancel.DialogResult = 'Cancel'
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 70)
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $btnCancel.FlatStyle = 'Flat'
    $btnCancel.Location = New-Object System.Drawing.Point(515, 14)
    $btnCancel.Size = New-Object System.Drawing.Size(95, 32)
    $btnRow.Controls.Add($btnCancel)

    $form.AcceptButton = $btnOk
    $form.CancelButton = $btnCancel

    $dialogRes = $form.ShowDialog()
    if ($dialogRes -eq 'OK') {
        foreach ($rb in $radioList) {
            if ($rb.Checked) {
                return $rb.Tag
            }
        }
    }

    Write-Host "用户已取消版本选择。" -ForegroundColor Yellow
    return @()
}

# ==================== 专属定制免责声明弹窗 ====================
function Show-Disclaimer {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "AION 2 正式版汉化工具 - 制作: B站@吃素的佩奇"
    $form.Size = New-Object System.Drawing.Size(580, 480)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(24,24,28)

    # 顶部横幅
    $banner = New-Object System.Windows.Forms.Panel
    $banner.Dock = 'Top'
    $banner.Height = 65
    $banner.BackColor = [System.Drawing.Color]::FromArgb(35,35,45)
    $form.Controls.Add($banner)

    $icon = New-Object System.Windows.Forms.Label
    $icon.Text = '!'
    $icon.Font = New-Object System.Drawing.Font('Arial', 24, [System.Drawing.FontStyle]::Bold)
    $icon.ForeColor = [System.Drawing.Color]::FromArgb(255,165,0)
    $icon.Location = New-Object System.Drawing.Point(16,12)
    $icon.Size = New-Object System.Drawing.Size(36,40)
    $icon.TextAlign = 'MiddleCenter'
    $banner.Controls.Add($icon)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = '重要操作风险说明 (Steam / PURPLE 通用)'
    $title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 15, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(255,165,0)
    $title.Location = New-Object System.Drawing.Point(58,16)
    $title.AutoSize = $true
    $banner.Controls.Add($title)

    # 中部说明文字区
    $body = New-Object System.Windows.Forms.Panel
    $body.Dock = 'Fill'
    $body.BackColor = [System.Drawing.Color]::FromArgb(28,28,34)
    $body.Padding = New-Object System.Windows.Forms.Padding(20,12,20,0)
    $form.Controls.Add($body)
    $form.Controls.SetChildIndex($body, 0)

    $items = @(
        '1. 本工具会向游戏目录释放汉化数据文件，并备份所选文字语言包。',
        '2. 任何客户端修改都可能违反游戏服务条款，相关风险由使用者自行承担。',
        '3. 执行过程中请勿启动游戏或中断任务，避免客户端文件损坏。',
        '4. 本工具操作前会先自动备份原文件，可对所选文字语言单独还原。'
    )
    $y = 12
    foreach ($it in $items) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $it
        $l.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
        $l.ForeColor = [System.Drawing.Color]::FromArgb(220,220,225)
        $l.AutoSize = $false
        $l.Location = New-Object System.Drawing.Point(16,$y)
        $l.Size = New-Object System.Drawing.Size(515,50)
        $l.TextAlign = 'TopLeft'
        $body.Controls.Add($l)
        $y += 56
    }

    # 声明栏
    $authorBanner = New-Object System.Windows.Forms.Label
    $authorBanner.Text = "原作者：B站@吃素的佩奇 | 二次升级作者：Foohi"
    $authorBanner.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
    $authorBanner.ForeColor = [System.Drawing.Color]::FromArgb(160,130,240)
    $newY = $y + 4
    $authorBanner.Location = New-Object System.Drawing.Point(16, $newY)
    $authorBanner.Size = New-Object System.Drawing.Size(515,22)
    $authorBanner.TextAlign = 'MiddleLeft'
    $body.Controls.Add($authorBanner)

    # 底部勾选确认栏
    $checkRow = New-Object System.Windows.Forms.Panel
    $checkRow.Dock = 'Bottom'
    $checkRow.Height = 56
    $checkRow.BackColor = [System.Drawing.Color]::FromArgb(20,20,26)
    $form.Controls.Add($checkRow)

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = '我已充分了解修改客户端的潜在风险，并确认当前游戏已经完全关闭。'
    $chk.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
    $chk.ForeColor = [System.Drawing.Color]::FromArgb(200,200,205)
    $chk.Location = New-Object System.Drawing.Point(18,16)
    $chk.AutoSize = $true
    $checkRow.Controls.Add($chk)

    # 按钮栏
    $btnRow = New-Object System.Windows.Forms.Panel
    $btnRow.Dock = 'Bottom'
    $btnRow.Height = 64
    $btnRow.BackColor = [System.Drawing.Color]::FromArgb(32,32,38)
    $form.Controls.Add($btnRow)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = '取消退出'
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(55,55,62)
    $btnCancel.ForeColor = [System.Drawing.Color]::FromArgb(200,200,200)
    $btnCancel.FlatStyle = 'Flat'
    $btnCancel.Location = New-Object System.Drawing.Point(20,15)
    $btnCancel.Size = New-Object System.Drawing.Size(100,34)
    $btnRow.Controls.Add($btnCancel)

    $btnUpdate = New-Object System.Windows.Forms.Button
    $btnUpdate.Text = '检查更新'
    $btnUpdate.BackColor = [System.Drawing.Color]::FromArgb(45,85,125)
    $btnUpdate.ForeColor = [System.Drawing.Color]::White
    $btnUpdate.FlatStyle = 'Flat'
    $btnUpdate.Location = New-Object System.Drawing.Point(150,15)
    $btnUpdate.Size = New-Object System.Drawing.Size(110,34)
    $btnUpdate.Add_Click({
        $btnUpdate.Enabled = $false
        try { Confirm-Aion2Update -Info (Get-Aion2UpdateInfo -CurrentVersion $CurrentVersion) }
        catch { Show-Aion2UpdateMessage $_.Exception.Message 'OK' 'Warning' | Out-Null }
        finally { $btnUpdate.Enabled = $true }
    })
    $btnRow.Controls.Add($btnUpdate)

    $btnGo = New-Object System.Windows.Forms.Button
    $btnGo.Text = '已了解，继续'
    $btnGo.BackColor = [System.Drawing.Color]::FromArgb(90,70,200)
    $btnGo.ForeColor = [System.Drawing.Color]::White
    $btnGo.FlatStyle = 'Flat'
    $btnGo.Location = New-Object System.Drawing.Point(410,15)
    $btnGo.Size = New-Object System.Drawing.Size(130,34)
    $btnGo.Enabled = $false
    $btnRow.Controls.Add($btnGo)

    $btnGo.Add_Click({ $form.DialogResult = 'OK'; $form.Close() })
    $btnCancel.Add_Click({ $form.DialogResult = 'Cancel'; $form.Close() })
    $chk.Add_CheckedChanged({ $btnGo.Enabled = $chk.Checked })

    $form.AcceptButton = $btnGo
    $form.CancelButton = $btnCancel
    return $form.ShowDialog()
}

# ==================== 主流程 ====================
Show-Banner
if ($Install -eq $Restore) { throw '请指定 -Install 或 -Restore 中的一个。' }
$target = Get-TextTarget $TargetLanguage
$action = if ($Install) { 'Install' } else { 'Restore' }
$verb = if ($Install) { "安装$LangName" } else { '还原' }
if ($Install -and (Show-Disclaimer) -ne 'OK') { exit 0 }
$selectedRoots = @(Select-TargetGameRoots -ActionName "$verb / $($target.Name)" | Select-Object -Unique)
if ($selectedRoots.Count -eq 0) { throw '未选择有效游戏目录。' }
$failed = 0
foreach ($gameRoot in $selectedRoots) {
    try {
        $result = Invoke-TextPatch -GameRoot $gameRoot -TargetLanguage $TargetLanguage -Action $action -SourceDir $ActiveSourceDir
        Write-Host "$verb / $($target.Name) 完成：$gameRoot" -ForegroundColor Green
        Write-Host "备份：$($result.Backup)"
        if ($result.LegacyBackup) { Write-Host '使用原工具英文备份；该备份未记录游戏版本。' -ForegroundColor Yellow }
    } catch {
        $failed++
        Write-Host "失败：$gameRoot；$($_.Exception.Message)" -ForegroundColor Red
    }
}
if ($Install) { Write-Host "游戏内文字语言请选择 $($target.Setting)。" -ForegroundColor Yellow }
Write-Host "成功 $($selectedRoots.Count - $failed) 个客户端，失败 $failed 个。"
if ($failed) { exit 1 }
