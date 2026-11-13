# Step 5: Edge removal with ave9858's UninstallEdge.ps1
# (https://gist.github.com/ave9858/c3451d9f452389ac7607c99d45edecc6, public domain, CC0-1.0).
#
# Microsoft only lets Edge be uninstalled in the European Economic Area. The script runs Edge's own
# uninstaller (the uninstall command of Edge's entry in Settings > Apps, plus --force-uninstall) in
# a way the uninstaller accepts in every country:
#   - it sets the AllowUninstall value under EdgeUpdateDev,
#   - it creates the empty placeholder for the old built-in Edge that the uninstaller looks for,
#   - it starts the uninstaller from a temporary copy of cmd.exe named dllhost.exe.
# It deletes those temporary files afterwards and does not touch WebView2 or Edge Update (which
# keeps WebView2 up to date).
#
# UDP downloads the gist revision pinned in config/tools.json, checks its SHA256 and runs it
# unchanged with no window. Then UDP waits until Edge is gone, checks that WebView2 is still there
# and removes leftover Edge shortcuts.
#
# UDP 0.1.0 to 0.1.12 used AveYo's Edge_Removal.bat instead. It cannot remove Edge 120 or newer,
# but it installs a link redirect (C:\Scripts\OpenWebSearch.cmd and Image File Execution Options
# entries for msedge.exe). UDP does not change that redirect; it only mentions it in the log.

function Test-UdpEdgeRemovalAvailable {
    param([hashtable]$Context)
    if (-not (Test-UdpEdgeInstalled)) {
        # Edge is already gone: the step can still remove the shortcuts a previous removal left behind.
        if (@(Get-UdpEdgeShortcuts).Count -gt 0) { return New-UdpAvailability $true }
        return New-UdpAvailability $false 'Microsoft Edge is not installed.'
    }
    if (-not $Context.System.Internet) { return New-UdpAvailability $false 'No internet connection.' }
    return New-UdpAvailability $true
}

# "Microsoft Edge" shortcuts on the desktop (yours and the all-users one) and in the Start menu
# that point to Edge's msedge.exe. Shortcuts with any other target are never touched.
function Get-UdpEdgeShortcuts {
    $folders = @(
        [Environment]::GetFolderPath('CommonDesktopDirectory'),
        [Environment]::GetFolderPath('DesktopDirectory'),
        [Environment]::GetFolderPath('CommonPrograms'),
        [Environment]::GetFolderPath('Programs')
    ) | Where-Object { $_ } | Select-Object -Unique

    $shell = New-Object -ComObject WScript.Shell
    $found = @()
    foreach ($folder in $folders) {
        foreach ($file in (Get-ChildItem -LiteralPath $folder -Filter 'Microsoft Edge*.lnk' -File -ErrorAction SilentlyContinue)) {
            $target = $shell.CreateShortcut($file.FullName).TargetPath
            if ($target -match '\\Microsoft\\Edge\\Application\\msedge\.exe$') { $found += $file.FullName }
        }
    }
    return $found
}

# Once Edge is gone, its leftover shortcuts point to a program that no longer exists.
function Remove-UdpEdgeShortcuts {
    param([hashtable]$Context)
    $removed = 0
    foreach ($shortcut in @(Get-UdpEdgeShortcuts)) {
        if ($Context.DryRun) {
            Write-UdpLog "[dry run] would remove the Edge shortcut $shortcut once Edge is gone" -Level DryRun
            continue
        }
        try {
            Remove-Item -LiteralPath $shortcut -Force -ErrorAction Stop
            $removed++
            Write-UdpLog "Removed the Edge shortcut $shortcut" -Level Info
        }
        catch {
            Write-UdpLog "Could not remove ${shortcut}: $($_.Exception.Message)" -Level Warning
        }
    }
    return $removed
}

function Get-UdpEdgeRemovalPlan {
    param([hashtable]$Context, [hashtable]$Options)
    if (-not (Test-UdpEdgeInstalled)) {
        return @("Edge is already removed: only remove its $(@(Get-UdpEdgeShortcuts).Count) leftover shortcut(s) on the desktop and in the Start menu")
    }
    $tool = Get-UdpToolConfig -Context $Context -Id 'edgeRemoval'
    return @(
        "Download $($tool.name) by $($tool.author) (gist revision $($tool.revision.Substring(0, 7)) of $($tool.revisionDate)) and check its SHA256",
        'Run it with no window: it starts Edge''s own uninstaller in a way the uninstaller accepts outside the EEA. WebView2 is not touched',
        'Wait until Edge is gone, then check that WebView2 is still there',
        'Remove the leftover Edge shortcuts on the desktop and in the Start menu'
    )
}

# AveYo's Edge_Removal.bat, used by UDP 0.1.0 to 0.1.12, leaves a link redirect behind.
function Test-UdpEdgeRedirectLeftover {
    if (Test-Path -LiteralPath (Join-Path $env:SystemDrive 'Scripts\OpenWebSearch.cmd')) { return $true }
    $filter = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\msedge.exe\0'
    $debugger = (Get-ItemProperty -LiteralPath $filter -Name Debugger -ErrorAction SilentlyContinue).Debugger
    return ([string]$debugger -like '*OpenWebSearch*')
}

# Edge's uninstall command includes --verbose-logging, so the uninstaller writes msedge_installer.log.
# Returns the newest one written since $Since, or $null.
function Get-UdpEdgeInstallerLog {
    param([datetime]$Since)
    $candidates = @(
        (Join-Path $env:TEMP 'msedge_installer.log'),
        (Join-Path $env:SystemRoot 'SystemTemp\msedge_installer.log'),
        (Join-Path $env:SystemRoot 'Temp\msedge_installer.log')
    )
    $found = @($candidates | Select-Object -Unique | ForEach-Object { Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue } |
            Where-Object { $_.LastWriteTime -ge $Since } | Sort-Object LastWriteTime -Descending)
    if ($found.Count -gt 0) { return $found[0].FullName }
    return $null
}

function Write-UdpEdgeInstallerLog {
    param([string]$Path, [int]$Lines = 40)
    try {
        $tail = @(Get-Content -LiteralPath $Path -Tail $Lines -ErrorAction Stop)
        Write-UdpLog "Last $($tail.Count) lines of Edge's own uninstaller log ($Path):" -Level Detail
        foreach ($line in $tail) { Write-UdpLog "  $line" -Level Detail }
    }
    catch {
        Write-UdpLog "Could not read ${Path}: $($_.Exception.Message)" -Level Warning
    }
}

function Invoke-UdpEdgeRemoval {
    param([hashtable]$Context, [hashtable]$Options)

    $tool = Get-UdpToolConfig -Context $Context -Id 'edgeRemoval'

    if (Test-UdpEdgeRedirectLeftover) {
        Write-UdpLog ('Found the link redirect left by AveYo''s Edge_Removal.bat from an earlier UDP version ' +
            "($env:SystemDrive\Scripts\OpenWebSearch.cmd). UDP leaves it as it is; docs/edge-removal.md explains how to remove it.") -Level Info
    }

    if (-not (Test-UdpEdgeInstalled)) {
        $count = Remove-UdpEdgeShortcuts -Context $Context
        if ($Context.DryRun) { return New-UdpStepResult -Status Success -Message 'Dry run: Edge is already removed; leftover shortcuts not removed.' }
        return New-UdpStepResult -Status Success -Message "Edge was already removed. $count leftover Edge shortcut(s) removed."
    }

    # Never leave the user without a browser.
    $browsers = @(Get-UdpInstalledBrowsers)
    if ($browsers.Count -eq 0 -and -not $Context.DryRun) {
        $answer = Request-UdpDecision -Context $Context -Kind 'Confirm' -Title 'No other browser is installed' -Body (
            "UDP found no browser other than Edge on this PC. If you remove Edge now, you will have no web browser.`r`n`r`n" +
            "You can still download one later from another device, but it is easier to install one first (go back and enable the 'Alternative browser' step).") -Buttons @(
            (New-UdpButton 'skip' 'Keep Edge' -Primary),
            (New-UdpButton 'remove' 'Remove Edge anyway'))
        if ($answer -ne 'remove') { return New-UdpStepResult -Status Skipped -Message 'Edge kept: no other browser is installed.' }
    }
    else {
        Write-UdpLog "Other browsers found: $($browsers -join ', ')" -Level Info
    }

    $folder = New-UdpWorkFolder -Context $Context -Name 'edge'
    $scriptPath = Join-Path $folder $tool.name
    Invoke-UdpDownload -Uri $tool.url -OutFile $scriptPath | Out-Null
    if (-not (Test-UdpFileHash -Path $scriptPath -ExpectedSha256 $tool.sha256)) {
        return New-UdpStepResult -Status Skipped -Message "$($tool.name) does not match the SHA256 pinned in config/tools.json; skipped for safety."
    }

    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath)
    if ($Context.DryRun) {
        Write-UdpLog "[dry run] would run: $powershell $(Join-UdpArguments -ArgumentList $arguments)" -Level DryRun
        Remove-UdpEdgeShortcuts -Context $Context | Out-Null
        return New-UdpStepResult -Status Success -Message 'Dry run: Edge not removed.'
    }

    $started = (Get-Date).AddSeconds(-5)
    $exitCode = Invoke-UdpProcess -FilePath $powershell -Label $tool.name -ArgumentList $arguments

    # Exit code 0: the uninstaller ran. Anything else: the script stopped with an error, normally
    # before the uninstaller started, so there is nothing to wait for.
    $timeout = 300
    if ($exitCode -ne 0) { $timeout = 15 }
    $edgeGone = Wait-UdpEdgeRemoved -TimeoutSeconds $timeout

    $installerLog = Get-UdpEdgeInstallerLog -Since $started
    if ($installerLog -and -not $edgeGone) { Write-UdpEdgeInstallerLog -Path $installerLog }
    elseif ($installerLog) { Write-UdpLog "Edge's own uninstaller log: $installerLog" -Level Detail }

    $webView = Test-UdpWebView2Installed
    Write-UdpLog "WebView2 Runtime after removal: $(if ($webView) { 'present' } else { 'NOT FOUND' })" -Level Info
    $cleanup = ''
    if ($edgeGone) {
        $count = Remove-UdpEdgeShortcuts -Context $Context
        $cleanup = " $count leftover Edge shortcut(s) removed."
    }

    if ($edgeGone -and $webView) {
        return New-UdpStepResult -Status Success -Message "Edge removed, WebView2 kept.$cleanup Edge may come back after a major Windows update; run UDP again if it does."
    }
    if ($edgeGone -and -not $Context.System.WebView2Installed) {
        return New-UdpStepResult -Status Success -Message "Edge removed.$cleanup WebView2 was not installed before UDP ran either; some apps may ask you to install it."
    }
    if ($edgeGone) {
        return New-UdpStepResult -Status Failed -Message 'Edge was removed but WebView2 is missing afterwards. Reinstall it from https://developer.microsoft.com/microsoft-edge/webview2/'
    }
    if ($exitCode -ne 0) {
        return New-UdpStepResult -Status Failed -Message ("$($tool.name) stopped with exit code $exitCode, so Edge's uninstaller probably did not run. The log shows its error. " +
            "If your antivirus reported dllhost.exe in $env:SystemRoot\SystemTemp, that was the script's temporary copy of cmd.exe.")
    }
    return New-UdpStepResult -Status Failed -Message "Edge is still installed after waiting 5 minutes ($(Get-UdpEdgeLeftoverText)). See the log, which includes the end of Edge's own uninstaller log."
}

function Get-UdpEdgeLeftoverText {
    $left = @()
    if (Test-UdpEdgeUninstallEntry) { $left += 'its entry in Settings > Apps is still there' }
    foreach ($path in @(Get-UdpEdgeExePaths)) { $left += "$path still exists" }
    if ($left.Count -eq 0) { return 'nothing left' }
    return ($left -join '; ')
}

# Edge's uninstaller can still be finishing (removing files, its Settings > Apps entry) when the
# script returns, so checking right away may report Edge as still installed. Wait until both its
# Settings > Apps entry and msedge.exe are gone, or until the timeout.
function Wait-UdpEdgeRemoved {
    param([int]$TimeoutSeconds = 300)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $announced = $false
    while ($true) {
        if (-not (Test-UdpEdgeInstalled)) {
            Write-UdpLog 'Edge is gone: no entry in Settings > Apps and no msedge.exe.' -Level Info
            return $true
        }
        if ((Get-Date) -ge $deadline) {
            Write-UdpLog "Edge is still present after waiting: $(Get-UdpEdgeLeftoverText)" -Level Warning
            return $false
        }
        if (-not $announced) {
            $wait = if ($TimeoutSeconds -ge 120) { "$([int]($TimeoutSeconds / 60)) minutes" } else { "$TimeoutSeconds seconds" }
            Write-UdpLog "Waiting for Edge's own uninstaller to finish (up to $wait): $(Get-UdpEdgeLeftoverText)" -Level Info
            $announced = $true
        }
        Start-Sleep -Seconds 3
    }
}
