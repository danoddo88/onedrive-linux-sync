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
| **Health check** (`onedrive-salud.timer`) | Every 10 min checks the services, the mount, the Microsoft session, the hourly reconciliation, the change feed, the upload queue and free disk space. If anything stopped working it shows a persistent desktop notification (once per hour while it lasts, and once when it recovers) and logs it to `historial-salud.log`. Run `onedrive-salud` by hand for a status line. | every 10 min |
| **Change feed** (`onedrive-delta.service`) | Asks Microsoft every 30 s "what changed since my last read?" (the Graph *delta* API, the same thing the official clients use: one request, only the changes, no listing). Changes inside pinned folders are applied file by file: download, rename/move without re-downloading, or delete. Newest wins; it never overwrites a file that is newer on this PC. | always |
| **Reconciliation** (`onedrive-local.timer`) | `rclone bisync` on each pinned folder, as a safety net: resolves anything the feed missed, recovers on its own after an aborted run. | every hour |

The change feed reuses rclone's OneDrive session (`~/.config/rclone/rclone.conf`) and asks rclone to refresh it when it expires; it keeps its read position in `~/.config/onedrive-sync/delta.json` and an item-id → path map in `delta-ids.sqlite` (needed because a deletion in the feed carries only the id). Files it downloads are flagged to the fast queue so they are not uploaded straight back.

Pinning a folder (`onedrive-local --fijar`) first runs `rclone sync` cloud → disk, which compares and downloads at the same time (unlike `bisync`, which lists everything before downloading anything), then one `bisync --resync` to set up two-way sync. Downloads run one folder at a time with 16 parallel transfers capped at 12 requests per second: going over Microsoft's per-account quota pauses *every* transfer for minutes, so staying just under it is faster than more threads.

Emblems are GIO metadata (`metadata::emblems`), which Nemo and Thunar draw. A small daemon (`onedrive-marcas-vivas`) marks **only the folder you have open**, so a 100 000-file OneDrive costs nothing to browse.

## Requirements

- Linux with systemd and a user session (tested on Ubuntu 26.04 with XFCE).
- **rclone ≥ 1.66** with a remote named `onedrive` (`rclone config`, type `onedrive`).
- `fuse3`, `inotify-tools`, `xdotool`, `x11-utils`, `zenity`, `libnotify-bin`, `python3`.
- A file manager that draws GIO emblems: **Nemo** (recommended) or **Thunar**. Nautilus does not draw them.
- X11 (the live emblem daemon reads the active window title with `xdotool`).

## File manager

**Nemo** is the recommended file manager: it draws the GIO emblems, has an editable path bar and tabs, and `install.sh` configures it for you (full path in the window title, "standard" icon size in list view — smaller icons don't show emblems — and no folder item counts or image thumbnails, which would otherwise download cloud files just to browse). Those are plain `gsettings` keys; change them back any time.

**Thunar** works too: the actions go in `~/.config/Thunar/uca.xml` and the installer sets the window title to the full path.

**Nautilus** (GNOME Files) does not draw emblems, so you get the right-click options but no ticks.

Emblems used: `emblem-default` (green tick), `emblem-web` (cloud, online only), `emblem-synchronizing` (arrows). They look right with the Adwaita, Papirus and WhiteSur icon themes; other themes may draw them differently.

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

- `ONEDRIVE_HILOS` (default 16): parallel transfers when pinning a folder.
- `ONEDRIVE_TPS` (default 12): max requests per second when pinning, to stay under Microsoft's quota.
- `ONEDRIVE_DELTA_SEG` (default 30): seconds between change-feed polls.
- `onedrive-local.timer`: reconciliation interval (default 1 min).
- `onedrive.service`: rclone mount flags (`--vfs-cache-max-size`, `--dir-cache-time`, …).

## Safety rules

- **Newest wins, always.** Reconciliation uses `--conflict-resolve newer`; the resync when pinning uses `--resync-mode newer` (rclone's default would let the *local* copy win, which can silently overwrite edits made elsewhere between the download and the resync). The fast queue uploads with `--update`, so it never replaces a cloud file that is newer than the local one.
- **Deleted elsewhere while downloading = not resurrected.** The first pinning step mirrors the cloud onto the disk (`rclone sync`, not `copy`), so a file deleted on another device mid-download does not stay on this PC to be re-uploaded by the resync. It is deleted from this PC too, as it was in the cloud (the cloud copy stays in OneDrive's recycle bin). Files that are newer on this PC are kept (`--update`) and uploaded.
- **A file edited here after being deleted elsewhere is kept and re-uploaded**, never deleted. Downloads retry on Microsoft throttling (429/503) and failed items are retried up to 5 times before being left to the hourly reconciliation.
- **Names OneDrive rejects** (`" * : < > ? |`, trailing space or dot) are never uploaded: the queue skips them, notifies once and lists them in `nombres-prohibidos.txt`; the reconciliation filters them out so one bad name cannot abort a whole folder.
- **Mass deletions are confirmed, like Microsoft's client does.** If one pass would delete 200 or more files from this PC (`ONEDRIVE_MAX_BORRAR`), nothing is deleted: a dialog asks *delete here too* / *restore to the cloud* / *decide later*. This applies to the change-log reader, the first pinning step (`--max-delete`) and the hourly reconciliation (bisync's "too many deletes" abort). Pending decisions: `onedrive-borrados --lista`.
- Pinning never deletes anything in the cloud. The one-way "keep uploaded" mode moves replaced or deleted cloud files to `_reemplazados-<host>/` instead of deleting them.
- OneDrive keeps per-file version history; if something ever goes wrong, that is where to look.

## What it is not

- **Not instant from the cloud side.** A change made on another device reaches a pinned folder in about 1–2 minutes: that device's upload time, plus the 30–90 s Microsoft takes to publish it in the change feed. Measured: edit 154 s end to end (54 s of which was the Mac uploading), rename 63 s, delete ~60 s. Linux → cloud is seconds.
- **Not a replacement for a real client on huge trees of tiny files.** Every file is a request to Microsoft; `node_modules` with 40 000 files will take a while whatever you do.
- **Nothing is deleted in the cloud by unpinning.** Unpin keeps both copies. Two-way sync *does* propagate deletions you make yourself, as any sync does.

## Uninstall

```bash
./uninstall.sh
```

Keeps `~/.onedrive-local` (your local copies) and `~/.config/onedrive-sync` (lists and logs).

## License

MIT.
