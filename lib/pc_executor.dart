import 'dart:io';

class ExecResult {
  final String text;
  final String? screenshotB64;
  ExecResult(this.text, [this.screenshotB64]);
}

/// Executes commands on the Windows PC. Only ever called in PC Agent mode
/// on Windows; every branch is guarded so other platforms fail politely.
class PcExecutor {
  static const _apps = <String, String>{
    'notepad': 'notepad.exe',
    'calculator': 'calc.exe',
    'chrome': 'chrome',
    'code': 'code',
    'explorer': 'explorer.exe',
    'paint': 'mspaint.exe',
    'taskmgr': 'Taskmgr.exe',
    'cmd': 'cmd.exe',
    'powershell': 'powershell.exe',
  };

  Future<ExecResult> execute(String type, String payload) async {
    if (!Platform.isWindows) {
      return ExecResult('PC Agent can only run commands on Windows.');
    }
    try {
      switch (type) {
        case 'OPEN_APP':
          return await _openApp(payload);
        case 'OPEN_URL':
          await Process.run('cmd', ['/c', 'start', '', payload]);
          return ExecResult('Opened: $payload');
        case 'SCREENSHOT':
          return await _screenshot();
        case 'STATUS':
          return await _status();
        case 'LOCK':
          await Process.run('rundll32.exe', ['user32.dll,LockWorkStation']);
          return ExecResult('PC locked.');
        case 'SHUTDOWN':
          await Process.run('shutdown', ['/s', '/t', '60']);
          return ExecResult('Shutdown scheduled in 60 seconds. Send cancel shutdown to stop it.');
        case 'RESTART':
          await Process.run('shutdown', ['/r', '/t', '60']);
          return ExecResult('Restart scheduled in 60 seconds. Send cancel shutdown to stop it.');
        case 'CANCEL_SHUTDOWN':
          await Process.run('shutdown', ['/a']);
          return ExecResult('Shutdown/restart cancelled.');
        case 'SPEAK':
          final safe = payload.replaceAll("'", "''");
          await _ps(
              "Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('$safe')");
          return ExecResult('Said: $payload');
        case 'POWERSHELL':
          final out = await _ps(payload);
          return ExecResult(out.isEmpty ? 'PowerShell command executed successfully.' : out);
        default:
          return ExecResult('Unknown command type: $type');
      }
    } catch (e) {
      return ExecResult('Failed: $e');
    }
  }

  Future<ExecResult> _openApp(String payload) async {
    final key = payload.trim().toLowerCase();
    final target = _apps[key] ?? payload.trim();
    final res = await Process.run(
        'powershell', ['-NoProfile', '-Command', 'Start-Process "' + target + '"']);
    if (res.exitCode != 0) {
      return ExecResult(('Could not open "' + payload + '". ' + res.stderr.toString()).trim());
    }
    return ExecResult('Opened app: $payload');
  }

  Future<String> _ps(String script) async {
    final res = await Process.run(
        'powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script]);
    return (res.stdout as String).trim();
  }

  Future<ExecResult> _screenshot() async {
    const script = r'''
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$target = $bmp
if ($bmp.Width -gt 1280) {
  $h = [int]($bmp.Height * 1280 / $bmp.Width)
  $target = New-Object System.Drawing.Bitmap($bmp, 1280, $h)
}
$ms = New-Object System.IO.MemoryStream
$target.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg)
[Convert]::ToBase64String($ms.ToArray())
''';
    final b64 = await _ps(script);
    if (b64.length < 100) return ExecResult('Screenshot failed on the PC.');
    return ExecResult('Screenshot taken.', b64);
  }

  Future<ExecResult> _status() async {
    const script = r'''
$os = Get-CimInstance Win32_OperatingSystem
$cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
$total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$free = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$used = [math]::Round($total - $free, 1)
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$diskFree = [math]::Round($disk.FreeSpace / 1GB, 1)
$diskTotal = [math]::Round($disk.Size / 1GB, 1)
"CPU: $cpu% | RAM: $used GB used / $total GB | Disk C: $diskFree GB free / $diskTotal GB"
''';
    final out = await _ps(script);
    return ExecResult(out.isEmpty ? 'Could not read PC status.' : out);
  }

  /// Adds the agent to the Windows Startup folder so it runs at logon.
  Future<bool> enableAutostart() async {
    if (!Platform.isWindows) return false;
    final exe = Platform.resolvedExecutable.replaceAll("'", "''");
    final script =
        "\$s = (New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup') + '\\PC Assistant.lnk'); \$s.TargetPath = '" + exe + "'; \$s.Save()";
    final res = await Process.run(
        'powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script]);
    return res.exitCode == 0;
  }
}
