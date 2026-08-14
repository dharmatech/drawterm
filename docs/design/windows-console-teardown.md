# Windows `-G` console teardown

Status: implemented and interactively validated on Windows Terminal.

## Problem

Windows Drawterm's `-G` mode shares the invoking terminal with the remote
program.  A full-screen program can enable raw mode, maintain a background
read from `/dev/cons`, and use terminal output modes such as the alternate
screen and bracketed paste.

Three shutdown failures appeared together in that scenario:

- `Ctrl-C` was handled as a Windows console signal instead of reaching the
  remote program as byte `0x03`;
- closing `/dev/consctl` could wait behind a blocking `/dev/cons` read; and
- after the remote application restored the screen and exited, Drawterm could
  remain alive until another key completed the outstanding console read.

When Drawterm terminated before application cleanup, Windows Terminal was
left in the alternate screen with bracketed paste and mouse reporting still
enabled.  Subsequent PowerShell input then appeared corrupted even though the
shell itself was functioning normally.

## Root cause

The failures crossed three layers of the console path.

First, `setterm(1)` disabled line and echo input but retained
`ENABLE_PROCESSED_INPUT`.  Windows therefore treated `Ctrl-C` as a host signal
instead of returning it from `ReadFile`.

Second, `consread` held the keyboard state lock while it called the potentially
blocking host console read.  A concurrent `rawoff` or close of `/dev/consctl`
needed the same lock before it could restore the host console mode.

Finally, exportfs handled a 9P `Tflush` by interrupting its Inferno-style
worker process.  On Windows, that interrupt did not cancel a synchronous
`ReadFile` already executing in the worker's host thread.  A Plan 9 program
whose runtime posted an exit note to a background input worker therefore left
that worker blocked in `Pread` until the user pressed a key.

## Design

The implementation keeps Windows virtual-terminal input as the byte
translation layer and makes shutdown interruptible:

1. Raw mode clears `ENABLE_PROCESSED_INPUT` along with line and echo input, so
   control characters are delivered to the remote application.
2. A dedicated reader lock serializes `/dev/cons` reads, while the keyboard
   state lock is held only while inspecting or updating raw/cooked state.
   Terminal-mode changes no longer wait for host input.
3. A Windows exportfs worker interrupt also calls `CancelSynchronousIo` for
   that worker's host thread.  The API is resolved dynamically so builds do
   not require a global Windows target-version change.
4. Windows `-G` sessions register a final input-mode restoration callback
   before the remote-status callback terminates the native process.

The reader-lock change is platform-neutral because it corrects the ownership
of Drawterm's console state.  Synchronous-I/O cancellation and the final
restoration callback are Windows-only.

## Regression procedure

Run Drawterm from a fresh PowerShell session and start a remote full-screen
program that opens `/dev/consctl`, enters raw mode, and maintains a background
console read.  LegMacs running under Letgo on Plan 9 exercises this path.

Verify the following before exit:

- Ctrl commands, including a multi-key `Ctrl-X` prefix, reach the application;
- Alt/Meta chords, navigation keys, Enter, and Backspace still work; and
- terminal resize notifications and redraws still work.

Then exit through the application's ordinary `Ctrl-X`, `Ctrl-C` command and
do not press another key.  Verify that:

- the original screen is restored;
- the PowerShell prompt appears immediately;
- typing and submitting another PowerShell command works;
- pasted text has no bracketed-paste marker bytes; and
- the mouse wheel controls terminal scrollback rather than shell history.

Also run a noninteractive `-G -c` command and confirm that redirected or
ordinary command output and exit status remain unchanged.

## Relevant Windows APIs

- Console input modes and `ENABLE_PROCESSED_INPUT`:
  <https://learn.microsoft.com/en-us/windows/console/setconsolemode>
- Canceling synchronous I/O in a specific thread:
  <https://learn.microsoft.com/en-us/windows/win32/fileio/cancelsynchronousio-func>
