# Windows `-G` terminal resize propagation

Status: low-risk watcher implemented for Windows `-G`; event-driven input
refactor reserved for future evaluation.

## Problem

When Windows Drawterm runs with `-G` inside Windows Terminal, the remote
program receives keyboard input and renders through standard I/O, but it does
not learn when the visible terminal size changes. Full-screen programs can
therefore remain at their startup dimensions after the window is resized.

The desired contract is:

- publish the initial visible row and column counts;
- update them when the Windows Terminal viewport changes;
- expose a resize notification that guest-side terminal code can observe; and
- leave graphical Drawterm and redirected, non-console I/O unchanged.

This document concerns the Windows Drawterm side of that contract. Guest-side
code may still need a separate change to react to the published notification
and redraw itself.

## Current Windows input path

In `-G` mode, `kern/win32.c` enables `ENABLE_VIRTUAL_TERMINAL_INPUT`, and
`osconsread` reads bytes with `ReadFile`. Windows performs the key translation:
Alt combinations arrive with an ESC prefix and navigation keys arrive as VT
sequences. This behavior is already working and should be preserved.

`ReadFile` does not deliver Windows console resize records. Microsoft exposes
those records through `ReadConsoleInput` when `ENABLE_WINDOW_INPUT` is enabled.
Consequently, resize events cannot simply be added to the existing byte read.
Running a second reader against the same console input queue would also create
a race over keyboard and resize records.

## Near-term design: size watcher

The initial implementation should keep the current keyboard path intact and
run a small watcher only when `-G` is attached to a Windows console.

The watcher should:

1. Query `GetConsoleScreenBufferInfo` at startup and at a modest interval, such
   as 100 milliseconds.
2. Derive the visible dimensions from `srWindow`, not `dwSize`:

   ```text
   columns = srWindow.Right - srWindow.Left + 1
   rows    = srWindow.Bottom - srWindow.Top + 1
   ```

3. Cache the last valid dimensions and publish an update only when either
   value changes.
4. Update the remote-facing `COLS` and `LINES` first, then write a monotonically
   increasing `WINCH` generation last so readers do not intentionally observe
   a notification for stale values. Bind only those exported files into the
   remote environment; do not expose Drawterm's entire host environment.
5. Stop cleanly during Drawterm shutdown and restore no additional console
   state beyond what the process changed.
6. Disable itself for pipes, files, or other non-console standard handles.

This is polling, but it is bounded and inexpensive: ten small console queries
per second, with no remote update or redraw when the cached size is unchanged.
It isolates resize support from keyboard decoding and is therefore the lowest
risk change for the current implementation.

## Future design: unified event-driven console input

The canonical Windows design is a single owner of the console input queue. It
enables `ENABLE_WINDOW_INPUT` and uses `ReadConsoleInputW` to receive both
`KEY_EVENT` and `WINDOW_BUFFER_SIZE_EVENT` records.

A future implementation could replace the watcher and the current console
`ReadFile` path with one dispatcher:

```text
ReadConsoleInputW
    |
    +-- KEY_EVENT --------------------> VT/input byte queue
    |
    `-- WINDOW_BUFFER_SIZE_EVENT -----> publish size and resize notification
```

This would remove periodic polling and deliver resize changes as Windows emits
them. It should replace the watcher rather than run alongside it.

The refactor is not currently selected because Drawterm would become
responsible for translating Windows `KEY_EVENT_RECORD` values into the byte
stream now produced by `ENABLE_VIRTUAL_TERMINAL_INPUT`. Correct translation
must cover at least:

- Alt/Meta combinations and ESC prefixes;
- Ctrl combinations;
- arrow, navigation, and function keys;
- key-repeat counts;
- Unicode input and non-ASCII keyboard layouts;
- pasted input;
- the Escape, Enter, Tab, and Backspace keys;
- console-mode restoration; and
- redirected standard input, which must retain a byte-oriented path.

That work is large enough to deserve a dedicated branch, design review, and
interactive regression testing. It may eventually provide a cleaner central
place for other Windows console events, but resize support alone does not yet
justify replacing the proven VT input translation.

## Criteria for evaluating the event-driven alternative

If the event-driven design is prototyped later, compare it with the watcher on:

- input compatibility, especially Meta and navigation sequences;
- Unicode and keyboard-layout behavior;
- resize latency and behavior during rapid window dragging;
- CPU usage while idle;
- shutdown and console-mode restoration;
- behavior under Windows Terminal and the legacy Windows console host; and
- behavior when stdin or stdout is redirected.

The watcher can be removed only after the event-driven implementation passes
the same interactive test matrix and becomes the sole console-input reader.

## Related implementations and documentation

- Windows ADB translates `WINDOW_BUFFER_SIZE_EVENT` into a remote terminal-size
  message, closely matching Drawterm's role:
  <https://android.googlesource.com/platform/system/core/+/2e02dc6%5E%21/>
- A QEMU Windows-console design handles resize records in its existing
  `ReadConsoleInput` event loop:
  <https://www.mail-archive.com/qemu-devel@nongnu.org/msg1162854.html>
- Microsoft documents console resize records and the distinction between
  `ReadFile`/`ReadConsole` and `ReadConsoleInput`:
  <https://learn.microsoft.com/en-us/windows/console/reading-input-buffer-events>
- Microsoft documents the visible-window fields returned by
  `GetConsoleScreenBufferInfo`:
  <https://learn.microsoft.com/en-us/windows/console/getconsolescreenbufferinfo>
