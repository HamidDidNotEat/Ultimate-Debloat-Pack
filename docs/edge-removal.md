# Edge removal

- **Author:** ave9858
- **Source:** <https://gist.github.com/ave9858/c3451d9f452389ac7607c99d45edecc6> ("Uninstall Microsoft Edge"), file `UninstallEdge.ps1`
- **License:** CC0-1.0 (public domain). UDP does not redistribute the script: it downloads it from the gist each time it runs.
- **Pinned version:** gist revision `abdd31d1d074154b16e48a92d44824ac1d5fc970` (2026-10-27), SHA256 `b3f35e4795e2d3d8989baad03c757089799375d70e81d5d9c58b5a3719908858`. Both are in `config/tools.json`.
- **Default:** off. Tick it on the Edge removal page.

## Why a script?

Microsoft lets you uninstall Edge normally only in the **European Economic Area (EEA)**, as part of complying with the EU Digital Markets Act. In Switzerland and every other non-EEA country, Edge's uninstaller refuses.

## What the script does

`UninstallEdge.ps1` is 41 lines of readable PowerShell, with no options and no questions. It:

1. Reads the uninstall command of Edge's entry in *Settings > Apps* (`HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge`) and adds `--force-uninstall`.
2. Deletes the `experiment_control_labels` value of Edge in Edge Update's `ClientState` key, if it exists.
3. Sets `AllowUninstall` (an empty string) in `HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev`.
4. Creates an empty placeholder, `C:\Windows\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe`, for the old built-in Edge.
5. Copies `cmd.exe` to `C:\Windows\SystemTemp\dllhost.exe`, runs the uninstall command through that copy with no window, and waits for it.
6. Deletes the placeholder and the copy of `cmd.exe` again (and the placeholder folder, if the script created it).

With these, Edge's own uninstaller accepts to run in every country. The script does not touch WebView2 or Edge Update, which keeps WebView2 up to date. The `AllowUninstall` value stays in the registry.

## How UDP runs it

1. Downloads the pinned revision and checks its SHA256. A mismatch skips the step.
2. Runs it unchanged with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...`, with no window, and streams its output into the log.
3. Waits until both Edge's entry in *Settings > Apps* and `msedge.exe` are gone: up to 5 minutes, or 15 seconds when the script stopped with an error (Edge's uninstaller then normally did not run).
4. Checks the result. The step succeeds when Edge is gone and WebView2 is still present. Otherwise the step fails, the log says exactly what is left and shows the last lines of Edge's own uninstaller log (`msedge_installer.log`).
5. Removes the leftover **Microsoft Edge** shortcuts on the desktop (yours and the all-users one) and in the Start menu. Only shortcuts that point to Edge's `msedge.exe` are removed, and only once Edge is gone.

If Edge was already removed (for example by an earlier run), the step skips the script and only removes leftover shortcuts.

## Why this script

Checked in November 2026:

| Tool | Why UDP does not use it |
|------|-------------------------|
| AveYo's `Edge_Removal.bat` (UDP 0.1.0 to 0.1.12) | Last changed in September 2023. It cannot remove Edge 120 or newer. |
| Win11Debloat's `-ForceRemoveEdge` | An older form of the same method: placeholder and `AllowUninstall`, without the `dllhost.exe` step that ave9858 added in October 2026. |
| he3als' EdgeRemover | Built from the same guide, without the newest step. Users report that it no longer works on Windows 11 25H2. |
| ShadowWhisperer's Remove-MS-Edge | Runs an old Edge installer from 2021, then force-deletes the rest, including Edge Update (WebView2 would stop getting updates), and edits Windows' app database directly. It also checks its downloads with `Get-FileHash`, which some Windows builds do not have. |

## Never without a browser

- **Order:** this step runs after the browser step.
- **In the wizard:** if no other browser is installed and the browser step is off, the Edge page shows a warning and requires explicit confirmation.
- **During the run:** UDP checks again. If no other browser is found, it asks before removing Edge.

## Things to know

- **Not supported by Microsoft** outside the EEA. Edge may come back after a major Windows feature update. Run UDP again: the step is skipped automatically when Edge is not installed.
- **Some system links** (some search results, widgets, help links) are `microsoft-edge:` links that only Edge opens. Without Edge, Windows says it needs an app to open them. Win11Debloat's recommended settings already turn off Bing results in search and widgets.
- **Antivirus:** a copy of `cmd.exe` named `dllhost.exe`, running from `C:\Windows\SystemTemp`, can look suspicious to security software. It only exists while Edge's uninstaller runs. If it is blocked, the step is marked as failed and the run continues.
- **Not yet confirmed on every Windows version.** The `dllhost.exe` step is from October 2026. If the removal fails for you, please [open an issue](https://github.com/HamidDidNotEat/Ultimate-Debloat-Pack/issues) with the log.

## Leftovers from UDP 0.1.12 and earlier

UDP 0.1.0 to 0.1.12 ran AveYo's `Edge_Removal.bat`. With Edge 120 or newer it removed Edge's Store packages but not the browser itself, and it installed a link redirect:

- `C:\Scripts\OpenWebSearch.cmd` and a copy of `ie_to_edge_stub.exe`
- *Image File Execution Options* entries that start the redirect instead of `msedge.exe` and `ie_to_edge_stub.exe`
- a scheduled task named `OpenWebSearchRepair`
- `microsoft-edge:` and `MSEdgeHTM` link handlers that point to the redirect
- Edge Update values meant to stop Windows from reinstalling Edge

That is why opening Edge on those PCs shows a tiny empty window: Edge is still installed, but the redirect starts instead.

**To finish the removal**, run the Edge step of UDP 0.1.13 or newer. It removes Edge itself. UDP leaves the redirect as it is; once Edge is gone it no longer gets in the way.

**To keep Edge instead**, remove the redirect in PowerShell started as administrator. This only removes entries that point to `OpenWebSearch`:

```powershell
$ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
foreach ($exe in 'msedge.exe', 'ie_to_edge_stub.exe') {
    $filter = "$ifeo\$exe\0"
    if ((Get-ItemProperty -LiteralPath $filter -ErrorAction SilentlyContinue).Debugger -like '*OpenWebSearch*') {
        Remove-Item -LiteralPath $filter -Recurse
        Remove-ItemProperty -LiteralPath "$ifeo\$exe" -Name UseFilter -ErrorAction SilentlyContinue
    }
}
Unregister-ScheduledTask -TaskName OpenWebSearchRepair -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$env:SystemDrive\Scripts\OpenWebSearch.cmd", "$env:SystemDrive\Scripts\ie_to_edge_stub.exe" -ErrorAction SilentlyContinue
```

Then repair Edge (*Settings > Apps > Installed apps > Microsoft Edge > Modify > Repair*) so its link handlers point to Edge again. AveYo's own way back, which also clears its Edge Update values, is to run `Edge_Removal.bat` again and type `edge` when it asks.

## How to undo

- Reinstall Edge from <https://www.microsoft.com/edge>.
- Or use the System Restore point UDP created at the start.
