param([string]$Godot, [string]$ResultsPath)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\find_godot.ps1')
$taskEngine = Find-MistboundGodot $Godot
$taskProject = Split-Path $PSScriptRoot -Parent
if (-not $ResultsPath) {
    $ResultsPath = Join-Path ([IO.Path]::GetTempPath()) ('mistbound-tests-' + [guid]::NewGuid().ToString('N'))
}
$taskResults = [IO.Path]::GetFullPath($ResultsPath)
New-Item -ItemType Directory -Path $taskResults -Force | Out-Null
$taskRunId = [guid]::NewGuid().ToString('N').Substring(0, 8)
$taskPreviousSave = $env:MISTBOUND_SAVE_DIR
$taskStarted = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

function Start-TestGodot {
    param([string]$Name, [string[]]$ExtraArgs)
    $env:MISTBOUND_SAVE_DIR = Join-Path $taskResults ($Name + '-saves-' + $taskRunId)
    $taskLog = Join-Path $taskResults ($Name + '.log')
    $taskArguments = @('--headless', '--path', $taskProject, '--log-file', $taskLog) + $ExtraArgs
    $taskQuoted = ($taskArguments | ForEach-Object { ConvertTo-MistboundArgument $_ }) -join ' '
    $taskProcess = Start-Process -FilePath $taskEngine -ArgumentList $taskQuoted -WindowStyle Hidden -PassThru
    $taskStarted.Add($taskProcess)
    return @{ Process = $taskProcess; Log = $taskLog; Name = $Name }
}

function Complete-TestGodot {
    param([hashtable]$Run, [string]$Expected)
    if (-not $Run.Process.WaitForExit(45000)) {
        $Run.Process.Kill()
        throw ($Run.Name + ' timed out')
    }
    $taskText = Get-Content -LiteralPath $Run.Log -Raw
    if ($Run.Process.ExitCode -ne 0 -or $taskText -match '(?m)^(SCRIPT ERROR|ERROR):' -or ($Expected -and $taskText -notmatch [regex]::Escape($Expected))) {
        Write-Output (($taskText -split "`n" | Select-Object -First 90) -join "`n")
        throw ($Run.Name + ' failed. Log: ' + $Run.Log)
    }
    Write-Output ('PASS ' + $Run.Name)
}

try {
    Complete-TestGodot (Start-TestGodot 'import' @('--editor', '--import', '--quit')) ''
    Complete-TestGodot (Start-TestGodot 'persistence' @('--script', 'res://tests/test_persistence.gd')) '0 failures'
    Complete-TestGodot (Start-TestGodot 'gameplay' @('--script', 'res://tests/test_gameplay.gd')) '0 failures'
    Complete-TestGodot (Start-TestGodot 'combat' @('--script', 'res://tests/test_combat.gd')) '0 failures'
    Complete-TestGodot (Start-TestGodot 'enemy-brain' @('--script', 'res://tests/test_enemy_brain.gd')) 'PASS enemy brain'
    $taskPort = Get-Random -Minimum 25000 -Maximum 45000
    $taskHost = Start-TestGodot 'network-host' @('--script', 'res://tests/network_peer.gd', '--', '--test-role=host', "--test-port=$taskPort")
    Start-Sleep -Milliseconds 700
    $taskClient = Start-TestGodot 'network-client' @('--script', 'res://tests/network_peer.gd', '--', '--test-role=client', "--test-port=$taskPort")
    Complete-TestGodot $taskHost 'NETWORK HOST PASS'
    Complete-TestGodot $taskClient 'NETWORK CLIENT PASS'
    Write-Output "All tests passed. Logs: $taskResults"
}
finally {
    foreach ($taskProcess in $taskStarted) {
        if (-not $taskProcess.HasExited) { $taskProcess.Kill() }
    }
    $env:MISTBOUND_SAVE_DIR = $taskPreviousSave
}
