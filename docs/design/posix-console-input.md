# POSIX `-G` raw terminal input

Status: implemented and interactively verified on Linux.

## Problem

When a remote program enabled raw console mode, the POSIX backend disabled
local echo and canonical input but retained the host terminal's carriage-return
translation flags. A typical Linux terminal has `ICRNL` enabled, so pressing
Enter produced line feed (`0x0a`, conventionally `C-j`) instead of carriage
return (`0x0d`, conventionally `RET`). Terminal applications that distinguish
those keys therefore received the wrong input.

## Design

On the first raw-mode transition, Drawterm saves the complete original
`termios` state. Raw mode clears `IGNCR`, `ICRNL`, and `INLCR`, preserving
carriage return and line feed as distinct input bytes, in addition to disabling
echo and canonical input as before. Leaving raw mode restores the saved state
exactly. If restoration fails, the saved state remains available for a later
retry.

This is a focused correction to CR/LF handling. It does not otherwise expand
the POSIX backend's historical raw-mode policy for signals, flow control, or
output processing.

## Verification

- A clean `CONF=linux` build completed successfully.
- A pseudo-terminal check against the linked production `setterm` function
  confirmed that raw mode clears the three CR/LF translations and that leaving
  raw mode restores the complete baseline terminal state.
- An interactive GNOME Terminal session running Legmacs on Plan 9 through
  `drawterm -G` confirmed that Enter inserts a newline, literal `Ctrl-J` remains
  distinct, terminal resize propagation still works, and the host terminal is
  usable after Drawterm exits.
