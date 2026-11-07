param([string]$GamePath)

$ErrorActionPreference = 'Stop'
$pkgRoot = $PSScriptRoot | Split-Path -Parent      # ...\GravHounds<中文补丁>\
$repak   = Join-Path $pkgRoot 'tools\repak.exe'
$overlay = Join-Path $pkgRoot 'overlay'

function Ok($t){ Write-Host $t -ForegroundColor Green }
function Step($t){ Write-Host $t -ForegroundColor Cyan }
function Bad($t){ Write-Host $t -ForegroundColor Red }
function Warn($t){ Write-Host $t -ForegroundColor Yellow }

function Test-GameRoot($p) { return ($p -and (Test-Path (Join-Path $p 'WFOSteam.exe'))) }

function Find-SteamGame {
    $libs = New-Object System.Collections.Generic.List[string]
    foreach ($k in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam')) {
        $pp = (Get-ItemProperty $k -ErrorAction SilentlyContinue)
        if ($pp) { if ($pp.SteamPath) { $libs.Add($pp.SteamPath) }; if ($pp.InstallPath) { $libs.Add($pp.InstallPath) } }
    }
    foreach ($l in @($libs)) {
        $vdf = Join-Path $l 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($line in (Get-Content $vdf -ErrorAction SilentlyContinue)) {
                $m = [regex]::Match($line, '"path"\s+"([^"]+)"')
                if ($m.Success) { $libs.Add(($m.Groups[1].Value -replace '\\\\','\')) }
            }
        }
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        $c = Join-Path $lib 'steamapps\common\GravHounds'
        if (Test-GameRoot $c) { return $c }
    }
    return $null
}

Write-Host ''
Write-Host '================ GRAVHOUNDS 简体中文补丁 ================' -ForegroundColor White

# 1) 本补丁文件夹就放在游戏根目录 → 直接用它
if (-not (Test-GameRoot $GamePath)) {
    $parent = Split-Path $pkgRoot -Parent
    if (Test-GameRoot $parent) { $GamePath = $parent }
}
# 2) 参数
# 3) Steam 自动查找
if (-not (Test-GameRoot $GamePath)) { $GamePath = Find-SteamGame }
# 4) 弹窗手动选
if (-not (Test-GameRoot $GamePath)) {
    Warn '没找到游戏目录。请把本文件夹放进游戏根目录（与 WFOSteam.exe 同级）后重试，'
    Warn '或者在弹窗里手动选择游戏文件夹。'
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = '选择 GravHounds 游戏文件夹（里面有 WFOSteam.exe）'
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { Bad '已取消。'; exit 1 }
    $GamePath = $dlg.SelectedPath
}
if (-not (Test-GameRoot $GamePath)) { Bad ('这个目录里没有 WFOSteam.exe：' + $GamePath); exit 1 }

$paks = Join-Path $GamePath 'WFO\Content\Paks'
$pak  = Join-Path $paks 'pakchunk0-Windows.pak'
if (-not (Test-Path $pak)) { Bad ('找不到 ' + $pak); exit 1 }
if (Get-Process WFOSteam-Win64-Shipping -ErrorAction SilentlyContinue) { Bad '请先完全关闭游戏，再运行本脚本。'; exit 1 }

Write-Host ('游戏目录：' + $GamePath) -ForegroundColor Gray
Write-Host ''

$bak = $pak + '.orig'
$exe = Join-Path $GamePath 'WFO\Binaries\Win64\WFOSteam-Win64-Shipping.exe'
if (-not (Test-Path $exe)) { $exe = Join-Path $GamePath 'WFOSteam.exe' }

# ===== v1.2 关键守卫：备份是否已因游戏更新而过期 =====
# 规则：.orig 备份的修改时间早于游戏主程序 → 游戏在安装补丁之后更新过 → 旧备份不能再用
$staleBak = $false
$useBak   = $false
if (Test-Path $bak) {
    $bakAge = (Get-Item $bak).LastWriteTime
    $exeAge = (Get-Item $exe).LastWriteTime
    if ($bakAge -lt $exeAge) {
        $staleBak = $true
        Warn '=============================================================='
        Warn '检测到游戏在安装补丁之后更新过（.orig 备份已过期）。'
        Warn '旧备份不能作为基底，否则会因版本不匹配导致游戏报错。'
        Warn '=============================================================='
    } else {
        $useBak = $true
        Warn '检测到已安装过（存在 .orig 备份），将基于备份原版重新生成。'
    }
} else {
    Copy-Item $pak $bak -Force
    Ok '已备份原版 pakchunk0-Windows.pak.orig'
}

$work = Join-Path $env:TEMP 'gh_zh_build'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory $work | Out-Null

if ($useBak) {
    Copy-Item $bak (Join-Path $work 'pakchunk0-Windows.pak') -Force
} else {
    # 过期备份场景：以当前 pak 为基底尝试（仅当它还是官方干净版时才能成功，见下方嗅探）
    Copy-Item $pak (Join-Path $work 'pakchunk0-Windows.pak') -Force
}

Step '[1/4] 解包 pak ...'
& $repak unpack (Join-Path $work 'pakchunk0-Windows.pak') | Out-Null
if ($LASTEXITCODE -ne 0) {
    Bad '解包失败（可能是游戏更新改变了 pak 格式）。'
    if ($staleBak) { Bad '另外：游戏更新后请先在 Steam 验证文件完整性，再运行本脚本。' }
    exit 1
}

# ===== v1.2 嗅探：当前基底是否为我们之前的注入产物 =====
$unpackedRoot = Join-Path $work 'pakchunk0-Windows'
$deLoc = Join-Path $unpackedRoot 'WFO\Content\Localization\Game\de\Game.locres'
$injected = $false
if (Test-Path $deLoc) {
    # 官方德语版不含中文；注入版含我们的译文特征词（整文件按 UTF-8 解码后查找）
    $text = [System.IO.File]::ReadAllText($deLoc, [System.Text.Encoding]::UTF8)
    if ($text.Contains([char]0x51FB + [char]0x6740) -or $text.Contains([char]0x91CD + [char]0x529B + [char]0x675F)) { $injected = $true }
}

if ($injected) {
    Remove-Item $work -Recurse -Force
    Bad '=============================================================='
    Bad '当前 pakchunk0-Windows.pak 是旧版注入产物，且游戏已更新，'
    Bad '两者版本不匹配（这正是启动报 StreamlineDeepDVC 错误的原因）。'
    Bad ''
    Bad '请按以下顺序操作：'
    Bad '  1. Steam 库 → 右键 GRAVHOUNDS → 属性 → 已安装文件'
    Bad '     → 验证文件完整性（恢复官方新版）'
    Bad '  2. 删除游戏 Paks 目录里的 pakchunk0-Windows.pak.orig'
    Bad '  3. 重新双击「安装中文.bat」'
    Bad '=============================================================='
    exit 1
}

if ($staleBak) {
    # 当前 pak 是官方新版（干净），刷新备份
    Copy-Item $pak $bak -Force
    Ok '游戏已更新：备份 .orig 已刷新为新版官方 pak。'
    Warn '注意：更新新增的游戏文本会暂时显示英文，等仓库出翻译更新版。'
}

Step '[2/4] 写入中文文本与字体 ...'
Copy-Item (Join-Path $overlay '*') (Join-Path $unpackedRoot) -Recurse -Force

Step '[3/4] 重新打包 ...'
$newpak = Join-Path $work 'new.pak'
& $repak pack $unpackedRoot $newpak -m '../../../' --version V11 --compression Zlib | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $newpak)) { Bad '打包失败'; exit 1 }

Step '[4/4] 安装 ...'
Copy-Item $newpak $pak -Force
Remove-Item $work -Recurse -Force

Write-Host ''
Ok '★ 安装完成！'
Write-Host ''
Write-Host '最后一步（只需做一次）：' -ForegroundColor White
Write-Host '  启动游戏 → OPTIONS → GAMEPLAY → LANGUAGE'
Write-Host '  语言改成  Deutsch (German)  →  返回 → 弹窗点 OK（游戏自动重启）'
Write-Host '  重启后界面就是简体中文了。'
Write-Host ''
Write-Host '卸载：双击 卸载还原.bat' -ForegroundColor Gray
Write-Host '游戏更新后：补丁会失效，先卸载还原或 Steam 验证完整性，再装新版补丁。' -ForegroundColor Gray
