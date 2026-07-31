# k4 public API

This is the public surface available to plugins. The API lives in `api/K4/`; the
source files contain additional implementation notes.

## Imports

A plugin imports Qt and k4:

```qml
import QtQuick
import K4 as K4
```

Start the host with `arrancar`. It adds `api/` to `QML_IMPORT_PATH`; launching
`quickshell -p shell.qml` directly will not resolve `import K4`.

Qt (`QtQuick`, `QtMultimedia`, `Timer`, animations, and so on) is the portable
layer. Quickshell and Wayland should stay behind a `K4` API type whenever an
equivalent exists.

## Plugin contract

`K4Plugin` is the root object of a module:

| Property | Meaning |
|---|---|
| `name` | Stable, unique plugin ID |
| `title` | Human-readable name |
| `habilitado` | Persistent user permission |
| `active` | Requests the island right now |
| `priority` | Arbitration priority |
| `islandWidth`, `islandHeight` | Requested island size |
| `view` | Component rendered by the host |
| `viewLoaded` | Keep the size while the view closes |
| `grabKeyboard` | Exclusive keyboard focus |
| `tecladoOpcional` | On-demand keyboard focus |
| `closeOnHoverExit` | Enable hover-exit timeout |

`active` and `habilitado` are different states:

```qml
K4Plugin {
    name: "hello"
    active: habilitado && abierto
    property bool abierto: false
}
```

## Processes: `K4.Process`

`K4.Process` wraps an external process and provides two output modes:

```qml
K4.Process {
    id: query
    command: ["python3", K4.Paths.guion("data.py")]
    running: abierto
    onSalida: function (text) { model = JSON.parse(text) }
    onLineaError: function (line) { console.warn(line) }
}
```

For one event per line:

```qml
K4.Process {
    command: ["my-command", "--watch"]
    porLineas: true
    running: true
    onLinea: function (line) { ... }
}
```

Properties include `command`, `running`, `workingDirectory`, `environment`,
`porLineas` and `entradaAbierta`. Signals are `arrancado`, `linea`, `salida`,
`lineaError` and `terminado(code)`. Stop a process that writes a file with
`parar()` (SIGINT), not a hard kill.

## Files and paths

`K4.Paths` keeps plugins independent from filesystem layout:

```qml
readonly property string statePath: K4.Paths.estado + "/hello.json"
K4.Fichero { id: state; path: statePath; blockLoading: true }

function save() {
    state.setText(JSON.stringify({ count: count }, null, 2))
}
```

- `K4.Paths.estado`: `~/.local/state/k4`, for persistent state.
- `K4.Paths.raiz`: the k4 installation root.
- `K4.Paths.guion(name)`: a file inside `tools/`.
- `K4.Paths.enRaiz(relative)`: any repository asset.

`K4.Fichero` provides `path`, `text()`, `setText()`, `blockLoading` and
`onLoaded`. Use it for small JSON/text files, not media assets.

## System and applications

`K4.Sistema` provides desktop actions:

```qml
K4.Sistema.abrir(path)
K4.Sistema.lanzar(["program", "--option"])
K4.Sistema.avisar("Title", "Details", false)
K4.Sistema.copiar("text")
const home = K4.Sistema.entorno("HOME")
```

`K4.Apps.lista` contains installed desktop entries; `K4.Apps.porId(id)` looks
one up and `K4.Apps.icono(name)` resolves its icon. `K4.Icono` is an
`IconImage` ready to render.

## IPC, windows and shortcuts

Expose commands with `K4.Ipc`:

```qml
K4.Ipc {
    target: "k4.hello"
    function toggle(): void { self.abierto = !self.abierto }
}
```

Call it from Hyprland with:

```sh
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.hello toggle
```

- `K4.Ventana`: a full-screen `wlr-layer-shell` surface that does not reserve
  layout space.
- `K4.PorPantalla`: one instance per monitor.
- `K4.Cargador`: a `LazyLoader` for expensive views or windows.
- `K4.Atajo`: a global shortcut identified by `appid: "k4"` and `name`.
- `K4.Autenticacion`: PAM authentication state and signals.
- `K4.BloqueoSesion`: the real `ext-session-lock` surface.
- `K4.MenuBandeja`: an application tray menu.

## Pill indicators

Plugins can register a small indicator without editing `shell.qml`:

```qml
Component.onCompleted: K4.Pildora.registrar(
    "hello.status", "ready", 0xF05A1, "#30d158", 80, true)

Connections {
    target: K4.Pildora
    function onInvocado(id) {
        if (id === "hello.status") self.abierto = true
    }
}
```

Available operations are `registrar(id, text, glyph, color, order, visible)`,
`actualizar(id, fields)`, `quitar(id)` and `quitarDe(owner)`. IDs must start with
the plugin ID (`hello.`). The host removes a plugin's indicators when it is
disabled.

## Current boundaries

Plugin loading is dynamic and isolated: each plugin is created on its own, a
failure is recorded with its error, and the rest start. Disabled means not
instantiated. Third-party plugins load from `~/.config/k4/plugins/<id>/`.

What that does **not** mean is a sandbox. QML runs inside the bar's process and
a loaded plugin can do whatever the bar can do. The declared permissions are
informed consent — you see them before enabling — plus a static analysis that
turns carelessness and simple deception into an installation error. Installing
a plugin is trusting its author.

Two doors stay shut on purpose: connecting to networks and pairing Bluetooth
devices are read-only for plugins, with no permission that opens them.

The full guide, in Spanish and kept current by `tools/api.py`, is
`docs/PLUGINS.md`. New dependencies still go in `dependencias.tsv`.
