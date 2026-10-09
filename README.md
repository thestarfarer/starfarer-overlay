# starfarer-overlay

Personal Gentoo overlay: a few ebuilds plus a `patches/` tree for `/etc/portage/patches`, synced like any other overlay.

## Setup

```ini
# /etc/portage/repos.conf/starfarer.conf
[starfarer]
location = /var/db/repos/starfarer
sync-type = git
sync-uri = https://github.com/thestarfarer/starfarer-overlay.git
auto-sync = yes
```

```sh
emaint sync -r starfarer
```

To use the patches, point `/etc/portage/patches` (or individual package dirs in it) at the synced tree:

```sh
mv /etc/portage/patches /etc/portage/patches.bak   # keep anything you have
ln -s /var/db/repos/starfarer/patches /etc/portage/patches
```

`eapply_user` applies everything under `patches/` to matching builds, so only sync patch repos you trust.

## Ebuilds

| Package | Notes |
|---|---|
| `media-sound/jamesdsp-9999` | JamesDSP (JDSP4Linux) built against Qt 6, PipeWire or PulseAudio. Live, unkeyworded. |
| `x11-misc/mygestures-9999` | Mouse gestures for X, pinned to commit `0c033bf`, with a gcc 14 fix. |
| `www-client/waterfox-bin-6.7.4` | GURU's ebuild without its `!www-client/firefox-bin` blocker. The two packages share no files (`/opt/waterfox` vs `/opt/firefox`, separate binaries, icons and desktop files). |

## Patches

| Path | What |
|---|---|
| `sys-apps/portage/portage-direct-deps-only.patch` | Scheduler parallelism fix, see below. |
| `x11-terms/st/st-0.9.3-scrollback-ringbuffer-mouse-blink.diff` | suckless scrollback (ringbuffer, mouse, altscreen) and blinking cursor patches, rebased into one patch for st 0.9.3 (applies with fuzz 0). Output no longer snaps a scrolled-back view to the bottom: the view stays on the same lines, and typing returns to the bottom. Use an unversioned savedconfig (`/etc/portage/savedconfig/x11-terms/st`) so your config survives version bumps. |
| `media-sound/cantata/cantata-modified-column.patch` | "Modified" play queue column, plus sort by length, disc and original year. |
| `media-sound/cantata-3.3.0/qregularexpression-streamsmodel.patch` | Missing `QRegularExpression` include. |
| `games-util/lutris/no_webkit.patch` | Lets Lutris run without WebKit (disables web-login services). |
| `sys-apps/sysvinit/nowall.patch` | No `wall` broadcast on shutdown. |

## The portage scheduler patch

### Symptom

`emerge --jobs=16` running one package at a time for hours, with load around 5 on 16 threads. This happened during a large `@world` update on portage 3.0.82.2.

### What was throttling it

Four separate mechanisms, found in this order:

1. **`--jobs-tmpdir-require-free-gb`** (new in 3.0.82, [bug 934382](https://bugs.gentoo.org/934382)). It requires 18 GiB plus 1 GiB per running job free in `PORTAGE_TMPDIR`. On a 16 GiB tmpfs that can never pass, even right after a flush, so `--jobs` collapses to 1 permanently. Fix: `--jobs-tmpdir-require-free-gb=0`.
2. **`FEATURES=merge-wait`** (default on). Finished builds can't merge while anything else is building. Fix: `FEATURES=-merge-wait`.
3. **`--implicit-system-deps`** (default `y`). Deep `@system` runtime dependencies are ordered first and merged alone. See also [PR #1679](https://github.com/gentoo/portage/pull/1679), which adds `--merge-wait-scope`.
4. **`Scheduler._dependent_on_scheduled_merges()`**, which no option controls. Before starting a package, it walks the package's entire dependency graph, including through packages that are already installed or already finished in this run, and blocks if it finds anything still building or queued ahead.

The fourth one dominated. On the system in question, installed-package dependencies formed a strongly connected cycle of about 510 packages around `sys-libs/glibc`, including 92 perl modules. Two of the paths:

```
glibc → libidn2 → perl → perl-cleaner → portage → gemato → gnupg → pinentry[qt6]
      → qtbase → qtmultimedia → ffmpeg[samba] → samba → dev-perl/JSON → JSON-XS → common-sense
glibc → python → automake → help2man → dev-perl/Locale-gettext
```

Inside a cycle, every member reaches every other, so whichever one is building blocks all the rest. About 91% of installed packages depended on that cycle, so they waited on it as well. The cycle figures come from analysing the installed package database (`/var/db/pkg`), which approximates portage's own graph.

### The patch

It stops the walk after a package's direct dependencies. A package still waits for its own unmerged dependencies, which is a real build-order requirement. It no longer waits for unrelated packages that happen to sit behind installed ones.

### Risk

Builds no longer wait for indirect dependencies to finish merging, so a build can occasionally see a dependency of one of its dependencies being replaced. This is the same class of risk as `-merge-wait`. It is limited because portage installs files by atomic rename and keeps old sonames via `preserve-libs`. In practice it shows up as a rare build failure that succeeds on retry. Use `--keep-going`.

Tested against portage 3.0.82.2. On a portage upgrade, check that the patch still applies. The anchor is the "Don't traverse children of uninstall nodes" block in `lib/_emerge/Scheduler.py`.

### Related upstream

- [PR #1679](https://github.com/gentoo/portage/pull/1679), `--merge-wait-scope`: relaxes merge barriers, not this build-start walk.
- [Bug 403895](https://bugs.gentoo.org/show_bug.cgi?id=403895), "emerge with parallel jobs quickly degrades to building only one package at a time".
- [Bug 279623](https://bugs.gentoo.org/show_bug.cgi?id=279623), request for an aggressive `--jobs` mode.

## License

GPL-2, the same as Gentoo and portage. Patches to third-party software keep their upstream licenses.
