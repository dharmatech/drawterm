# drawterm Windows/MSVC fork

This fork tracks 9front drawterm with a small set of Windows-focused
improvements.

## Changes from upstream

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

After installation:

```powershell
drawterm -h cpu.example -a auth.example -u glenda -G -c 'lc /'
```

## More information

- Upstream/9front README: [`README`](README)
- Automated Windows install/update and manual WSL/MinGW-w64 build notes:
  [`README.mingw-wsl.md`](README.mingw-wsl.md)
- MSVC build notes: [`README.msvc`](README.msvc)
