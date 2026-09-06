# swapfile role

Creates a swap file on a host that has none, so a memory spike degrades the
box rather than having the OOM killer end a process — on the VPS that could
be anything, including something mid-booking. `deploy-meshcentral.yml` runs
it before the meshcentral role. It is host-level, needs no collections, and
can be run against any box on its own.

## What it does

- If `ansible_memory_mb.swap.total` is already above zero, reports the
  existing swap and leaves it alone. This role only creates swap where there
  is none.
- Otherwise: writes the file with `dd` (not `fallocate`, which can produce a
  sparse file that `swapon` rejects), sets mode 0600, runs `mkswap`, adds the
  `/etc/fstab` line (validated with `findmnt --verify`) and only then
  `swapon` — so a reboot between the two still brings swap back.
- Always: writes `/etc/sysctl.d/60-swappiness.conf` and applies it.

## Variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `swapfile_path` | `/swapfile` | Where the file goes |
| `swapfile_size_mb` | `2048` | Size in MB |
| `swapfile_swappiness` | `10` | `vm.swappiness`: swap as an emergency reserve, not a habit (the kernel default is 60) |
