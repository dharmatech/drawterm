# Project guidance

## Project VM

- Use `$p9qemu-local` for VM onboarding, startup, shutdown, and checkpoints.
- Drawterm's project VM root is `C:\Users\dharm\vm\drawterm`.
- Use `$plan9-access` for guest commands, Drawterm connections, and `/mnt/term`.
- Disposable test instances use `scratch-*`; do not assume an instance is running or reuse a leased loopback address.
