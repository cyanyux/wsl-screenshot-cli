package linuxclipboard

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"strings"
)

// ErrUnavailable indicates that no supported Linux clipboard backend was found.
var ErrUnavailable = errors.New("no supported Linux clipboard backend found")

type backend struct {
	name string
	args []string
}

var lookPath = exec.LookPath

var runCommand = func(name string, args []string, pngData []byte) error {
	cmd := exec.Command(name, args...)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("stdin pipe: %w", err)
	}

	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Start(); err != nil {
		stdin.Close()
		return fmt.Errorf("start: %w", err)
	}

	if _, err := io.Copy(stdin, bytes.NewReader(pngData)); err != nil {
		stdin.Close()
		cmd.Wait()
		return fmt.Errorf("write png: %w", err)
	}

	if err := stdin.Close(); err != nil {
		cmd.Wait()
		return fmt.Errorf("close stdin: %w", err)
	}

	if err := cmd.Wait(); err != nil {
		if msg := strings.TrimSpace(stderr.String()); msg != "" {
			return fmt.Errorf("%w: %s", err, msg)
		}
		return err
	}

	return nil
}

// SyncImage mirrors the PNG into the Linux clipboard so apps running inside
// WSL that read the native clipboard API on Ctrl+V can see an image target.
func SyncImage(logger *log.Logger, pngData []byte) error {
	b, err := detectBackend()
	if err != nil {
		return err
	}

	if err := runCommand(b.name, b.args, pngData); err != nil {
		return fmt.Errorf("%s: %w", b.name, err)
	}

	if logger != nil {
		logger.Printf("Linux clipboard updated (%s)", b.name)
	}
	return nil
}

func detectBackend() (backend, error) {
	if os.Getenv("WAYLAND_DISPLAY") != "" {
		if _, err := lookPath("wl-copy"); err == nil {
			return backend{name: "wl-copy", args: []string{"--type", "image/png"}}, nil
		}
	}

	if os.Getenv("DISPLAY") != "" {
		if _, err := lookPath("xclip"); err == nil {
			return backend{name: "xclip", args: []string{"-selection", "clipboard", "-t", "image/png", "-i"}}, nil
		}
	}

	return backend{}, ErrUnavailable
}
