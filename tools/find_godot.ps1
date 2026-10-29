function Find-MistboundGodot {
    param([string]$RequestedPath)
    $taskCandidates = [System.Collections.Generic.List[string]]::new()
    if ($RequestedPath) { $taskCandidates.Add($RequestedPath) }
    if ($env:MISTBOUND_GODOT) { $taskCandidates.Add($env:MISTBOUND_GODOT) }
    foreach ($taskName in @('godot', 'godot4')) {
        $taskCommand = Get-Command $taskName -ErrorAction SilentlyContinue
        if ($taskCommand) { $taskCandidates.Add($taskCommand.Source) }
    }
    foreach ($taskDrive in Get-PSDrive -PSProvider FileSystem) {
        foreach ($taskRelative in @(
            'SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
            'Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
            'Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
        )) { $taskCandidates.Add((Join-Path $taskDrive.Root $taskRelative)) }
    }
    foreach ($taskCandidate in $taskCandidates) {
        if (Test-Path -LiteralPath $taskCandidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $taskCandidate).Path
        }
    }
    throw 'Godot 4 was not found. Pass -Godot "C:\path\Godot.exe" or set MISTBOUND_GODOT.'
}

function ConvertTo-MistboundArgument {
    param([string]$Value)
    # Windows process argument quoting. Arguments here never contain embedded quotes.
    if ($Value.Contains('"')) { throw 'Double quotes are not valid in this argument.' }
    return '"' + $Value.TrimEnd('\') + '"'
}
