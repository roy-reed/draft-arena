#requires -Version 7.0
# 运行一个 Godot 无头检查：退出码非 0、日志含脚本错误或缺少成功标记时失败。
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(Mandatory)][string[]]$Arguments,
    [string]$SuccessMarker = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$processName = [System.IO.Path]::GetFileNameWithoutExtension([Environment]::ProcessPath)
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.0' -or $processName -ne 'pwsh') {
    throw 'ci/run-check.ps1 仅支持 PowerShell 7+ 的 pwsh.exe。'
}
$utf8 = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

$log = "$Name.log"
& $Exe @Arguments 2>&1 | Tee-Object -FilePath $log
$code = $LASTEXITCODE
if ($code -ne 0) { Write-Error "[$Name] exit code $code"; exit $code }
if (Select-String -Path $log -Pattern 'SCRIPT ERROR|ERROR:' -Encoding utf8 -Quiet) { Write-Error "[$Name] error found in log"; exit 1 }
if ($SuccessMarker -and -not (Select-String -Path $log -SimpleMatch $SuccessMarker -Encoding utf8 -Quiet)) {
    Write-Error "[$Name] missing success marker '$SuccessMarker'"; exit 1
}
Write-Host "[$Name] OK"

