# Cross-build Windows Drawterm with MinGW-w64 under WSL

This workflow builds a native 64-bit Windows `drawterm.exe` from Ubuntu under
WSL. WSL is only the build host: the resulting executable runs directly on
Windows and does not require WSL, Cygwin, or `cygwin1.dll` at runtime.

The instructions below were tested with Ubuntu 22.04 under WSL 2.

## Install the Ubuntu prerequisites

From an Ubuntu shell, install Git, GNU Make, `file`, and the x86-64 MinGW-w64
GCC and binutils packages:

```sh
sudo apt update
sudo apt install git make file gcc-mingw-w64-x86-64 binutils-mingw-w64-x86-64
```

Other Linux distributions may provide the same tools under different package
names, but they have not been tested as part of this workflow. The required
compiler and related programs use the `x86_64-w64-mingw32-` prefix.

## Clone into the WSL filesystem

Keep the build tree in WSL's native Linux filesystem rather than below
`/mnt/c`. The build writes object files and libraries throughout the source
tree, and native WSL filesystem access is substantially faster.

```sh
mkdir -p ~/src
git clone https://github.com/dharmatech/drawterm.git ~/src/drawterm
cd ~/src/drawterm
```

A Windows checkout may be kept separately. Synchronize the two working trees
through Git rather than manually mirroring source files.

## Build

Run:

```sh
make CONF=win64
```

The output is:

```text
./drawterm.exe
```

For a clean rebuild, run:

```sh
make CONF=win64 clean
make CONF=win64
```

## Inspect the executable

These commands confirm that the result is a 64-bit Windows PE executable and
show its subsystem and DLL imports:

```sh
file drawterm.exe
x86_64-w64-mingw32-objdump -p drawterm.exe |
    grep -E 'AddressOfEntryPoint|Subsystem|DLL Name'
```

The executable should report the Windows console subsystem. Drawterm still
opens its graphical window during ordinary invocation; uppercase `-G` selects
text-only operation. The console subsystem allows PowerShell and `cmd.exe` to
wait for `-G -c` sessions and supports ordinary redirection and pipelines.

The standard build has only Windows system DLL imports. No MinGW or Cygwin
runtime DLL needs to accompany `drawterm.exe`.

## Copy the result to Windows

Copy the executable to a destination on the Windows filesystem. For example:

```sh
mkdir -p /mnt/c/Users/your-name/bin/drawterm
cp drawterm.exe /mnt/c/Users/your-name/bin/drawterm/
```

Then invoke that copy from Windows. A text-only command from PowerShell looks
like:

```powershell
$env:PASS = 'your-password'
.\drawterm.exe -h cpu.example -a auth.example -u glenda -G -c 'lc /'
```

Omit `-G` for Drawterm's graphical interface.

## Troubleshooting

If `x86_64-w64-mingw32-gcc` or
`x86_64-w64-mingw32-objdump` is not found, verify that the Ubuntu MinGW-w64
packages above are installed:

```sh
x86_64-w64-mingw32-gcc --version
x86_64-w64-mingw32-objdump --version
```

Use `CONF=win64` for both the build and clean targets. Running plain
`make clean` does not select a platform configuration.

This is intentionally a manual workflow. It keeps the compiler invocation and
artifact location visible; an automated prerequisite or build wrapper can be
added later if repeated use justifies it.
