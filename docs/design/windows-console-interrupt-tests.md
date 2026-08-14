# Windows `-G` remote-command interrupt tests

Status: manual diagnostic procedure.  These tests characterize current
behavior; they do not require a particular interrupt design.

## Purpose

Windows Drawterm can run both ordinary commands and raw terminal applications
through `-G -c`.  These cases need different keyboard behavior:

- an ordinary long-running command should be cancellable without leaving a
  remote process behind; and
- a raw application must continue receiving control characters as input so it
  can implement its own key bindings and graceful shutdown.

The tests below distinguish three possible outcomes:

1. the remote process group receives a Plan 9 `interrupt` note;
2. the remote process receives `hangup` because the client disconnects; or
3. Drawterm exits but the remote process remains alive.

Run each test from a fresh PowerShell session when checking terminal teardown.
Use the exact Drawterm binary under test rather than relying on `PATH`.

```powershell
$env:PASS = '<password>'
$ip = '127.0.0.10'
$dt = 'C:\path\to\drawterm.exe'
```

## 1. Natural-completion baseline

Run a short cooked-mode command without pressing any keys:

```powershell
& $dt -h $ip -a $ip -u glenda -G -c 'sleep 3; echo natural-completion'
```

Verify that `natural-completion` appears, Drawterm exits, the PowerShell prompt
returns immediately, and the prompt accepts another command.  This establishes
the baseline before testing interruption.

### 1a. Cooked-mode typeahead

Run a cooked command that does not read standard input:

```powershell
& $dt -h $ip -a $ip -u glenda -G -c 'sleep 3'
```

While it sleeps, type `Write-Output typeahead-preserved` and press Enter.  When
Drawterm exits, verify that PowerShell receives and executes the queued command.
This detects an exit callback that unnecessarily flushes the host console input
buffer even though the remote command never requested raw mode.

## 2. Instrumented long-running command

The following command identifies its shell in `ps` and records an `interrupt`,
`hangup`, or ordinary completion in a guest-side file:

```powershell
& $dt -h $ip -a $ip -u glenda -G -c 'rm -f /tmp/drawterm-interrupt-result; echo -n drawterm-interrupt-test >/proc/$pid/args; fn sigint { echo interrupt >/tmp/drawterm-interrupt-result; exit interrupted }; fn sighup { echo hangup >/tmp/drawterm-interrupt-result; exit hangup }; echo ready; sleep 600; echo completed >/tmp/drawterm-interrupt-result'
```

After Drawterm exits, reconnect and inspect both the result and any surviving
test process:

```powershell
& $dt -h $ip -a $ip -u glenda -G -c 'cat /tmp/drawterm-interrupt-result; ps | grep drawterm-interrupt-test'
```

Interpret the output as follows:

- `interrupt`: the remote process group received the intended interrupt note;
- `hangup`: cancellation occurred through session disconnection;
- `completed`: the command was not interrupted;
- a missing result file with no matching process: the process ended without
  running either note handler; or
- a matching process after Drawterm exits: the remote command was orphaned and
  must be cleaned up before continuing.

If cleanup is necessary, note the PID reported by `ps` and send it a `kill` or
`hangup` note from a separate administrative session.  Do not leave the
ten-minute sleep running between tests.

### 2a. Ctrl-C

Start the instrumented command, wait for `ready`, and press Ctrl-C once.  Record:

- whether Drawterm exits;
- whether the PowerShell prompt returns immediately;
- the contents of `/tmp/drawterm-interrupt-result`; and
- whether `drawterm-interrupt-test` remains in `ps`.

With a future `rcpu` interrupt-note channel, the desired result is `interrupt`.
A local Drawterm termination followed by `hangup` is observably different and
should be recorded as such.

### 2b. Delete

Start a fresh copy of the instrumented command, wait for `ready`, and press the
Delete key once.  Wait a few seconds before pressing anything else.

Record whether Delete exits the command or has no visible effect.  If the
command keeps running, use the known Ctrl-C behavior or Ctrl-Break to recover,
then inspect the result file and process list.  A forwarded DEL byte alone is
not equivalent to Rio sending an `interrupt` note to a process group.

## 3. Raw-application graceful exit

Run LegMacs in its normal raw terminal mode:

```powershell
& $dt -h $ip -a $ip -u glenda -G -c 'cd /usr/glenda/src/legmacs; lg main.lg'
```

Verify that Ctrl and Alt/Meta bindings still reach LegMacs.  Exit with
Ctrl-X, Ctrl-C and, without pressing another key, verify that:

- LegMacs restores its terminal output modes;
- Drawterm exits;
- the PowerShell prompt appears immediately; and
- typing, paste, and terminal scrollback work normally.

This is a graceful application exit, not a remote-command interrupt test.
Ctrl-C must remain application input while the console is in raw mode.

### 3a. Exit, resize, and relaunch

This sequence covers stale terminal modes, blocked readers, resize propagation,
and initial rendering together:

1. Open a new Windows Terminal at its default size.
2. Start LegMacs and exit with Ctrl-X, Ctrl-C.
3. Maximize Windows Terminal after the PowerShell prompt returns.
4. Run the same Drawterm command again.
5. Verify that the initial LegMacs frame immediately fills the terminal, the
   scratch-buffer text is visible, and the mode line spans the full width.

No extra keypress or manual resize should be needed to repair the second frame.
After the second graceful exit, verify that PowerShell remains fully usable.

## 4. Optional filesystem-walk stress case

After the deterministic `sleep` tests, `walk / >/dev/null` can replace
`sleep 600` in the instrumented command.  This exercises cancellation while a
program is traversing the namespace rather than sleeping.  Retain the same
note handlers, result file, process marker, and post-test inspection.

The walk is optional because its duration depends on the mounted namespace and
system load.  The sleep test should remain the primary repeatable spot check.

## Results record

Record enough information to compare builds:

| Date/build | Test | Key or exit command | Prompt immediate? | Remote result | Process remains? | Terminal usable? |
| --- | --- | --- | --- | --- | --- | --- |
| | Natural completion | none | | `completed` | | |
| | Cooked typeahead | none | | n/a | | |
| | Instrumented sleep | Ctrl-C | | | | |
| | Instrumented sleep | Delete | | | | |
| | LegMacs raw mode | Ctrl-X, Ctrl-C | | graceful exit | | |
| | LegMacs relaunch after maximize | Ctrl-X, Ctrl-C | | graceful exit | | |
| | Optional walk | Ctrl-C | | | | |

Ctrl-Break or closing the terminal tab is an emergency local escape, not a
successful remote interrupt.  Use it when a test cannot otherwise be stopped,
and record that the test required forced client termination.
