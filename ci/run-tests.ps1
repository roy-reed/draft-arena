#requires -Version 7.0
<#
.SYNOPSIS
  统一测试入口：按固定顺序运行全部 Godot 无头检查（导入、smoke、Boss 回归、独立测试脚本、平衡模拟、长跑），
  并校验 scripts/tests 下每个 *_test.gd 都已登记，避免新增测试被遗漏。

.EXAMPLE
  pwsh ./ci/run-tests.ps1 -Godot .\.tools\godot\godot_console.exe
  pwsh ./ci/run-tests.ps1 -Godot ~/godot/Godot_v4.4.1-stable_linux.x86_64 -Quick
  pwsh ./ci/run-tests.ps1 -List
#>
[CmdletBinding()]
param(
    [string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { Join-Path '.tools' 'godot' 'godot_console.exe' }),
    # 只运行指定名称的检查（可多个）
    [string[]]$Only = @(),
    # 跳过耗时的 soak 长跑
    [switch]$Quick,
    # 只列出检查项，不运行
    [switch]$List
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# pwsh -File 传入的 "a,b" 是单个字符串，这里统一拆分
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

$root = Split-Path -Parent $PSScriptRoot
$runCheck = Join-Path $PSScriptRoot 'run-check.ps1'
$base = @('--headless', '--path', $root)

# 检查清单：Name 唯一；Script 表示通过 --script 直接运行的测试文件
$checks = @(
    [pscustomobject]@{ Name = 'import';           Args = $base + @('--import');                                             Marker = '' }
    [pscustomobject]@{ Name = 'smoke';            Args = $base + @('--', '--smoke', '--grid-verify');                                        Marker = 'SMOKE_OK' }
    # 同一局 smoke 在手游版模式下再跑一遍（强制触屏 + expand + 模拟安全区），覆盖 main 的移动端分支
    [pscustomobject]@{ Name = 'smoke-mobile';     Args = $base + @('--', '--smoke', '--grid-verify', '--mobile-preview', '--safe-inset=96,0,48,40'); Marker = 'SMOKE_OK' }
    [pscustomobject]@{ Name = 'boss-test';        Args = $base + @('--', '--boss-test');                                    Marker = 'BOSS_TEST_OK' }
    [pscustomobject]@{ Name = 'sawblade-test';    Args = $base + @('--script', 'res://scripts/tests/sawblade_cooldown_test.gd'); Marker = 'SAWBLADE_COOLDOWN_OK' }
    [pscustomobject]@{ Name = 'spawn-curve-test'; Args = $base + @('--script', 'res://scripts/tests/spawn_curve_test.gd');    Marker = 'SPAWN_CURVE_OK' }
    [pscustomobject]@{ Name = 'android-config-test'; Args = $base + @('--script', 'res://scripts/tests/android_export_config_test.gd'); Marker = 'ANDROID_CONFIG_OK' }
    [pscustomobject]@{ Name = 'touch-input-test'; Args = $base + @('--script', 'res://scripts/tests/touch_input_test.gd'); Marker = 'TOUCH_INPUT_OK' }
    [pscustomobject]@{ Name = 'player-highlight-test'; Args = $base + @('--script', 'res://scripts/tests/player_highlight_test.gd'); Marker = 'PLAYER_HIGHLIGHT_OK' }
    [pscustomobject]@{ Name = 'screen-layout-test'; Args = $base + @('--script', 'res://scripts/tests/screen_layout_test.gd'); Marker = 'SCREEN_LAYOUT_OK' }
    [pscustomobject]@{ Name = 'collision-grid-test'; Args = $base + @('--script', 'res://scripts/tests/collision_grid_test.gd'); Marker = 'COLLISION_GRID_OK' }
    [pscustomobject]@{ Name = 'sim';              Args = $base + @('--', '--sim');                                          Marker = 'SIM_OK' }
    [pscustomobject]@{ Name = 'soak';             Args = $base + @('--', '--soak', '--grid-verify');                                         Marker = 'SOAK_OK' }
)

# 登记校验：每个测试脚本必须出现在 boss_test_runner.gd 或上面的清单里
function Test-Registry {
    $testsDir = Join-Path $root 'scripts' 'tests'
    $runnerText = Get-Content -LiteralPath (Join-Path $testsDir 'boss_test_runner.gd') -Raw
    $listed = ($checks | ForEach-Object { $_.Args }) -join ' '
    $missing = @(Get-ChildItem -LiteralPath $testsDir -Filter '*_test.gd' | Where-Object {
        $res = "res://scripts/tests/$($_.Name)"
        -not ($runnerText.Contains($res) -or $listed.Contains($res))
    } | ForEach-Object Name)
    if ($missing.Count -gt 0) { throw "未登记到任何测试入口的测试脚本：$($missing -join ', ')" }
    Write-Host "[registry] OK"
}

$selected = @($checks | Where-Object {
    ($Only.Count -eq 0 -or $Only -contains $_.Name) -and -not ($Quick -and $_.Name -eq 'soak')
})
if ($Only.Count -gt 0) {
    $unknown = @($Only | Where-Object { $_ -notin $checks.Name })
    if ($unknown.Count -gt 0) { throw "未知的检查项：$($unknown -join ', ')。可用：$($checks.Name -join ', ')" }
}

if ($List) {
    $checks | ForEach-Object { '{0,-18} {1}' -f $_.Name, ($_.Args[3..($_.Args.Count - 1)] -join ' ') }
    return
}

if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw "找不到 Godot 可执行文件：$Godot（用 -Godot 或环境变量 GODOT 指定）" }

$results = [System.Collections.Generic.List[object]]::new()
$failed = 0
try { Test-Registry; $results.Add([pscustomobject]@{ Name = 'registry'; Result = 'PASS'; Seconds = 0 }) }
catch { Write-Host "[registry] FAIL: $($_.Exception.Message)"; $results.Add([pscustomobject]@{ Name = 'registry'; Result = 'FAIL'; Seconds = 0 }); $failed++ }

foreach ($check in $selected) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = 'PASS'
    try {
        & $runCheck -Name $check.Name -Exe $Godot -Arguments $check.Args -SuccessMarker $check.Marker
    }
    catch {
        $result = 'FAIL'
        $failed++
        Write-Host "[$($check.Name)] FAIL: $($_.Exception.Message)"
    }
    $results.Add([pscustomobject]@{ Name = $check.Name; Result = $result; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) })
}

$table = $results | Format-Table -AutoSize | Out-String
Write-Host $table
if ($env:GITHUB_STEP_SUMMARY) {
    $md = @('| 检查 | 结果 | 秒 |', '|---|---|---|') + ($results | ForEach-Object { "| $($_.Name) | $($_.Result) | $($_.Seconds) |" })
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ($md -join "`n")
}
if ($failed -gt 0) { Write-Host "$failed 项检查失败"; exit 1 }
Write-Host "ALL_TESTS_OK ($($results.Count) 项)"
