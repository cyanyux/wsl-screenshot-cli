Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ClipboardListener: a NativeWindow that receives WM_CLIPBOARDUPDATE messages
# via AddClipboardFormatListener. This replaces GetClipboardSequenceNumber polling
# and, crucially, the main loop pumps messages via DoEvents() so the STA thread
# stays responsive — preventing Explorer/Snipping Tool freezes.
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Windows.Forms;
using System.Runtime.InteropServices;

public class ClipboardListener : NativeWindow, IDisposable {
    private const int WM_CLIPBOARDUPDATE = 0x031D;

    [DllImport("user32.dll")]
    private static extern bool AddClipboardFormatListener(IntPtr hwnd);
    [DllImport("user32.dll")]
    private static extern bool RemoveClipboardFormatListener(IntPtr hwnd);
    [DllImport("user32.dll")]
    public static extern bool IsClipboardFormatAvailable(uint format);

    public bool Changed { get; set; }

    public ClipboardListener() {
        CreateHandle(new CreateParams());
        AddClipboardFormatListener(Handle);
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_CLIPBOARDUPDATE) {
            Changed = true;
        }
        base.WndProc(ref m);
    }

    public void Dispose() {
        RemoveClipboardFormatListener(Handle);
        DestroyHandle();
    }
}
'@

$listener = New-Object ClipboardListener

[Console]::Out.WriteLine("READY")
[Console]::Out.Flush()

# Start async stdin read (non-blocking — keeps the STA thread free to pump messages)
$readTask = [Console]::In.ReadLineAsync()

while ($true) {
    # CRITICAL: pump Windows messages so other apps' clipboard operations
    # (OLE/COM) don't time out waiting for our STA apartment to respond.
    [System.Windows.Forms.Application]::DoEvents()

    if (-not $readTask.IsCompleted) {
        Start-Sleep -Milliseconds 10
        continue
    }

    $line = $readTask.Result
    if ($line -eq $null -or $line -eq "EXIT") { break }

    if ($line -eq "CHECK") {
        try {
            # Event-driven: skip if no clipboard change since last check
            if (-not $listener.Changed) {
                [Console]::Out.WriteLine("NONE")
                [Console]::Out.Flush()
                $readTask = [Console]::In.ReadLineAsync()
                continue
            }
            $listener.Changed = $false

            # Lock-free check: skip if no bitmap format on clipboard
            # CF_BITMAP=2, CF_DIB=8. Avoids locking for text/file copies.
            if (-not ([ClipboardListener]::IsClipboardFormatAvailable(2) -or
                      [ClipboardListener]::IsClipboardFormatAvailable(8))) {
                [Console]::Out.WriteLine("NONE")
                [Console]::Out.Flush()
                $readTask = [Console]::In.ReadLineAsync()
                continue
            }

            # Fingerprint check: if all 3 of our formats are still present
            # (CF_BITMAP=2, CF_UNICODETEXT=13, CF_HDROP=15), the clipboard
            # still holds our previous write — no new image to process.
            if ([ClipboardListener]::IsClipboardFormatAvailable(2) -and
                [ClipboardListener]::IsClipboardFormatAvailable(13) -and
                [ClipboardListener]::IsClipboardFormatAvailable(15)) {
                [Console]::Out.WriteLine("NONE")
                [Console]::Out.Flush()
                $readTask = [Console]::In.ReadLineAsync()
                continue
            }

            $img = [System.Windows.Forms.Clipboard]::GetImage()
            if ($img -eq $null) {
                [Console]::Out.WriteLine("NONE")
                [Console]::Out.Flush()
            } else {
                try {
                    $ms = New-Object System.IO.MemoryStream
                    $img.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                    $bytes = $ms.ToArray()
                    $ms.Dispose()
                    $b64 = [Convert]::ToBase64String($bytes)
                    [Console]::Out.WriteLine("IMAGE")
                    [Console]::Out.WriteLine($b64)
                    [Console]::Out.WriteLine("END")
                    [Console]::Out.Flush()
                } finally {
                    $img.Dispose()
                }
            }
        } catch {
            [Console]::Out.WriteLine("NONE")
            [Console]::Out.Flush()
        }
    }
    elseif ($line.StartsWith("UPDATE|")) {
        $parts = $line.Split("|")
        $wslPath = $parts[1]
        $winPath = $parts[2]
        try {
            $img = [System.Drawing.Image]::FromFile($winPath)
            try {
                $data = New-Object System.Windows.Forms.DataObject
                $data.SetImage($img)
                $data.SetText($wslPath, [System.Windows.Forms.TextDataFormat]::UnicodeText)

                $files = New-Object System.Collections.Specialized.StringCollection
                [void]$files.Add($winPath)
                $data.SetFileDropList($files)

                [System.Windows.Forms.Clipboard]::SetDataObject($data, $true)
                # Suppress the WM_CLIPBOARDUPDATE from our own write
                $listener.Changed = $false
                [Console]::Out.WriteLine("OK")
                [Console]::Out.Flush()
            } finally {
                $img.Dispose()
            }
        } catch {
            [Console]::Out.WriteLine("ERR|" + $_.Exception.Message)
            [Console]::Out.Flush()
        }
    }

    # Start next async read
    $readTask = [Console]::In.ReadLineAsync()
}

$listener.Dispose()
