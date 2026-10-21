$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Update.ps1')
function Assert($condition, $message) { if (-not $condition) { throw $message } }
function Release($tag, $notes = '本版更新：三语言汉化及还原修复。') {
    [pscustomobject]@{tag_name=$tag;body=$notes;draft=$false;prerelease=$false;html_url='https://example.invalid/foreign-download'}
}
$new = ConvertTo-Aion2UpdateInfo (Release 'v1.2.1.10') '1.2.1.6'
Assert $new.HasUpdate 'Numeric version comparison failed'
Assert ($new.DownloadUrl -ceq 'https://github.com/Foohi666/Aion2-CN-Foohi/releases/tag/v1.2.1.10') 'Download did not remain in the project repository'
foreach ($tag in 'v1.2.1.6','v1.2.1.5','v1.2.1') {
    Assert (-not (ConvertTo-Aion2UpdateInfo (Release $tag) '1.2.1.6').HasUpdate) 'Current or older release treated as update'
}
$script:opened = @()
$script:messages = @()
$script:answer = 'Cancel'
function Show-Aion2UpdateMessage {
    param($Message,$Buttons,$Icon)
    $script:messages += [pscustomobject]@{Message=$Message;Buttons=$Buttons}
    return $script:answer
}
function Open-Aion2DownloadPage { param($Url) $script:opened += $Url }
Confirm-Aion2Update $new
Assert ($script:opened.Count -eq 0) 'Cancel opened browser'
Assert ($script:messages[-1].Buttons -eq 'OKCancel') 'New release did not request confirmation'
Assert ($script:messages[-1].Message.Contains($new.Notes)) 'Release notes not displayed'
$script:answer = 'OK'
Confirm-Aion2Update $new
Assert ($script:opened.Count -eq 1 -and $script:opened[0] -ceq $new.DownloadUrl) 'Confirmation did not open the expected release'
Confirm-Aion2Update (ConvertTo-Aion2UpdateInfo (Release 'v1.2.1.6') '1.2.1.6')
Assert ($script:opened.Count -eq 1) 'No-update dialog opened browser'
foreach ($release in @((Release 'vbad'), (Release 'v1.2.1.7' ''), (Release 'v1.2.1.7-preview'))) {
    $failed = $false
    try { ConvertTo-Aion2UpdateInfo $release '1.2.1.6' | Out-Null } catch { $failed = $true }
    Assert $failed 'Malformed release accepted'
}
$preview = Release 'v1.2.1.7'
$preview.prerelease = $true
$failed = $false
try { ConvertTo-Aion2UpdateInfo $preview '1.2.1.6' | Out-Null } catch { $failed = $true }
Assert $failed 'Preview release accepted as stable'
Write-Output 'PASS: numeric versions, release validation, notes, confirmation required, cancel stays local, destination restricted to project'
