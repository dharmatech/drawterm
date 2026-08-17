# Dharmatech Drawterm

This is a downstream of 9front drawterm that preserves the upstream project
layout while adding tested improvements for native Windows, Windows builds
from WSL, and high-DPI Wayland desktops.

## Changes from upstream

### Windows

- Builds on Windows using Microsoft Visual C via `NMakefile.msvc`.
  - Upstream 9front drawterm's Windows build path uses MinGW/Cygwin.
- Supports and documents building native Windows binaries from Ubuntu under
  WSL using MinGW-w64.
  - Upstream documents its MinGW build using Cygwin.
- Supports no-GUI command execution from PowerShell or cmd with
  `-G -c <cmd>`.
  - Output is written to the invoking console, and the shell waits for
    drawterm to exit before returning to the prompt.
  - Programs that request raw console mode receive Windows virtual-terminal
    input, including Alt chords encoded as an Escape-prefixed key.
  - UTF-8 output is rendered through the attached Windows console without
    mojibake, and the caller's original console output code page is restored
    when Drawterm exits.
  - Raw-mode `Ctrl-C` is delivered to the remote program, and console reads
    can be interrupted during clean shutdown so the invoking shell regains a
    usable prompt immediately.
  - Terminal rows, columns, and resize notifications are propagated to
    terminal applications running on Plan 9.

After installation:

```powershell
drawterm -h cpu.example -a auth.example -u glenda -G -c 'lc /'
```

### Linux and Wayland HiDPI

- Propagates terminal rows, columns, and resize notifications from interactive
  Linux `-G` sessions to terminal applications running on Plan 9.
- Honors the integer buffer scale advertised by the Wayland compositor.
- Supplies a high-resolution shared-memory buffer while preserving Plan 9
  screen and mouse coordinates.
- Avoids the extra low-resolution upscaling pass that previously softened
  bitmap fonts on HiDPI displays.

Build the Wayland version with its standard executable name:

```sh
make CONF=linux clean
make CONF=linux
```

The resulting executable is `./drawterm`. To install it for the current user:

```sh
make CONF=linux install
```

This installs `drawterm` in `~/.local/bin`. The destination can be overridden
with `BINDIR=/another/directory` when needed.

Integer desktop scaling such as 200% gives bitmap content exact pixel
alignment; fractional scaling still benefits from the higher-resolution
client buffer but requires a final compositor resampling step.

Always perform a clean build when changing `CONF` values. Object files are
shared between configurations and are not ABI-compatible in every case.

## Upstream relationship

The canonical upstream is 9front drawterm's `front` branch. Downstream changes
remain organized by platform so upstream can be merged periodically without
restructuring the source tree. Focused changes intended for upstream should be
prepared on topic branches based directly on the current upstream `front`.

## More information

- Upstream/9front README: [`README`](README)
- Automated Windows install/update and manual WSL/MinGW-w64 build notes:
  [`README.mingw-wsl.md`](README.mingw-wsl.md)
- MSVC build notes: [`README.msvc`](README.msvc)
