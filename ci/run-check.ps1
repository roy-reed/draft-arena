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

$log = "$Name.log"
& $Exe @Arguments 2>&1 | Tee-Object -FilePath $log
$code = $LASTEXITCODE
if ($code -ne 0) { Write-Error "[$Name] exit code $code"; exit $code }
if (Select-String -Path $log -Pattern 'SCRIPT ERROR|ERROR:' -Quiet) { Write-Error "[$Name] error found in log"; exit 1 }
if ($SuccessMarker -and -not (Select-String -Path $log -SimpleMatch $SuccessMarker -Quiet)) {
    Write-Error "[$Name] missing success marker '$SuccessMarker'"; exit 1
}
Write-Host "[$Name] OK"
