# Windows `-G` UTF-8 console output

## Problem

Drawterm and Plan 9 exchange UTF-8 byte strings.  On Unix, writing those bytes
to a terminal preserves them as UTF-8.  The Windows `-G` path also writes the
bytes directly, but a Windows console interprets `WriteFile` output through its
active output code page.

With the common OEM code page 437, the UTF-8 bytes `e2 94 82` for the box
drawing character `│` render as the three characters `Γöé`.  ANSI sequences
and ASCII remain valid, so the defect is especially visible in Unicode TUI
borders and dividers.

This is a host-console transport issue.  Replacing Unicode characters in the
remote application would hide it for one program while leaving all other
Unicode output broken.

## Design

When Windows `-G` has a real console as standard output, Drawterm:

1. reads and saves the active console output code page;
2. selects `CP_UTF8` before it begins serving the remote command; and
3. restores the saved code page from the existing console teardown callback.

The UTF-8 switch happens only after the restoration callback is registered.
This avoids leaking a changed, console-wide code page into the invoking shell
when Drawterm exits.

The input mode and output code page have independent lifecycles.  A remote
program may never request raw input, but its output still needs UTF-8.  The
teardown path therefore restores either saved state independently and remains
idempotent.

## Scope

- Graphical Drawterm does not call the `-G` console setup.
- Redirected standard output is not a console, so its byte stream is unchanged.
- A console already using UTF-8 is left unchanged and needs no restoration.
- Linux and other hosts do not compile the Windows implementation.

## Verification

Manual acceptance should cover:

- a remote command that emits `│` and other non-ASCII UTF-8;
- a full-screen TUI with ANSI styling and repeated Unicode dividers;
- ordinary ASCII output;
- redirected output retaining its original UTF-8 bytes; and
- the invoking shell's output encoding matching its pre-Drawterm value after
  both cooked and raw-mode sessions exit.
