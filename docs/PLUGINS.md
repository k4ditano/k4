# Creating a plugin

This guide describes an integrated k4 plugin. Dynamic third-party loading is
not enabled yet; until the manifest and permission model are complete, plugins
are added to the repository and registered explicitly in the host.

## 1. Create the directory

```text
plugins/Hello/
├── HelloPlugin.qml
├── HelloView.qml
└── qmldir
```

`qmldir` follows the Quickshell format:

```text
module qs.plugins.Hello
HelloPlugin 1.0 HelloPlugin.qml
HelloView 1.0 HelloView.qml
```

## 2. Write the plugin and view

The plugin owns opening state, processes, timers and IPC. The view only paints
what is visible while the host gives the plugin the island:

```qml
// plugins/Hello/HelloPlugin.qml
import QtQuick
import K4 as K4
import "../../core"

K4Plugin {
    id: self
    name: "hello"
    title: "Hello"
    priority: 70
    active: habilitado && abierto
    tecladoOpcional: abierto
    islandWidth: 360
    islandHeight: 120

    property bool abierto: false
    property string text: "Hello"

    view: Component { HelloView { plugin: self } }

    K4.Ipc {
        target: "k4.hello"
        function toggle(): void { self.abierto = !self.abierto }
        function close(): void { self.abierto = false }
    }
}
```

```qml
// plugins/Hello/HelloView.qml
import QtQuick
import "../../core"

Item {
    required property var plugin
    IslandLabel {
        anchors.centerIn: parent
        text: plugin.text
    }
}
```

Use `self` for the root ID. A view property named `plugin` can shadow an ID with
the same name. Declare processes and timers as direct children of `K4Plugin`,
not inside the view, so they continue working while the plugin is closed.

## 3. Register the module

Import the folder and instantiate the plugin in `shell.qml`:

```qml
import "plugins/Hello"

HelloPlugin {
    id: helloPlugin
    habilitado: PluginManager.estaHabilitado("hello")
}
```

References to other modules are injected here (`panel: panelPlugin`); plugins
should not import each other directly. Add the plugin to the catalog as well:

```json
{
  "id": "hello",
  "entry": "Hello/HelloPlugin.qml",
  "version": "1.0.0",
  "title": "Hello",
  "enabledByDefault": true,
  "configurable": true
}
```

`id` is stable, lowercase and space-free. `entry` points to the class that
inherits `K4Plugin`. The user's enabled state is stored in
`~/.local/state/k4/plugins.json`.

## 4. Lifecycle

There are three separate states:

1. `habilitado`: the user allows the plugin to run.
2. `active`: the plugin requests the island right now.
3. `viewLoaded`: the view is mounted or being released.

Expensive work should respect both permission and visibility:

```qml
K4.Process {
    command: ["python3", K4.Paths.guion("hello.py")]
    running: self.habilitado && self.abierto
}

Timer {
    interval: 1000
    running: self.habilitado && self.abierto
    repeat: true
    onTriggered: ...
}
```

With `closeOnHoverExit`, the host emits `hoverTimedOut()` after
`hoverExitDelay`; the plugin decides whether to close. When disabled, the host
calls `close()` if available and removes the plugin's pill indicators.

## 5. State, settings and dependencies

- Store small JSON state under `K4.Paths.estado` using `K4.Fichero`.
- Declare new external packages in `dependencias.tsv`.
- Do not hardcode `$HOME`; use `K4.Paths` or `K4.Sistema.entorno()`.
- Keep long-running dialogs in the plugin, not in a disposable view.
- Add global persistent options to `services/Settings.qml`.

## 6. Indicators and documentation

Use `K4.Pildora` for a small actionable signal. Prefix its ID with the plugin
ID, document every IPC command and add an example to the README when the command
is intended for users or shortcut authors.

## 7. Checks before a pull request

Run these commands from the repository root:

```sh
python3 tools/plugins.py
python3 tools/api.py
python3 tools/prueba_editar.py
git diff --check
```

`tools/plugins.py` validates the catalog, entries, folders and host registration;
`tools/api.py` checks that plugins do not bypass the public API.
