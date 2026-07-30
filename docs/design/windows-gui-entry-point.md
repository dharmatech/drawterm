# Possible Windows GUI entry point

Status: future consideration; not currently planned or implemented.

Drawterm currently uses one canonical console-subsystem `drawterm.exe`.
Ordinary invocation opens the graphical interface, while `-G` provides proper
terminal waiting, standard I/O, redirection, and exit behavior.

A future Windows release might provide an optional GUI-oriented entry point for
Explorer, Start-menu, or desktop-shortcut launches. Possible forms include a
small GUI launcher, a separately linked GUI binary, or a suitable Windows
manifest. Any such addition should delegate to or share the canonical Drawterm
implementation rather than create an independently maintained program.

Before pursuing this, decide:

- Which Windows versions must be supported.
- Whether current Explorer launch behavior presents a real user problem.
- How arguments, environment, errors, and exit status would be forwarded.
- Whether the packaging benefit justifies another executable.

This idea is outside the current WSL build and Windows installer work.
