import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ExecResult {
  final String text;
  final String? screenshotB64;
  final String? fileB64;
  final String? fileName;

  ExecResult(this.text, [this.screenshotB64, this.fileB64, this.fileName]);
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

  Future<ExecResult> execute(String type, String payload, {String? geminiApiKey}) async {
    if (!Platform.isWindows) {
      return ExecResult('PC Agent can only run commands on Windows.');
    }
    try {
      switch (type) {
        case 'OPEN_APP':
          return await _openApp(payload);

        case 'OPEN_URL':
          await Process.run('cmd', ['/c', 'start', '', payload]);
          return ExecResult('Opened URL: $payload');

        case 'SCREENSHOT':
          return await _screenshot();

        case 'SCREEN_VISION':
          return await _screenVision(payload, geminiApiKey: geminiApiKey);

        case 'WEBCAM_CAPTURE':
          return await _webcamCapture();

        case 'CLIPBOARD_GET':
          return await _clipboardGet();

        case 'CLIPBOARD_SET':
          return await _clipboardSet(payload);

        case 'FILE_FETCH':
          return await _fileFetch(payload);

        case 'FILE_LIST':
          return await _fileList(payload);

        case 'BATTERY_GUARD':
        case 'STATUS':
          return await _status();

        case 'SCHEDULE_TASK':
          return await _scheduleTask(payload);

        case 'LOCK':
          await Process.run('rundll32.exe', ['user32.dll,LockWorkStation']);
          return ExecResult('PC locked securely.');

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
          return ExecResult('Maliha said: $payload');

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
    if (b64.length < 100) return ExecResult('Screenshot capture failed on the PC.');
    return ExecResult('Screenshot taken successfully.', b64);
  }

  /// Stealth Webcam Capture using Windows avicap32
  Future<ExecResult> _webcamCapture() async {
    const script = r'''
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Windows.Forms;

public class WebcamCapture {
    [DllImport("avicap32.dll", EntryPoint="capCreateCaptureWindowA")]
    public static extern IntPtr capCreateCaptureWindowA(string lpszWindowName, int dwStyle, int x, int y, int nWidth, int nHeight, IntPtr hWnd, int nID);

    [DllImport("user32.dll")]
    public static extern bool SendMessage(IntPtr hWnd, uint Msg, int wParam, int lParam);

    [DllImport("user32.dll")]
    public static extern bool DestroyWindow(IntPtr hWnd);

    public const uint WM_CAP_START = 0x400;
    public const uint WM_CAP_DRIVER_CONNECT = WM_CAP_START + 10;
    public const uint WM_CAP_DRIVER_DISCONNECT = WM_CAP_START + 11;
    public const uint WM_CAP_GRAB_FRAME = WM_CAP_START + 60;
    public const uint WM_CAP_EDIT_COPY = WM_CAP_START + 30;

    public static string CaptureBase64() {
        IntPtr hWnd = capCreateCaptureWindowA("WebcamCapture", 0, 0, 0, 640, 480, IntPtr.Zero, 0);
        if (hWnd == IntPtr.Zero) return "ERROR_INIT";
        try {
            if (!SendMessage(hWnd, WM_CAP_DRIVER_CONNECT, 0, 0)) {
                return "ERROR_NO_CAMERA";
            }
            SendMessage(hWnd, WM_CAP_GRAB_FRAME, 0, 0);
            SendMessage(hWnd, WM_CAP_EDIT_COPY, 0, 0);
            SendMessage(hWnd, WM_CAP_DRIVER_DISCONNECT, 0, 0);

            if (Clipboard.ContainsImage()) {
                Image img = Clipboard.GetImage();
                using (System.IO.MemoryStream ms = new System.IO.MemoryStream()) {
                    img.Save(ms, System.Drawing.Imaging.ImageFormat.Jpeg);
                    return Convert.ToBase64String(ms.ToArray());
                }
            }
            return "ERROR_GRAB";
        } finally {
            DestroyWindow(hWnd);
        }
    }
}
"@ -ReferencedAssemblies "System.Drawing", "System.Windows.Forms"

[WebcamCapture]::CaptureBase64()
''';
    final out = await _ps(script);
    if (out.contains('ERROR_NO_CAMERA') || out.isEmpty) {
      return ExecResult('📷 Stealth Webcam Sentry: No active webcam or camera device detected on this PC.');
    }
    if (out.length < 200) {
      return ExecResult('📷 Webcam capture failed: ' + out);
    }
    return ExecResult('📷 Stealth Webcam Snapshot captured by Maliha.', out);
  }

  /// Screen Vision: Captures screen and passes image + prompt to Gemini Vision
  Future<ExecResult> _screenVision(String userPrompt, {String? geminiApiKey}) async {
    final shotRes = await _screenshot();
    if (shotRes.screenshotB64 == null) {
      return ExecResult('Could not capture screen for Vision AI analysis.');
    }

    final key = geminiApiKey?.trim();
    if (key == null || key.isEmpty) {
      return ExecResult('📸 Screen captured. To activate Vision Analysis, set your Gemini API key in Settings.', shotRes.screenshotB64);
    }

    try {
      final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$key');
      final promptText = userPrompt.trim().isEmpty
          ? 'Describe what is currently visible on this Windows PC screen in detail. Mention active apps, open documents, or any visible errors.'
          : userPrompt.trim();

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': 'You are Maliha AI Desktop Assistant. Provide a clear, intelligent explanation of this PC screen in Bengali and English: ' + promptText},
                {
                  'inlineData': {
                    'mimeType': 'image/jpeg',
                    'data': shotRes.screenshotB64,
                  }
                }
              ]
            }
          ],
          'generationConfig': {'temperature': 0.2, 'maxOutputTokens': 1000}
        }),
      ).timeout(const Duration(seconds: 18));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        final answer = data['candidates']?[0]?['content']?['parts']?[0]?['text']?.toString();
        if (answer != null && answer.isNotEmpty) {
          return ExecResult('👁️ Maliha Screen Vision Analysis:\n\n' + answer.trim(), shotRes.screenshotB64);
        }
      }
    } catch (e) {
      // Vision API failed, return screenshot with error notice
      return ExecResult('📸 Screen captured. Vision API request failed: $e', shotRes.screenshotB64);
    }

    return ExecResult('📸 Screen captured successfully.', shotRes.screenshotB64);
  }

  /// Get PC Clipboard contents
  Future<ExecResult> _clipboardGet() async {
    final out = await _ps('Get-Clipboard -Raw');
    if (out.trim().isEmpty) {
      return ExecResult('📋 Windows Clipboard is currently empty.');
    }
    return ExecResult('📋 Windows PC Clipboard:\n$out');
  }

  /// Set PC Clipboard contents
  Future<ExecResult> _clipboardSet(String payload) async {
    final safe = payload.replaceAll("'", "''");
    await _ps("Set-Clipboard -Value '$safe'");
    return ExecResult('📋 Copied to Windows PC Clipboard: "$payload"');
  }

  /// Fetch a file from Desktop / Downloads / Documents and encode to base64
  Future<ExecResult> _fileFetch(String query) async {
    final safe = query.replaceAll("'", "''").replaceAll('"', '').trim();
    if (safe.isEmpty) {
      return ExecResult('Please specify a file name to fetch (e.g. file fetch resume.pdf).');
    }

    final script = '''
\$search = '$safe'
\$folders = @(
  [Environment]::GetFolderPath('Desktop'),
  [Environment]::GetFolderPath('MyDocuments'),
  ("\$env:USERPROFILE\\Downloads")
)
\$found = \$null
foreach (\$f in \$folders) {
  if (Test-Path \$f) {
    \$match = Get-ChildItem -Path \$f -Filter "*\$search*" -Recurse -Depth 2 -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (\$match) { \$found = \$match; break }
  }
}

if (-not \$found -and (Test-Path \$search)) {
  \$found = Get-Item \$search
}

if (\$found) {
  \$len = \$found.Length
  if (\$len -gt 4194304) {
    "LARGE|" + \$found.Name + "|" + [math]::Round(\$len / 1MB, 2) + " MB|" + \$found.FullName
  } else {
    \$b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes(\$found.FullName))
    "OK|" + \$found.Name + "|" + [math]::Round(\$len / 1KB, 1) + " KB|" + \$b64
  }
} else {
  "NOT_FOUND|" + \$search
}
''';

    final res = await _ps(script);
    if (res.startsWith('OK|')) {
      final parts = res.split('|');
      final name = parts.length > 1 ? parts[1] : 'file';
      final size = parts.length > 2 ? parts[2] : '';
      final b64 = parts.length > 3 ? parts[3] : '';
      return ExecResult('📁 File fetched: $name ($size)', null, b64, name);
    } else if (res.startsWith('LARGE|')) {
      final parts = res.split('|');
      final name = parts.length > 1 ? parts[1] : 'file';
      final size = parts.length > 2 ? parts[2] : '';
      final path = parts.length > 3 ? parts[3] : '';
      return ExecResult('📁 File located: $name ($size at $path). Too large for instant cloud transfer (>4MB).');
    } else {
      return ExecResult('📁 File not found: "$query" in Desktop, Downloads, or Documents.');
    }
  }

  /// List files in specified directory (Desktop, Downloads, Documents)
  Future<ExecResult> _fileList(String folder) async {
    final lower = folder.toLowerCase();
    String target = "[Environment]::GetFolderPath('Desktop')";
    if (lower.contains('download')) target = '"\$env:USERPROFILE\\Downloads"';
    if (lower.contains('document')) target = "[Environment]::GetFolderPath('MyDocuments')";

    final script = '''
\$target = $target
if (Test-Path \$target) {
  Get-ChildItem -Path \$target -File | Select-Object -First 8 Name, Length | ForEach-Object {
    \$_.Name + " (" + [math]::Round(\$_.Length / 1KB, 1) + " KB)"
  }
}
''';
    final out = await _ps(script);
    if (out.trim().isEmpty) return ExecResult('📁 No files found in the requested directory.');
    return ExecResult('📁 Directory Listing:\n$out');
  }

  /// Schedule a delayed task (e.g. "30 shutdown", "15 lock", "60 restart")
  Future<ExecResult> _scheduleTask(String payload) async {
    final parts = payload.trim().split(RegExp(r'\s+'));
    int delayMinutes = 30;
    String action = 'shutdown';

    if (parts.isNotEmpty) {
      final numParsed = int.tryParse(parts[0]);
      if (numParsed != null) {
        delayMinutes = numParsed;
        if (parts.length > 1) action = parts.sublist(1).join(' ').toLowerCase();
      } else {
        action = payload.toLowerCase();
      }
    }

    final seconds = delayMinutes * 60;
    if (action.contains('shutdown') || action.contains('শাটডাউন')) {
      await Process.run('shutdown', ['/s', '/t', seconds.toString()]);
      return ExecResult('⏰ Scheduled PC Shutdown in $delayMinutes minute(s). Send "cancel shutdown" to stop.');
    } else if (action.contains('restart') || action.contains('রিস্টার্ট')) {
      await Process.run('shutdown', ['/r', '/t', seconds.toString()]);
      return ExecResult('⏰ Scheduled PC Restart in $delayMinutes minute(s). Send "cancel shutdown" to stop.');
    } else {
      // Background delayed PowerShell trigger
      final safe = action.replaceAll("'", "''");
      final script = "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile -Command Start-Sleep -Seconds $seconds; $safe'";
      await _ps(script);
      return ExecResult('⏰ Scheduled task "$action" to run in $delayMinutes minute(s).');
    }
  }

  /// Combined PC telemetry + Battery & Power Status
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

Add-Type -AssemblyName System.Windows.Forms
$p = [System.Windows.Forms.SystemInformation]::PowerStatus
$battPct = [int]($p.BatteryLifePercent * 100)
$acStatus = $p.PowerLineStatus.ToString()

"CPU: $cpu% | RAM: $used GB / $total GB | Disk C: $diskFree GB free / $diskTotal GB | Battery: $battPct% ($acStatus)"
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
