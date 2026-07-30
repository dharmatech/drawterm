# Archived exploration: Windows GUI versus console launching

> Status: superseded. This conversational exploration is preserved in this
> commit for history and replaced in the active tree by a short future-design
> note.

This is a real Windows design issue, not merely a linker-flag issue. After looking at our implementation and surveying established projects, my recommendation is:

Keep `drawterm.exe` as the single, console-capable program on every platform. Don’t create two complete Drawterm builds. For polished Windows GUI launching, use either the new Windows console-allocation manifest or, if older Windows versions matter, a tiny optional GUI launcher.

### Why Windows makes this difficult

Windows reads an executable’s subsystem before Drawterm gets an opportunity to parse `-G`.

- A console-subsystem executable makes CMD and PowerShell wait and provides standard input/output.
- A GUI-subsystem executable normally makes the shell return immediately and supplies no console.

Attaching to the parent console later can recover console handles, but it cannot reliably go backward and make the shell treat the process as one it should have waited for. Microsoft documents this distinction explicitly in its [console-allocation policy](https://learn.microsoft.com/en-us/windows/console/console-allocation-policy).

Our current implementation reflects that:

- The MSVC binary uses `/SUBSYSTEM:CONSOLE` and retains `WinMainCRTStartup` in [NMakefile.msvc](../../NMakefile.msvc).
- The normal GUI path calls `FreeConsole()` in [screen.c](../../gui-win32/screen.c).
- The no-GUI path uses the standard handles and can attach to a parent console when necessary in [win32.c](../../kern/win32.c).
- At the time of this exploration, the MinGW build still selected the GUI
  subsystem with `-mwindows` in [Make.win64](../../Make.win64). Console parity
  was subsequently implemented in commit `c969d22`.

Thus our MSVC executable is already a hybrid: Windows classifies it as a console program, but it detaches when Drawterm actually opens its GUI.

### What other major projects do

| Project | Windows approach |
|---|---|
| Emacs | `emacs.exe` is the real console-capable program. `runemacs.exe` is a GUI launcher that starts it without an unwanted console. The [GNU Emacs manual](https://www.gnu.org/software/emacs/manual/html_node/emacs/Windows-Startup.html) explicitly describes the difference. |
| Python | Provides console commands such as `python` and `py`, plus windowed variants such as `pythonw` and `pyw` that avoid creating a console. See the [Python Windows documentation](https://docs.python.org/3/using/windows.html). |
| Vim | Has `vim.exe` for console use and `gvim.exe` for the Windows GUI. Its [Windows GUI manual](https://vimhelp.org/gui_w32.txt.html) explains that they use different subsystems. |
| Modern Windows | Windows 11 24H2 introduced a manifest setting specifically for a console-subsystem program that should look like a GUI application when started from Explorer. |

So your recollection about Emacs was exactly right. `runemacs.exe` is essentially a Windows-only launch adapter; it is not a second independent Emacs implementation.

### Our practical choices

1. Single console-subsystem `drawterm.exe`, as we have now.

   - Same program name and arguments across platforms.
   - Correct shell waiting, redirection, pipelines, and `-G -c`.
   - On older Windows, launching it from Explorer can briefly create a console before `FreeConsole()` runs.

2. Single `drawterm.exe` plus the modern detached-console manifest.

   Microsoft now recommends compiling as a console application and embedding:

   ```xml
   <consoleAllocationPolicy xmlns="http://schemas.microsoft.com/SMI/2024/WindowsSettings">
     detached
   </consoleAllocationPolicy>
   ```

   That lets the shell recognize it as a process that must be waited for, while Windows avoids allocating a console when it is launched without one. It is almost exactly the behavior we want. However, the documented minimum is Windows 11 24H2.

3. `drawterm.exe` plus a tiny `drawterm-gui.exe` launcher.

   - `drawterm.exe` remains the canonical program.
   - `drawterm-gui.exe` contains almost no Drawterm code; it just starts the adjacent `drawterm.exe` without a console.
   - Desktop and Start-menu shortcuts target `drawterm-gui.exe`.
   - Terminal users invoke `drawterm.exe`.
   - This is essentially the Emacs model and works on older Windows versions.

4. Two complete Drawterm binaries.

   For example, a GUI `drawterm.exe` and console `drawterm-console.exe`. Python and Vim demonstrate that this can work, but I don’t think it is right for us. It duplicates the linked program, complicates testing and packaging, and makes Windows command usage unnecessarily different from Unix.

### My recommendation for our fork

I would choose this hierarchy:

1. Keep `drawterm.exe` console-subsystem and fully support `-G -c`.
2. Make the MinGW build produce the same subsystem behavior as the MSVC build.
3. Add the Windows 11 detached-console manifest.
4. Only add a tiny `drawterm-gui.exe` launcher if we want a polished no-console launch experience on Windows 10 or other older systems.
5. Do not build two complete copies of Drawterm.

That preserves the property you value: the real program is still called `drawterm` everywhere, and `drawterm -G -c ...` behaves consistently across Windows, Linux, and macOS. Any second Windows executable would merely be a convenience launcher, comparable to a platform-specific application shortcut—not a competing version of Drawterm.

I do think implementation deserves a separate focused conversation after the unchanged WSL baseline. The WSL task should answer, “Can the existing MinGW path compile our fork, and what does that binary currently do?” A subsequent Windows-launch task can address:

- The exact MinGW console-subsystem and `WinMain` entry-point flags.
- Embedding the manifest in both MSVC and MinGW builds.
- Explorer launch without a console flash.
- CMD, PowerShell, redirection, pipelines, exit status, and `-G -c`.
- Whether we care about Windows releases older than 11 24H2.

Before using the current WSL handoff, I would slightly tighten it so the WSL task records the `-mwindows` behavior but does not redesign the launch model prematurely.
