package linuxclipboard

import (
	"errors"
	"io"
	"log"
	"os"
	"reflect"
	"testing"
)

func overrideLookPath(t *testing.T, fn func(string) (string, error)) {
	t.Helper()
	orig := lookPath
	lookPath = fn
	t.Cleanup(func() { lookPath = orig })
}

func overrideRunCommand(t *testing.T, fn func(string, []string, []byte) error) {
	t.Helper()
	orig := runCommand
	runCommand = fn
	t.Cleanup(func() { runCommand = orig })
}

func TestSyncImage_PrefersWayland(t *testing.T) {
	t.Setenv("WAYLAND_DISPLAY", "wayland-0")
	t.Setenv("DISPLAY", ":0")

	overrideLookPath(t, func(name string) (string, error) {
		if name == "wl-copy" {
			return "/usr/bin/wl-copy", nil
		}
		return "", errors.New("not found")
	})

	var gotName string
	var gotArgs []string
	var gotData []byte
	overrideRunCommand(t, func(name string, args []string, pngData []byte) error {
		gotName = name
		gotArgs = append([]string(nil), args...)
		gotData = append([]byte(nil), pngData...)
		return nil
	})

	data := []byte("png")
	if err := SyncImage(log.New(io.Discard, "", 0), data); err != nil {
		t.Fatalf("SyncImage() error = %v", err)
	}

	if gotName != "wl-copy" {
		t.Fatalf("backend = %q, want wl-copy", gotName)
	}
	if !reflect.DeepEqual(gotArgs, []string{"--type", "image/png"}) {
		t.Fatalf("args = %#v", gotArgs)
	}
	if string(gotData) != string(data) {
		t.Fatalf("png data mismatch")
	}
}

func TestSyncImage_FallsBackToXclip(t *testing.T) {
	t.Setenv("WAYLAND_DISPLAY", "")
	t.Setenv("DISPLAY", ":0")

	overrideLookPath(t, func(name string) (string, error) {
		if name == "xclip" {
			return "/usr/bin/xclip", nil
		}
		return "", os.ErrNotExist
	})

	var gotName string
	overrideRunCommand(t, func(name string, args []string, pngData []byte) error {
		gotName = name
		return nil
	})

	if err := SyncImage(nil, []byte("png")); err != nil {
		t.Fatalf("SyncImage() error = %v", err)
	}

	if gotName != "xclip" {
		t.Fatalf("backend = %q, want xclip", gotName)
	}
}

func TestSyncImage_Unavailable(t *testing.T) {
	t.Setenv("WAYLAND_DISPLAY", "")
	t.Setenv("DISPLAY", "")

	overrideLookPath(t, func(name string) (string, error) {
		return "", os.ErrNotExist
	})

	err := SyncImage(nil, []byte("png"))
	if !errors.Is(err, ErrUnavailable) {
		t.Fatalf("SyncImage() error = %v, want ErrUnavailable", err)
	}
}
