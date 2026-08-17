# Project guidance

## Project VM

- Use `$p9qemu` for VM onboarding, startup, shutdown, and checkpoints.
- Drawterm's project VM root is `C:\Users\dharm\vm\drawterm` for native
  Windows and `/home/dharmatech/vm/drawterm` in the active Linux filesystem.
  WSL and bare-metal Ubuntu use independent storage lineages even when their
  Linux paths have identical spelling.
- Use `$plan9-drawterm` for Drawterm connections, guest command execution, and
  `/mnt/term` file exchange; select its lane by the Drawterm process.
- Use `$plan9-file-search` for listing or searching files on the connected
  guest with `walk`, `g`, or `grep`.
- Disposable test instances use `scratch-*`; do not assume an instance is running or reuse a leased loopback address.
