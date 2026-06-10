#requires -Version 5.1
<#
.SYNOPSIS
    Launch OLLMchat with the GTK/MSYS2 runtime environment.

.DESCRIPTION
    Sets up the same environment as OLLMchat.bat and runs ollmchat.exe.

    Do NOT run this file as .\OLLMchat.ps1 — default ExecutionPolicy blocks it.
    From the portable bundle folder (same pattern as vala.win32 / Snappr):

      powershell -NoProfile -ExecutionPolicy Bypass -File .\OLLMchat.ps1 --debug

    Or use OLLMchat.exe (double-click; no Bypass needed).

    Copy dist-windows-x86_64/OLLMchat/ to Windows and run from that folder.
    The build tree (build-windows-x86_64/ollmapp/) is not runnable on its own.
#>
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AppArgs
)

$here = $PSScriptRoot
$bat = Join-Path $here 'OLLMchat.bat'

if (-not (Test-Path -LiteralPath $bat)) {
    Write-Error @"
OLLMchat.bat not found in '$here'.

Copy the full portable bundle to Windows:
  dist-windows-x86_64/OLLMchat/

Do not run from build-windows-x86_64/ollmapp/ — that directory has only the
compile output and is missing runtime DLLs and launchers.
"@
    exit 1
}

$quoted = foreach ($arg in $AppArgs) {
    if ($null -eq $arg -or $arg -eq '') { continue }
    if ($arg -match '[\s"]') {
        '"' + ($arg -replace '"', '\"') + '"'
    } else {
        $arg
    }
}
$argLine = if ($quoted.Count -gt 0) { ' ' + ($quoted -join ' ') } else { '' }

& cmd.exe /c "`"$bat`"$argLine"
exit $LASTEXITCODE
