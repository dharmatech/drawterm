# Project guidance

## Project VM

- Use `$p9qemu-local` for VM onboarding, startup, shutdown, and checkpoints.
- Drawterm's project VM root is `C:\Users\dharm\vm\drawterm`.
- Use `$plan9-drawterm-windows` for Drawterm connections, guest command
  execution, and `/mnt/term` file exchange.
- Use `$plan9-file-search` for listing or searching files on the connected
  guest with `walk`, `g`, or `grep`.
- Disposable test instances use `scratch-*`; do not assume an instance is running or reuse a leased loopback address.
