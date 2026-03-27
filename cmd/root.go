package cmd

import (
	"context"
	"os"

	"github.com/spf13/cobra"
)

// version is set at build time by GoReleaser via ldflags.
var version = "dev"

var rootCmd = &cobra.Command{
	Use:     "wsl-screenshot-cli",
	Version: version,
	Short: "Monitor the Windows clipboard for screenshots, making them pasteable in WSL while preserving Windows paste functionality",
	Long: `wsl-screenshot-cli monitors the Windows clipboard for screenshots, making
them pasteable in WSL (e.g. Claude Code CLI, Codex CLI, ...) while preserving
Windows paste functionality.

A persistent powershell.exe -STA subprocess handles all clipboard access
via a stdin/stdout text protocol (CHECK / UPDATE / EXIT). The Go side polls
by sending CHECK commands; PowerShell uses pre-compiled .NET Clipboard APIs
(System.Windows.Forms.Clipboard) for change detection — no runtime C#
compilation, so it works even when EDR products block csc.exe. DoEvents()
pumps Windows messages to keep the STA thread responsive. When a new bitmap
is detected, it saves the PNG (deduplicated by SHA256 hash), sets three
Windows clipboard formats at once, and mirrors the image into the Linux
clipboard when a supported backend is available:

  CF_UNICODETEXT  — WSL path to the PNG, so you can paste in WSL terminals
  CF_BITMAP       — the original image data, preserving normal image paste
  CF_HDROP        — Windows UNC path as a file drop, preserving paste-as-file
  image/png       — Linux clipboard image data for WSL apps that read the
                    native clipboard API on Ctrl+V

After a screenshot, you can paste the file path in a WSL terminal and still
paste normally in Windows applications.`,
}

// ExecuteContext adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func ExecuteContext(ctx context.Context) {
	err := rootCmd.ExecuteContext(ctx)
	if err != nil {
		os.Exit(1)
	}
}

func init() {
	rootCmd.SilenceUsage = true
}
