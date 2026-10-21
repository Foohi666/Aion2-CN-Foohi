# 更新来源：Foohi 的二次升级项目。只检查正式 Release，不执行下载内容。
$script:Aion2Repository = 'Foohi666/Aion2-CN-Foohi'

function ConvertTo-Aion2UpdateInfo {
    param([Parameter(Mandatory)]$Release, [Parameter(Mandatory)][version]$CurrentVersion)
    $tag = [string]$Release.tag_name
    if ($Release.draft -or $Release.prerelease -or $tag -notmatch '^v(\d+\.\d+\.\d+(?:\.\d+)?)$') {
        throw '仓库返回的正式版本信息无效，请稍后重试。'
    }
    $latest = [version]$Matches[1]
    if ([string]::IsNullOrWhiteSpace([string]$Release.body)) {
        throw '该版本缺少更新说明，请到仓库核实后再下载。'
    }
    [pscustomobject]@{
        CurrentVersion = $CurrentVersion.ToString()
        LatestVersion = $latest.ToString()
        HasUpdate = $latest -gt $CurrentVersion
        Notes = [string]$Release.body
        DownloadUrl = "https://github.com/$script:Aion2Repository/releases/tag/$tag"
    }
}

function Get-Aion2UpdateInfo {
    param([Parameter(Mandatory)][version]$CurrentVersion)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $request = [Net.HttpWebRequest]::Create("https://api.github.com/repos/$script:Aion2Repository/releases/latest")
    $request.Timeout = 8000
    $request.ReadWriteTimeout = 8000
    $request.UserAgent = "Aion2-CN-Foohi/$CurrentVersion"
    $request.Accept = 'application/vnd.github+json'
    $request.Headers.Add('X-GitHub-Api-Version', '2022-11-28')
    $response = $null
    $reader = $null
    try {
        $response = $request.GetResponse()
        $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
        $release = $reader.ReadToEnd() | ConvertFrom-Json
        ConvertTo-Aion2UpdateInfo -Release $release -CurrentVersion $CurrentVersion
    } catch [Net.WebException] {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) {
            throw '仓库暂时没有可用的正式发布版本，未能完成更新检查。'
        }
        throw '无法连接 GitHub 检查更新（网络超时或访问受限）。请稍后重试。'
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($response) { $response.Dispose() }
    }
}

function Show-Aion2UpdateMessage {
    param([string]$Message, [string]$Buttons, [string]$Icon)
    [Windows.Forms.MessageBox]::Show($Message, '检查更新 - Foohi',
        [Windows.Forms.MessageBoxButtons]$Buttons, [Windows.Forms.MessageBoxIcon]$Icon)
}

function Open-Aion2DownloadPage {
    param([string]$Url)
    $start = New-Object Diagnostics.ProcessStartInfo($Url)
    $start.UseShellExecute = $true
    [Diagnostics.Process]::Start($start) | Out-Null
}

function Confirm-Aion2Update {
    param([Parameter(Mandatory)]$Info)
    if (-not $Info.HasUpdate) {
        Show-Aion2UpdateMessage "当前版本 v$($Info.CurrentVersion)，仓库最新版本 v$($Info.LatestVersion)。`r`n暂无更新。" 'OK' 'Information' | Out-Null
        return
    }
    $notes = $Info.Notes
    if ($notes.Length -gt 1500) { $notes = $notes.Substring(0, 1500) + "`r`n……完整内容见下载页。" }
    $message = "发现新版本 v$($Info.LatestVersion)（当前 v$($Info.CurrentVersion)）。`r`n`r`n更新内容：`r`n$notes`r`n`r`n点击[确定]打开 Foohi 的 GitHub 版本下载页。"
    $choice = Show-Aion2UpdateMessage $message 'OKCancel' 'Information'
    if ([string]$choice -eq 'OK') { Open-Aion2DownloadPage $Info.DownloadUrl }
}
