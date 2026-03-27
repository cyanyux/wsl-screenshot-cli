Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Uses pre-compiled .NET Clipboard APIs for change detection instead of a
# runtime-compiled C# class (Add-Type -TypeDefinition). Runtime C# compilation
# requires csc.exe, which EDR products (SentinelOne, CrowdStrike, etc.) block
# as a "living off the land" binary. The pre-compiled APIs work everywhere.
#
# The main loop still pumps messages via DoEvents() so the STA thread stays
# responsive, preventing Explorer/Snipping Tool freezes during OLE/COM
# clipboard operations.

[Console]::Out.WriteLine("READY")
[Console]::Out.Flush()

$readTask = [Console]::In.ReadLineAsync()

while ($true) {
    # Pump Windows messages so other apps' clipboard operations (OLE/COM)
    # don't time out waiting for our STA apartment to respond.
    [System.Windows.Forms.Application]::DoEvents()

    if (-not $readTask.IsCompleted) {
        Start-Sleep -Milliseconds 10
        continue
    }

    $line = $readTask.Result
    if ($line -eq $null -or $line -eq "EXIT") { break }

    if ($line -eq "CHECK") {
        try {
            # Skip if no image on clipboard
            if (-not [System.Windows.Forms.Clipboard]::ContainsImage()) {
                [Console]::Out.WriteLine("NONE")
                [Console]::Out.Flush()
                $readTask = [Console]::In.ReadLineAsync()
                continue
            }

            # Rich text copies from Office apps often include a preview bitmap
            # alongside the real text payload. Do not treat those as screenshots.
            # The only text-bearing image shape we still accept is the legacy
            # wscli-managed clipboard item from older builds, which included a
            # text path plus a file drop list.
            if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                if ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) {
                    try {
                        $text = [System.Windows.Forms.Clipboard]::GetText()
                        if (-not [string]::IsNullOrWhiteSpace($text)) {
                            [Console]::Out.WriteLine("PATH")
                            [Console]::Out.WriteLine($text)
                            [Console]::Out.WriteLine("END")
                            [Console]::Out.Flush()
                        } else {
                            [Console]::Out.WriteLine("NONE")
                            [Console]::Out.Flush()
                        }
                    } catch {
                        [Console]::Out.WriteLine("NONE")
                        [Console]::Out.Flush()
                    }
                } else {
                    [Console]::Out.WriteLine("NONE")
                    [Console]::Out.Flush()
                }
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
                # Clear first so stale wscli text/file-drop formats from an
                # earlier clipboard item do not survive onto the new image.
                [System.Windows.Forms.Clipboard]::Clear()
                [System.Windows.Forms.Clipboard]::SetDataObject($data, $true)
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

    $readTask = [Console]::In.ReadLineAsync()
}
