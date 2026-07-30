# Completed handoff: Cross-compile the Drawterm fork for Windows in WSL

> Status: completed on 2026-07-30 and merged into `main` as commit `c969d22`.
> This file is retained in this commit as a historical snapshot and is not
> active project guidance.

## Completion record

- The unchanged `-mwindows` MinGW baseline was built and recorded.
- The final MinGW executable uses the Windows console subsystem while retaining
  `WinMainCRTStartup`.
- PowerShell and `cmd.exe` waiting, output, redirection, and exit behavior were
  verified.
- Normal graphical startup and `-G -c` operation were tested against the
  project scratch VM.
- The shared Win32 change was cleanly rebuilt and smoke-tested with MSVC.
- The manual Ubuntu/WSL workflow is documented in `README.mingw-wsl.md`.

## Objective

Build this Drawterm fork in Ubuntu under WSL with the existing MinGW-w64
cross-compilation infrastructure. The result must be a native 64-bit Windows
`drawterm.exe`, not a Linux executable, and it must not require WSL or Cygwin at
runtime.

The final MinGW executable should match the established MSVC behavior:

- `drawterm.exe` is the one canonical executable.
- Normal invocation opens the Drawterm GUI.
- Uppercase `-G` disables graphics.
- `-G -c <command>` works as a proper console command: output is visible, the
  invoking shell waits, redirection works, and the process exits correctly.

This is additive work. Preserve the existing native MSVC/NMake build and the
upstream non-MSVC build paths.

## Settled design decisions

1. The first supported WSL workflow is transparent and manual. Clone, build,
   inspect, test, and copy the artifact using explicit WSL and Windows commands.
2. Build from a separate clone in WSL's native Linux filesystem, not from the
   Windows checkout under `/mnt/c`.
3. Record an unchanged `Make.win64` build before editing anything.
4. The unchanged configuration currently uses `-mwindows`, which selects the
   Windows GUI subsystem. That is the baseline, not the intended final behavior.
5. The intended final MinGW binary uses the Windows console subsystem, matching
   the current MSVC binary while preserving correct Windows command-line
   parsing and normal GUI operation.
6. Do not use the Windows 11-only detached-console manifest. Do not restrict the
   fork to Windows 11.
7. Do not add `rundrawterm.exe`, `drawtermw.exe`, `drawterm-gui.exe`, or another
   GUI launcher in this workstream. A small GUI launcher remains a possible
   future enhancement.
8. Do not create PowerShell build automation yet. A future script may automate
   the proven manual workflow.
9. Stage the verified result in the Windows checkout at
   `build\mingw-wsl\drawterm.exe`.
10. `%LOCALAPPDATA%\Programs\Drawterm` is the preferred future per-user
    installation directory, but installation and `PATH` management are not part
    of this task.
11. Do not introduce CMake, Ninja, or another build-system redesign.

## Repository context

- Windows checkout: `C:\Users\dharm\src\drawterm`
- GitHub origin: `https://github.com/dharmatech/drawterm.git`
- Starting branch: `main`
- Starting commit: `8958bdbc84f56f4a05df586e92a8d85e7ca29f07`
- Upstream 9front remote: `git://git.9front.org/plan9front/drawterm`
- Existing MSVC build: `NMakefile.msvc`
- Existing MinGW-w64 configuration: `Make.win64`
- Expected baseline command: `make CONF=win64`
- Confirmed WSL distribution: `Ubuntu` on WSL 2
- WSL-side working clone: `~/src/drawterm-dharmatech`
- WSL-side 9fans reference clone: `~/src/drawterm-9fans`
- WSL-side 9front reference clone: `~/src/drawterm-9front`
- Working branch: `codex/wsl-mingw-build`
- Final Windows staging path:
  `C:\Users\dharm\src\drawterm\build\mingw-wsl\drawterm.exe`

The tracked Drawterm repository was clean at the starting commit. The
`docs/design` directory containing this handoff is currently untracked.
The Windows repository's `.gitignore` already excludes `build/`, so staging the
result under `build\mingw-wsl` will not add the binary to Git accidentally.

The `-dharmatech` suffix is only a local organizational convention for keeping
the three WSL comparison clones distinct. The project, repository, and
executable remain named Drawterm. User-facing documentation should assume that
an ordinary clone is named `drawterm`.

## WSL execution and safety

The global `wsl-windows-local` skill applies to this task. Read it before the
first WSL operation.

Codex is running on the Windows host. Every `wsl.exe` command must run outside
the Windows sandbox on the first attempt with the required approval. Do not
probe WSL inside the sandbox first.

The user has WSL and Ubuntu installed. `Ubuntu` on WSL 2 was confirmed during
planning. Verify the registered distribution name at kickoff with:

```powershell
wsl.exe --list --verbose
```

Do not assume that the registered name is literally `Ubuntu`.

Inspect the Ubuntu release and existing toolchain before installing anything.
Likely requirements include Git, GNU Make, and the x86-64 MinGW-w64 GCC and
binutils packages (`gcc-mingw-w64-x86-64` and
`binutils-mingw-w64-x86-64`). Install only missing requirements. Package
installation may require network access and an interactive `sudo` password.
Never print, store, or repeat passwords.

Do not delete or overwrite an existing WSL clone or branch without inspecting
it and obtaining direction when its ownership or purpose is unclear.

## Source and branch strategy

Do not build in `C:\Users\dharm\src\drawterm` through `/mnt/c`. The GNU make
system writes `.o` and `.a` files throughout the source tree, and Linux build
tools perform better on WSL's native filesystem.

Prefer a separate WSL-side clone:

```sh
git clone https://github.com/dharmatech/drawterm.git ~/src/drawterm-dharmatech
cd ~/src/drawterm-dharmatech
```

If network access prevents cloning from GitHub, a local clone from the Windows
checkout is an acceptable fallback, but restore the GitHub `origin` afterward.

Treat `~/src/drawterm-9fans` and `~/src/drawterm-9front` as reference trees, not
as inputs to this build. Do not modify or clean them as part of this workstream.

Verify the starting commit, then create:

```sh
git switch -c codex/wsl-mingw-build
```

Create the branch before building. Do not edit source or build files until the
unchanged baseline has been attempted and recorded. Do not commit or push
without the user's request.

## Important terminology

These are separate layers:

- **WSL** is the Linux environment hosting the cross-compiler.
- **MinGW-w64** emits a native Windows PE executable.
- **`-mwindows`** selects the Windows GUI subsystem; it does not enable console
  behavior.
- **The console subsystem** tells PowerShell and `cmd.exe` to wait and provides
  normal standard-handle behavior.
- **Uppercase `-G`** is Drawterm's runtime no-graphics option.
- **Lowercase `-g`** is a different Drawterm option related to GUI geometry.

The operating system reads the PE subsystem before Drawterm parses `-G`.
Attaching to a parent console later may recover handles, but it does not
reliably make the invoking shell wait. The final solution therefore needs the
correct PE subsystem at link time.

## Phase 1: unchanged baseline

1. Record:
   - Exact WSL distribution name and Ubuntu release
   - Git commit and branch
   - GNU Make version
   - `x86_64-w64-mingw32-gcc` and binutils versions
2. Confirm that `Make.win64` still contains the upstream-style `-mwindows`
   configuration.
3. From a clean WSL clone, run:

   ```sh
   make CONF=win64
   ```

4. Capture all warnings and errors before changing files.
5. If compilation fails, preserve the exact first failure. Diagnose it before
   making the smallest necessary additive correction on the branch.
6. If it succeeds, inspect the baseline `drawterm.exe` with tools such as:
   - `file`
   - `x86_64-w64-mingw32-objdump`
   - Windows `dumpbin`, when useful
7. Record:
   - Architecture and PE format
   - PE subsystem
   - Entry point
   - Imported DLLs
   - Whether any MinGW runtime DLLs must accompany the executable
   - Confirmation that it does not import `cygwin1.dll`
8. Test the unchanged binary's normal GUI behavior.
9. Test `-G -c` from an actual Windows PowerShell or `cmd.exe` session, not only
   through WSL interoperation. Record console output, shell waiting, exit
   behavior, and redirection behavior.

The expected baseline is a GUI-subsystem binary because of `-mwindows`. Do not
mistake successful compilation for completion of the work.

## Phase 2: MinGW console parity

After the unchanged baseline is documented, make the smallest changes necessary
for the MinGW build to produce the same console-capable `drawterm.exe` design as
the MSVC build.

Requirements:

- Produce a Windows console-subsystem executable.
- Preserve normal GUI startup when `-G` is absent.
- Preserve the appropriate Windows entry point and UTF-16-to-UTF-8 command-line
  handling. Do not assume that replacing `-mwindows` with `-mconsole` is
  sufficient without verifying the resulting entry point and argument
  behavior.
- Make PowerShell and `cmd.exe` wait for `-G -c`.
- Preserve standard input, output, error, redirection, and pipelines.
- Preserve meaningful process exit behavior.
- Do not add a Windows-version-specific manifest.
- Do not add a second executable or GUI launcher.
- Keep changes compatible with both WSL-hosted MinGW-w64 and the existing
  upstream-style MinGW/Cygwin build path when practical.
- Do not alter `NMakefile.msvc` or shared source files unless technically
  necessary.

If shared source files are changed, rebuild and regression-test the MSVC target.
If that test cannot be run, report it explicitly.

## Phase 3: final verification and staging

Perform a clean MinGW rebuild after the console-subsystem change.

Verify:

- The output is an x86-64 native Windows PE executable.
- The PE subsystem is console/CUI rather than GUI.
- The intended entry point and command-line parsing remain correct.
- The binary does not depend on WSL or `cygwin1.dll`.
- All non-system runtime DLL dependencies, if any, are identified.
- Ordinary invocation opens the Drawterm GUI and remains usable.
- `-G -c` prints output in PowerShell and `cmd.exe`.
- The invoking shell waits until the remote command finishes.
- Success and failure exit behavior is recorded.
- Output redirection and at least one pipeline scenario work.
- Existing diagnostic logging still works when enabled.
- The MSVC build still succeeds if shared code was touched.

Use the user's existing local Plan 9 connection settings and password
environment variable for runtime tests. Do not print the password.

After verification, copy the final executable—and any required non-system DLLs,
if the dependency inspection finds them—to:

```text
C:\Users\dharm\src\drawterm\build\mingw-wsl
```

The primary artifact must be:

```text
C:\Users\dharm\src\drawterm\build\mingw-wsl\drawterm.exe
```

Do not add the WSL filesystem path to the Windows `PATH`. Do not install into
`%LOCALAPPDATA%\Programs\Drawterm` during this task.

Once the build is proven, add concise repository documentation for the exact
manual workflow and its output location. Keep future automation clearly marked
as deferred.

## Out of scope

- Replacing or removing MSVC/NMake
- Introducing CMake, Ninja, or another build generator
- Building directly in the Windows checkout through `/mnt/c`
- A PowerShell build wrapper or automatic dependency bootstrap
- A Windows installer or automatic `PATH` changes
- Installing into `%LOCALAPPDATA%\Programs\Drawterm`
- A Windows 11-only console-allocation manifest
- A GUI-only `drawterm.exe`
- A second GUI launcher such as `drawtermw.exe`
- Refactoring unrelated source
- Synchronizing new 9front upstream changes
- Publishing binaries, pushing branches, or opening a pull request without
  explicit user direction

## Completion criteria

The task is complete only when:

1. The unchanged `-mwindows` baseline has been recorded.
2. The final MinGW build succeeds from the documented manual WSL workflow.
3. The final PE subsystem and imported DLLs have been inspected.
4. Normal GUI mode and console `-G -c` mode have both been tested.
5. The verified final artifact has been copied into `build\mingw-wsl`.
6. The manual build workflow has been documented in the repository.
7. The final report clearly identifies any remaining limitations.

## Final report

Report:

- WSL distribution and Ubuntu release
- MinGW-w64, binutils, Git, and Make versions
- Exact baseline and final build commands
- Whether the unchanged baseline succeeded
- Baseline and final PE subsystem and entry point
- Compiler warnings or failures
- Imported DLLs and runtime-dependency conclusions
- GUI test results
- PowerShell and `cmd.exe` `-G -c` results
- Waiting, redirection, pipeline, and exit-behavior results
- Final Windows staging path
- Files changed and why
- MSVC regression result, if shared files changed
- Current branch, `git status`, and diff summary
- Anything not verified
