# k4

An extensible Dynamic Island-style bar for [Hyprland](https://hyprland.org/),
built with [Quickshell](https://quickshell.org/). k4 stays compact at the
edge of the screen — top or bottom, wherever you put it — and expands only
when it has something to show.

## Features

- A media player with artwork, transport controls, seeking and a visualizer.
- A control center for Wi-Fi, Bluetooth, audio, notifications and system
  actions.
- A native notification server with actions, application focusing and recent
  notification history.
- An application launcher with package search and installation support on Arch.
- Hyprland theme controls: colors, gaps, borders, blur, shadows, animations and
  wallpaper.
- System tray support, clipboard history, window switching, session controls and
  configurable shortcuts.
- A screen capture and recording workflow with region/window selection, video
  preview, folder/editor actions and a full non-linear editor.
- An idle roguelite game implemented as a regular k4 plugin.
- Plugin enable/disable state, plugin indicators and a documented public API:
  plugins contribute their own Settings rows (switches, choices, free-text
  fields with secret masking for API keys), launcher results and pill
  indicators.
- The island as a stage for plugins: tint the whole bar's ambience, request
  physical gestures (shake, push, tug), read the island's real screen
  geometry to draw outside it, and slide it along its edge for the length of
  a scene.
- The bar lives where you put it: top or bottom edge, aligned left, center
  or right — and plugins adapt through the API instead of assuming.
- Spanish UI with translation files for additional languages.

The editor supports layered video and image timelines, cuts, empty layers,
cropping, resizing, audio tracks, subtitles, camera overlays and rendering to
MP4, WebM or GIF.

## Installation

The installer targets Arch Linux and reads the single dependency list in
[`dependencias.tsv`](dependencias.tsv).

```sh
curl -fsSL https://raw.githubusercontent.com/k4ditano/k4/main/instalar | sh
```

It installs the missing base packages, writes the Hyprland integration, starts
the bar and keeps a local checkout at `~/.config/quickshell/k4`.

To update an existing installation:

```sh
~/.config/quickshell/k4/instalar
```

Useful modes:

| Option | Effect |
|---|---|
| `--seco` | Diagnose without changing anything |
| `--si` | Do not ask for confirmation |
| `--opcionales` | Install optional packages too |
| `--sin-paquetes` | Skip package management |
| `--sin-reiniciar` | Do not restart the running bar |

The wallpaper selector requires `swaybg` (or a compatible `awww`/`swww`
installation). `swaybg` is part of the base dependency set because wallpaper
selection is a built-in feature.

To start the installed bar manually, use the wrapper so the `K4` QML module is
available:

```sh
~/.config/quickshell/k4/arrancar
```

## Requirements

The installer is the source of truth. The main runtime requirements include:

| Package | Purpose |
|---|---|
| `quickshell` and `hyprland` | Bar runtime and compositor |
| `python` | Helper tools |
| `qt6-multimedia` and `qt6-multimedia-ffmpeg` | Video/audio preview |
| `grim`, `slurp`, `satty` | Capture, region selection and annotation |
| `wf-recorder` | Screen recording |
| `swaybg` | Wallpaper backend |
| `ffmpeg`, `ffprobe`, `imagemagick` | Editing, probing and thumbnails |
| `zenity` | File selection dialogs |
| `wl-clipboard` | Clipboard integration |
| `fd` | Launcher and editor search |
| `pactl`, `wpctl`, `nmcli`, `bluez` | Audio, network and Bluetooth |
| `notify-send`, `xdg-open`, `xdg-user-dir` | Desktop integration |

Optional packages provide Whisper transcription, AUR support, NVIDIA metrics,
Codex integration and other enhancements.

### k4term, optional but well fitted

[k4term](https://github.com/k4ditano/k4term) is this project's own terminal.
The bar does not require it and never assumes it: `services/Consola.qml` looks
for a terminal once at startup — `k4term`, then `$TERMINAL`, then the usual
suspects — and everything that opens one goes through it, so with any other
terminal installed the update flow, the launcher and the Terminal plugin all
work the same.

What you get by having it is what needs both sides:

- a real terminal **inside the island** (`SUPER + Shift + T`), whose session
  outlives the view — closing it does not stop what is running;
- `SUPER + Alt + T` to pop that same session out into a window, in the
  directory it was left in;
- a pill in the bar counting long commands, and a notice when an agent rings
  the bell with its window unfocused;
- system updates and AUR installs running **inside the island** instead of
  opening a window — close the view and they keep going;
- k4term's own settings inside k4's Settings, and the bar's tint reaching the
  terminal background live.

Without k4term, the island terminal and the pill simply do not appear, and the
Terminal plugin opens your default terminal instead.

## Default shortcuts

The installer writes these bindings to `~/.config/hypr/config/k4.lua` (or the
equivalent `k4.conf` for the legacy Hyprland format):

| Shortcut | Action |
|---|---|
| `SUPER + Space` | Application launcher |
| `SUPER + I` / `SUPER + X` | Control center |
| `SUPER + N` / `SUPER + A` | Notifications |
| `SUPER + Z` | k4 settings |
| `SUPER + Tab` | Window switcher |
| `SUPER + Shift + W` | Hyprland theme |
| `SUPER + V` | Clipboard history |
| `SUPER + B` | File browser |
| `SUPER + K` | Shortcut viewer |
| `SUPER + L` | Lock screen |
| `SUPER + G` | Ask Codex |
| `SUPER + C` | Capture a region |
| `SUPER + Shift + C` | Start/stop recording |
| `SUPER + Shift + E` | Open the video editor |
| `SUPER + Shift + T` | Terminal in the island (same session, kept alive) |
| `SUPER + Alt + T` | Pop that session out into a window |
| `Print` / `Shift + Print` / `Ctrl + Print` | Region / screen / window capture |

The generated Hyprland file is owned by k4. User-specific overrides should be
placed after it in the main Hyprland configuration.

## IPC

The host exposes a compatibility target and each plugin exposes its own target.
For example:

```sh
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4 toggleLauncher
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.theme toggle
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.editor abrir
```

Important targets include:

| Target | Examples |
|---|---|
| `k4` | `toggleLauncher`, `togglePanel`, `windows`, `settings`, `lock` |
| `k4.panel` | `toggle`, `notifications`, `wifi`, `bluetooth`, `close` |
| `k4.theme` | `toggle`, `tab`, `preset`, `wallpaper`, `apply`, `save` |
| `k4.captura` | `menu`, `region`, `grabar`, `parar`, `grande` |
| `k4.editor` | `abrir`, `editar`, `retomar`, `imagen`, `formato`, `silencios` |
| `k4.game` | `toggle`, `nueva`, `pausa`, `ver`, `cofre`, `estado` |
| `k4.term` | `isla`, `sacar`, `abrir`, `aqui`, `abrirEn`, `ejecutar` |

Plugin management is also available from the host:

```text
pluginEnable <id>   pluginDisable <id>
pluginToggle <id>   pluginStatus
```

## Architecture

```text
shell.qml       host, arbitration and layer surface
core/           theme tokens, K4Plugin contract and stateless widgets
api/K4/         public plugin API
services/       persistent domain services and singletons
widgets/        data-driven reusable widgets
plugins/        one directory per built-in plugin
docs/           public API, plugin and game guides
tools/          helper scripts and validators
hypr/           generated Hyprland integration templates
```

The dependency direction is `core → services → widgets → plugins`. Plugins do
not import each other; references are injected by `shell.qml`.

## Developer documentation

- [Public API](docs/API.md): plugin contract, processes, state, IPC, windows,
  shortcuts and pill indicators.
- [Creating a plugin](docs/PLUGINS.md): directory layout, catalog registration,
  lifecycle, dependencies and PR checks.
- [Creating a game plugin](docs/GAMES.md): persistent simulation, offline
  progress, tabs, components and balancing.
- [API quick reference](api/LEEME.md): the exported `K4` types and implementation
  notes.

Plugins are loaded dynamically and in isolation: a broken one is recorded with
its error and the bar starts without it. Your own plugins live in
`~/.config/k4/plugins/<id>/` with a `plugin.json` manifest, arrive disabled,
and declare the permissions they use — informed consent plus static analysis,
not a sandbox. Browse the public registry with `python3 tools/plugins.py
--buscar`, or install straight from a repository with `--instalar <url>`.

Before opening a pull request, run:

```sh
python3 tools/plugins.py
python3 tools/api.py
python3 tools/guia.py
python3 tools/glifos.py
python3 tools/prueba_editar.py
git diff --check
```

## Contributing

Please keep new functionality inside the appropriate layer, document new IPC
commands and dependencies, and do not import private host services from a
plugin. Plugins can currently execute local processes, so only reviewed code
should be installed.

Naming convention (the codebase predates it; migrate names when you touch
them, never in bulk): the `K4Plugin` contract keeps its English members
(`open`, `close`, `toggle`, `active`, `view`), and everything else — services,
properties, functions, signals — is named in Spanish, which is the project's
voice. Do not add a third variant of an existing pair: if a file already has
`abrir()`/`cerrar()`, extend that.

## License

k4 is released under the [MIT License](LICENSE).
