# k4

**A Dynamic Island for Hyprland.** It sits collapsed at the edge of your
screen and expands only when it has something to say — and everything it does,
including the parts that look built in, is a plugin.

[![Follow @k4ditano on X](https://img.shields.io/badge/follow-%40k4ditano-000000?style=flat&logo=x&logoColor=white)](https://x.com/k4ditano)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg?style=flat)](LICENSE)
[![Built with Quickshell](https://img.shields.io/badge/built%20with-Quickshell-5c6bc0?style=flat)](https://quickshell.org/)

<img src="screenshots/bar.png" width="100%" alt="The k4 bar at rest, collapsed at the top edge of the screen">

```sh
curl -fsSL https://raw.githubusercontent.com/k4ditano/k4/main/instalar | sh
```

Arch Linux and Hyprland. Installs what is missing, writes the Hyprland
integration, starts the bar, and keeps a checkout at
`~/.config/quickshell/k4`. Run `./instalar --dry-run` first if you would rather
see what it would do.

> ### Want your own widget? Ask your agent.
>
> k4 installs a skill for coding agents, so Claude Code or Codex already know
> what a k4 plugin looks like, how to test one without restarting your bar,
> and how to publish it. Say *"make me a k4 plugin that shows the train times
> to work"* and it starts from something that already runs.
>
> [How that works ↓](#or-just-ask-your-agent-for-one) · [Publishing yours ↓](#publish-it)

---

## What you get

| | |
|:--:|:--:|
| <img src="screenshots/launcher.png" alt="Application launcher"> | <img src="screenshots/control-center.png" alt="Control center with Wi-Fi, Bluetooth, sound and media"> |
| **Launcher** — apps, package search, install and update. | **Control center** — Wi-Fi, Bluetooth, per-device sound, player. |
| <img src="screenshots/theme.png" alt="Hyprland theme panel"> | <img src="screenshots/shortcuts.png" alt="Searchable shortcut viewer"> |
| **Hyprland's theme**, live — colors, gaps, borders, blur, animations, and the wallpaper. | **Every shortcut**, searchable — yours and the ones k4 adds. |

Plus notifications with actions and history, a system tray, clipboard history,
a window switcher, and a bar that lives wherever you put it — top or bottom,
left, center or right.

### Capture, and an editor that is not a separate app

<img src="screenshots/editor.png" width="100%" alt="The video editor: preview, tool panel and a two-layer timeline">

Region, window or screen; record; then land straight in a non-linear editor.
Layered video and image timelines, cuts, crops, audio tracks with ducking and
live noise removal, subtitles, camera overlay, silence detection, Whisper
transcription. Out the other side: MP4, WebM, GIF or 9:16 for Shorts.

### Wallpapers that move, and a palette that comes out of them

<img src="screenshots/fondos.gif" width="100%" alt="The wallpaper tab: picking a different video wallpaper, which crossfades in and keeps playing behind the bar">

The bar draws the wallpaper itself, on its own layer below the windows, so a
wallpaper can be a video or a GIF and not only a picture. Nothing new to
install: QtMultimedia was already a dependency, for the video editor.

And because k4 is the one drawing it, it can do what a wallpaper daemon cannot:
**pause the video when no window leaves any of it visible.** Measured on a
twelve-core machine, a 1080p60 loop costs about 1.5% of it while you can see it
and next to nothing while you cannot — which matters, because a daemon left to
itself decodes all day for nobody.

One wallpaper per monitor, and a transition when you change it: a crossfade, an
iris that grows out of the island, or a tide that rises from the bottom edge
with a wavy front.

The colour comes from the wallpaper too. k4 pulls a palette out of the image
and hands it to the three places colour shows up — the bar's own tint,
Hyprland's window borders, and the terminal. Pick a preset by hand and it
steps aside.

### Dual mode: the bar leaves the top and becomes a dock

<img src="screenshots/dual.gif" width="100%" alt="The bar splits in two, the halves run down the side edges of the screen and join at the bottom into a dock">

Press **SUPER + SHIFT + D** and the bar splits in two. The halves run down the side edges of
the screen like drops, meet at the bottom and close back into a dock — the
same silhouette, mirrored. Press **SUPER + K** whenever you want to see every
k4 shortcut and key binding in one place.

The top bar does not linger: it hands back the space it was reserving, and the
dock takes its own, so the desktop reflows once and then follows the movement.
While the halves are travelling they reserve nothing and pass over your
windows.

**Or a drop falls instead.** In Settings, *Transition effect* picks how the
change is told: the **trip** above, a **drop** — the bar stays put, a bead
swells under its bottom edge, the neck thins until it snaps, and it falls,
stretching, until it hits the bottom of the screen and spreads out into the
dock — or **instant**, no animation at all. The drop takes a second where the
trip takes three.

*Keep the bar when opening the dock* only changes what happens after that
shortcut: it keeps the top bar where it is instead of turning it into the dock,
so you get both. The drop was made for this: it does not tell a move, it tells
something coming loose, so nothing is missing up top.

<table>
<tr>
<td width="46%"><img src="screenshots/dual.png" alt="The dock at the bottom of the screen with its app drawer open above it"></td>
<td>

**It behaves like a dock.** What you pin stays; what you open shows up and
leaves on its own. Drag to reorder, drag out to drop. Clicking something
already running goes **to its window** instead of starting another — and when
there is more than one, a badge counts them and a row of live previews lets
you pick.

The app drawer grows out of the dock itself, with the applications on your
system: type to filter, `Enter` opens the best match, drag one onto the dock
to keep it there.

Any island shortcut brings the bar home — the dock retracts, the halves climb
back up, and what you asked for opens in the island. Unless the bar never
left: with both showing, the shortcut just opens what you asked for.

</td>
</tr>
</table>

---

## Plugins

The clock is a plugin. So is the launcher, the control center, the capture
tool. There is no privileged inner circle — **the API a stranger's plugin gets
is the API the launcher uses.** Plugins load in isolation, and a broken one is
recorded with its error while the bar starts without it.

### Install one from the bar

<table>
<tr>
<td width="50%"><img src="screenshots/plugins-discover.png" alt="The Discover tab, listing published plugins with their commit"></td>
<td width="50%"><img src="screenshots/plugins-installed.png" alt="The Installed tab, showing each plugin's permissions and origin"></td>
</tr>
<tr>
<td><b>Discover</b> — what is published, with the commit each entry pins.</td>
<td><b>Installed</b> — what you have, where it came from, what it asked for.</td>
</tr>
</table>

Installing shows you what the plugin declares, where it came from and **which
commit** — and installs that exact commit, so a branch moving while you read
cannot change what lands. From the terminal:

```sh
python3 tools/plugins.py --search          # what's published
python3 tools/plugins.py --install <url> --commit <sha>
python3 tools/plugins.py --check       # what of yours has something newer
```

### Write one in a minute

```sh
python3 tools/plugins.py --new mi-plugin   # a plugin that already runs
python3 tools/plugins.py --test mi-plugin  # opens it alone, not in your bar
```

`--test` matters more than it sounds: it runs the plugin in its own instance
with no bar, no services and no notifications, so an infinite loop takes down
a test window instead of your desktop.

Then `quickshell ipc -p shell.qml call k4 pluginReload mi-plugin` swaps the
running code for what is on disk, without restarting anything.

### Or just ask your agent for one

> **"Make me a k4 plugin that shows the train times to work."**

That works, and it is the point. k4 installs a skill for coding agents —
`./instalar` links it into `~/.claude/skills/` and `~/.config/agents/skills/`
— so Claude Code, Codex and anything else that reads those already know:

- that this machine runs k4, and that everything in the bar is a plugin;
- the shape of a plugin, with the whole starter file in front of them;
- which permissions exist, and that using an undeclared one makes it refuse to load;
- to test with `--test` instead of restarting your bar;
- to read `pluginStatus` when something does not show up.

Without that, an agent asked for "a widget for my bar" starts by guessing.
With it, it starts by running `--new` and editing something that already
works.

```sh
python3 tools/agente.py             # where it is, and whether it's linked
python3 tools/agente.py --install   # link it (./instalar does this for you)
```

The skill is [`agentes/skills/k4/`](agentes/skills/k4/) — a page on writing a
plugin and a page on driving the bar. It is linked, not copied, so it stays
current when k4 updates.

### Publish it

**1.** Push it to a public repository with a license, and check it passes:

```sh
python3 tools/plugins.py     # the permissions you declare are the ones you use
git rev-parse HEAD           # the SHA you want published
```

**2.** Open the [**Publish a plugin**](../../issues/new?template=publicar-plugin.yml)
issue with the repository URL and that full 40-character SHA.

**3.** A bot fetches **that exact commit**, validates it *without running any
of it*, and comments with what the manifest declares, which permissions it
asks for, and anything that tripped a named rule. Fix and edit the issue —
it re-reviews itself.

**4.** A maintainer applies the `publicado` label and it lands in the
registry. The bot never publishes on its own, and even a maintainer's label
will not publish past a blocking rule.

You publish a **commit, not a branch** — a branch moves after it is reviewed,
and then what people install is not what was looked at. New version, new
submission with the new SHA. That is a minute of work and it is what makes
the review mean anything.

### On permissions, honestly

A plugin declares what it uses, and `tools/plugins.py` checks that declaration
against what the QML actually calls — using something undeclared makes the
plugin refuse to load. On top of that, named rules flag patterns that make the
code you run stop being the code someone reviewed: `curl | sh`, passwordless
`sudo`, unpinned clones.

**This is informed consent plus static analysis, not a sandbox.** A plugin
runs inside the bar and can do what the bar can do. Install what you have read
or what you trust — everything above exists to make that judgement possible,
not to remove it.

Full guide: [docs/PLUGINS.md](docs/PLUGINS.md) · API: [docs/API.md](docs/API.md)

---

## Games, as ordinary plugins

Not special cases — the same contract as everything else. An idle roguelite, a
typing roguelike, an autobattler, and
[Digivice](https://github.com/k4ditano/digivice): a virtual pet whose road
advances on how you actually use the computer, reading nothing but *that* a
window changed.

**They arrive turned off.** A bar is not the place to be running a game nobody
asked for — and a plugin that is never enabled is never created, so it costs
exactly nothing. Turn one on in Settings when you want it.

---

<details>
<summary><b>Shortcuts</b></summary>

Written to `~/.config/hypr/config/k4.lua` (or `k4.conf` on the legacy format).
That file is owned by k4; put your overrides after it.

| Shortcut | Action |
|---|---|
| `SUPER + Space` | Application launcher |
| `SUPER + I` / `SUPER + X` | Control center |
| `SUPER + N` / `SUPER + A` | Notifications |
| `SUPER + Z` | k4 settings |
| `SUPER + Tab` | Window switcher |
| `SUPER + Shift + D` | Dual mode: the bar becomes a dock |
| `SUPER + Shift + W` | Hyprland theme |
| `SUPER + V` | Clipboard history |
| `SUPER + B` | File browser |
| `SUPER + K` | Shortcut viewer |
| `SUPER + L` | Lock screen |
| `SUPER + G` | Ask Codex |
| `SUPER + C` | Capture a region |
| `SUPER + Shift + C` | Start/stop recording |
| `SUPER + Shift + E` | Open the video editor |
| `SUPER + Shift + T` | Terminal in the island (sessions kept alive) |
| `SUPER + Alt + T` | Pop that session out into a window |
| `Print` / `Shift + Print` / `Ctrl + Print` | Region / screen / window capture |

</details>

<details>
<summary><b>IPC</b></summary>

```sh
quickshell ipc -p ~/.config/quickshell/k4/shell.qml show   # every target
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4 toggleLauncher
```

`show` is the authoritative list — targets come and go with the plugins that
publish them.

| Target | Examples |
|---|---|
| `k4` | `toggleLauncher`, `togglePanel`, `windows`, `settings`, `lock` |
| `k4.panel` | `toggle`, `notifications`, `wifi`, `bluetooth`, `close` |
| `k4.theme` | `toggle`, `tab`, `preset`, `wallpaper`, `apply`, `save` |
| `k4.captura` | `menu`, `region`, `grabar`, `parar`, `grande` |
| `k4.editor` | `abrir`, `editar`, `retomar`, `imagen`, `formato`, `silencios` |
| `k4.term` | `isla`, `nueva`, `siguiente`, `anterior`, `irA`, `ejecutar` |

Plugin management: `pluginEnable <id>`, `pluginDisable <id>`,
`pluginToggle <id>`, `pluginReload <id>`, `pluginRefresh`, `pluginStatus`,
`pluginCheck`.

</details>

<details>
<summary><b>Requirements and install options</b></summary>

The installer is the source of truth and reads
[`dependencias.tsv`](dependencias.tsv). The main ones:

| Package | Purpose |
|---|---|
| `quickshell`, `hyprland` | Bar runtime and compositor |
| `python` | Helper tools |
| `qt6-multimedia`, `qt6-multimedia-ffmpeg` | Video/audio preview |
| `grim`, `slurp`, `satty` | Capture, region selection, annotation |
| `wf-recorder` | Screen recording |
| `swaybg` | Wallpaper backend |
| `ffmpeg`, `imagemagick` | Editing, probing, thumbnails |
| `zenity`, `wl-clipboard`, `fd` | Dialogs, clipboard, search |
| `pactl`, `wpctl`, `nmcli`, `bluez` | Audio, network, Bluetooth |

Optional packages add Whisper transcription, AUR support, NVIDIA metrics and
Codex integration.

| Option | Effect |
|---|---|
| `--dry-run` | Diagnose without changing anything |
| `--yes` | Do not ask for confirmation |
| `--optional` | Install optional packages too |
| `--no-packages` | Skip package management |
| `--no-restart` | Do not restart the running bar |

The Spanish flags this started with — `--seco`, `--si`, `--opcionales`,
`--sin-paquetes`, `--sin-reiniciar` — still work and are not going away.

**Update with the same script**: `~/.config/quickshell/k4/instalar`. It pulls
with `--ff-only`, refreshes packages and shortcuts and offers to restart the
bar. With uncommitted changes in the checkout it leaves the code alone and
tells you so — nobody loses work to an update.

**And the bar tells you when there is one.** Settings shows the commit you are
on, and checks in the background — once a minute after start until it manages
to look, then every six hours — whether `origin` has moved. If it has, a pill
in the header says how many commits you are behind and runs the updater for
you. With uncommitted changes it says that instead of offering the button: the
installer would refuse anyway, and a button that does nothing is worse than no
button. `quickshell ipc -p shell.qml call k4.settings version` prints the same
thing as JSON. Start it by hand with
`~/.config/quickshell/k4/arrancar` — use the wrapper, so the `K4` QML module
resolves.

**[k4term](https://github.com/k4ditano/k4term)** is this project's own
terminal. It is never assumed: the bar looks for `k4term`, then `$TERMINAL`,
then the usual suspects, so everything works the same with any terminal. If
k4term shows up later the bar notices within a minute and the island terminal
turns itself on.

</details>

<details>
<summary><b>Architecture and contributing</b></summary>

```text
shell.qml       host, arbitration and layer surface
core/           theme tokens, the K4Plugin contract, stateless widgets
api/K4/         public plugin API
services/       persistent domain services and singletons
widgets/        data-driven reusable widgets
plugins/        one directory per built-in plugin
agentes/        the skill coding agents read
docs/           API, plugin and game guides
tools/          helper scripts and validators
hypr/           generated Hyprland integration
```

Dependencies flow `core → services → widgets → plugins`. Plugins never import
each other; references are injected by `shell.qml`.

Before opening a pull request:

```sh
python3 tools/plugins.py && python3 tools/api.py && python3 tools/guia.py
python3 tools/layouts.py && python3 tools/glifos.py
python3 tools/prueba_editar.py && python3 tools/prueba_plugins.py
python3 tools/prueba_rutas.py && python3 tools/prueba_texto.py
git diff --check
```

Naming: the `K4Plugin` contract keeps its English members (`open`, `close`,
`toggle`, `active`, `view`); everything else — services, properties, functions,
signals — is Spanish, which is the project's voice. Do not add a third variant
of an existing pair: if a file already has `abrir()`/`cerrar()`, extend that.
The codebase predates the rule, so migrate names when you touch them, never in
bulk.

More: [docs/API.md](docs/API.md) · [docs/PLUGINS.md](docs/PLUGINS.md) ·
[docs/GAMES.md](docs/GAMES.md) · [api/LEEME.md](api/LEEME.md)

</details>

---

MIT. Spanish UI with translation files in [`traducciones/`](traducciones/) —
English and Russian included.
