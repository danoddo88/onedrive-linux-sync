# onedrive-linux-sync

OneDrive on Linux the way the official Windows and macOS clients work:

- **Files On-Demand**: your whole OneDrive shows up in `~/OneDrive`, nothing is downloaded until you open it.
- **"Always keep on this device"** from the right-click menu: the folder is downloaded for real and kept in sync **both ways**.
- **Instant uploads**: a file you save inside a pinned folder is in the cloud within seconds.
- **Status emblems** in the file manager, like Windows: green tick (on this PC), cloud (online only), arrows (syncing).
- **One folder.** Pinned folders are bind-mounted over their place in `~/OneDrive`, so there is no second "local" tree to think about.

It is a handful of bash scripts and systemd user units on top of [rclone](https://rclone.org). No daemon of its own, no database, nothing that touches files you did not pin.

Spanish README: [README.es.md](README.es.md). The scripts, their messages and comments are in Spanish.

## Why

The official OneDrive client does not exist for Linux. The usual alternatives either download everything (full-sync clients) or keep everything in the cloud with no way to say "this folder, I want for real, and keep it updated" (plain `rclone mount`). This combines both, and adds the two things people miss most from Windows: the right-click option and the little green ticks.

## How it works

Three separate processes, so none of them blocks the others:

| Process | What it does | When |
|---|---|---|
| `rclone mount` (`onedrive.service`) | Shows the cloud in `~/OneDrive`. Files are fetched when opened and cached on disk. | always |
| **Fast queue** (`onedrive-cola.service`) | Watches pinned folders with inotify. Every saved file becomes a "slip" in a spool; a dispatcher uploads them 4 at a time with `rclone copyto`. Failed uploads are retried every 15 s, so working offline is fine. | always |
| **Reconciliation** (`onedrive-local.timer`) | `rclone bisync` on each pinned folder, every minute. Brings down what changed elsewhere, resolves conflicts (newest wins), recovers on its own after an aborted run. | every minute |

Pinning a folder (`onedrive-local --fijar`) first runs `rclone copy` cloud → disk, which compares and downloads at the same time (unlike `bisync`, which lists everything before downloading anything), then one `bisync --resync` to set up two-way sync. Downloads run one folder at a time with 32 parallel transfers; Microsoft throttles beyond that and rclone backs off on its own.

Emblems are GIO metadata (`metadata::emblems`), which Nemo and Thunar draw. A small daemon (`onedrive-marcas-vivas`) marks **only the folder you have open**, so a 100 000-file OneDrive costs nothing to browse.

## Requirements

- Linux with systemd and a user session (tested on Ubuntu 26.04 with XFCE).
- **rclone ≥ 1.66** with a remote named `onedrive` (`rclone config`, type `onedrive`).
- `fuse3`, `inotify-tools`, `xdotool`, `x11-utils`, `zenity`, `libnotify-bin`, `python3`.
- A file manager that draws GIO emblems: **Nemo** (recommended) or **Thunar**. Nautilus does not draw them.
- X11 (the live emblem daemon reads the active window title with `xdotool`).

## Install

```bash
git clone https://github.com/danoddo88/onedrive-linux-sync
cd onedrive-linux-sync
./install.sh
```

The installer copies the scripts to `/usr/local`, enables the user units, adds the right-click actions for Nemo and/or Thunar, allows your user to run the bind mount with sudo (that is the only thing that needs root), and enables lingering so sync keeps running without a graphical login.

## Use

Right-click a folder inside `~/OneDrive`:

| Option | Does |
|---|---|
| **Mantener siempre en esta PC** | Downloads it and keeps it in sync both ways |
| **Sincronizar esta copia ahora** | Runs the reconciliation right now |
| **Dejar de guardar en esta PC** | Stops syncing. Keeps both the local copy and the cloud |
| **Actualizar los tildes de estado** | Repaints every emblem |

Right-click a folder **outside** OneDrive to upload it and keep it uploaded (one way, local wins, every 10 minutes): **Mantener sincronizada con OneDrive**.

Same from the terminal:

```bash
onedrive-local --fijar ~/OneDrive/projects/foo   # pin
onedrive-local --lista                            # what is pinned, and where
onedrive-local --ahora                            # sync all pinned folders now
onedrive-local --soltar ~/OneDrive/projects/foo  # unpin
onedrive-sincronizar --registrar ~/Pictures       # upload a local folder, keep it uploaded
```

Logs live in `~/.config/onedrive-sync/`.

## Tuning

- `ONEDRIVE_HILOS` (default 32): parallel transfers when pinning a folder.
- `onedrive-local.timer`: reconciliation interval (default 1 min).
- `onedrive.service`: rclone mount flags (`--vfs-cache-max-size`, `--dir-cache-time`, …).

## What it is not

- **Not instant from the cloud side.** A change made on another device reaches a pinned folder on the next reconciliation (≤ 1 min). Linux → cloud is seconds.
- **Not a replacement for a real client on huge trees of tiny files.** Every file is a request to Microsoft; `node_modules` with 40 000 files will take a while whatever you do.
- **Nothing is deleted in the cloud by unpinning.** Unpin keeps both copies. Two-way sync *does* propagate deletions you make yourself, as any sync does.

## Uninstall

```bash
./uninstall.sh
```

Keeps `~/.onedrive-local` (your local copies) and `~/.config/onedrive-sync` (lists and logs).

## License

MIT.
