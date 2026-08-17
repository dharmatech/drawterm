# POSIX `-G` terminal resize propagation

Status: implemented for interactive POSIX `-G` sessions; Linux build verified,
interactive resize validation pending.

## Problem

The Windows Drawterm backend publishes terminal dimensions through the hosted
environment so a remote Plan 9 terminal application can resize without waiting
for keyboard input. The POSIX backend previously forwarded standard input and
output but did not publish equivalent geometry, and the remote `rcpu` script
bound the resize environment files only in Windows builds.

## Design

When `-G` is active, the POSIX backend checks that standard input and output are
terminals and queries the output terminal with `TIOCGWINSZ`. A valid initial
size is published synchronously before Drawterm connects, ensuring the resize
environment files exist when the remote script mounts `/mnt/term`.

A process-lifetime kernel process then checks the terminal size every 100 ms,
matching the existing Windows watcher. It publishes only changed dimensions
and writes the files in this order:

1. `COLS`
2. `LINES`
3. monotonically increasing `WINCH`

`WINCH` is the commit notification: guest readers that observe a new generation
can then read a matching pair of dimensions. Polling avoids introducing POSIX
signal handling into Drawterm's threaded hosted-kernel runtime and leaves the
existing console input path unchanged.

The `rcpu` startup script binds the three files into the guest only when all of
them are present. This keeps redirected input/output and graphical sessions
unchanged and avoids exporting unrelated or incomplete host environment state.

## Scope

This mechanism accompanies Drawterm's `rcpu` startup script. The legacy `ncpu`
fallback does not use that script and is outside this change.

The guest terminal runtime remains responsible for observing `WINCH`, reading
the live dimensions, and redrawing. Let Go implements that contract in its
Plan 9 terminal adapter.
