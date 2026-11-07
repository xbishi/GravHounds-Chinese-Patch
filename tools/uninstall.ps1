param([string]$GamePath)
$ErrorActionPreference = 'Stop'
$pkgRoot = $PSScriptRoot | Split-Path -Parent

function Test-GameRoot($p) { return ($p -and (Test-Path (Join-Path $p 'WFOSteam.exe'))) }
function Find-SteamGame {
    $libs = New-Object System.Collections.Generic.List[string]
    foreach ($k in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
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

Write-Host '============ GRAVHOUNDS 中文补丁 · 卸载恢复 ============' -ForegroundColor White
if (-not (Test-GameRoot $GamePath)) {
    $parent = Split-Path $pkgRoot -Parent
    if (Test-GameRoot $parent) { $GamePath = $parent }
}
if (-not (Test-GameRoot $GamePath)) { $GamePath = Find-SteamGame }
if (-not (Test-GameRoot $GamePath)) { Write-Host '没找到游戏目录，请把本文件夹放进游戏根目录后再运行。' -ForegroundColor Yellow; exit 1 }

$pak = Join-Path $GamePath 'WFO\Content\Paks\pakchunk0-Windows.pak'
if (Get-Process WFOSteam-Win64-Shipping -ErrorAction SilentlyContinue) { Write-Host '请先完全关闭游戏。' -ForegroundColor Red; exit 1 }
if (-not (Test-Path ($pak + '.orig'))) { Write-Host '没有找到备份（.orig），无法还原。可让 Steam 校验文件完整性。' -ForegroundColor Red; exit 1 }

# v1.2 守卫：游戏更新后旧备份会版本不匹配
$exe = Join-Path $GamePath 'WFO\Binaries\Win64\WFOSteam-Win64-Shipping.exe'
if (-not (Test-Path $exe)) { $exe = Join-Path $GamePath 'WFOSteam.exe' }
if ((Test-Path $exe) -and ((Get-Item ($pak + '.orig')).LastWriteTime -lt (Get-Item $exe).LastWriteTime)) {
    Write-Host '==============================================================' -ForegroundColor Yellow
    Write-Host '检测到游戏更新过，.orig 备份是旧版本的。' -ForegroundColor Yellow
    Write-Host '还原旧版 pak 会与新版游戏不匹配，可能导致启动报错。' -ForegroundColor Yellow
    Write-Host '推荐：改用 Steam 校验文件完整性来还原官方新版。' -ForegroundColor Yellow
    $ans = Read-Host '仍要还原旧版备份吗？(y=还原 / 其他=取消)'
    if ($ans -ne 'y') { Write-Host '已取消。请运行 Steam 验证文件完整性。'; exit 0 }
}
Copy-Item ($pak + '.orig') $pak -Force
Write-Host '已还原原版 pak，中文补丁已卸载。' -ForegroundColor Green
