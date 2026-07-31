# Writing a k4 plugin

This is the quick reference. For complete guides see:

- [Public API](../docs/API.md)
- [Creating a plugin](../docs/PLUGINS.md)
- [Creating a game plugin](../docs/GAMES.md)

> A plugin imports `QtQuick` and `K4`. Nothing else from the host.

## Minimal plugin

```qml
import QtQuick
import K4 as K4
import "../../core"

K4Plugin {
    id: self
    name: "hello"
    title: "Hello"
    priority: 70
    active: habilitado && abierto
    islandWidth: 300
    islandHeight: 120

    property bool abierto: false

    view: Component {
        Item {
            IslandLabel { anchors.centerIn: parent; text: "Hello" }
        }
    }

    K4.Ipc {
        target: "k4.hello"
        function toggle(): void { self.abierto = !self.abierto }
    }
}
```

`K4Plugin` is the contract: it declares when the plugin wants the island, its
requested size, the view to render and keyboard behavior. The host binds
`habilitado` to `PluginManager`; it is different from `active`:

```qml
K4.Process { running: self.habilitado && self.abierto }
Timer { running: self.habilitado && self.abierto }
```

Processes, timers and IPC handlers are direct children of the plugin. A view is
mounted only while the host gives the plugin the island, so long-lived work must
not be declared inside the view.

## Exported types

| Type | Use |
|---|---|
| `K4.Process` | Run a process and read line or complete output |
| `K4.Ipc` | Expose commands to Hyprland and other clients |
| `K4.Fichero` | Read/write a small text or JSON file |
| `K4.Paths` | Installation, tools and state paths |
| `K4.Sistema` | Launch, open, notify, copy and read environment |
| `K4.Apps` | Installed applications and icons |
| `K4.Icono` | Theme-aware application icon |
| `K4.Ventana` | Full-screen layer-shell surface |
| `K4.PorPantalla` | One instance per monitor |
| `K4.Cargador` | Lazy-load expensive content |
| `K4.Atajo` | Global shortcut |
| `K4.Autenticacion` | PAM authentication |
| `K4.BloqueoSesion` | Real session lock surface |
| `K4.MenuBandeja` | Tray application menu |
| `K4.Pildora` | Small indicators in the folded pill |

## Catalog and registration

The host still loads plugins statically. A new plugin must be:

1. placed under `plugins/` with a `qmldir` file;
2. imported and instantiated in `shell.qml`;
3. added to `plugins/catalog.json`;
4. documented with its IPC commands and dependencies.

Validate the result with:

```sh
python3 tools/plugins.py
python3 tools/api.py
```

The catalog is intentionally not a code loader. k4 does not execute downloaded
QML, and plugins can launch local processes, so only reviewed code should be
installed.

## API changes

If a plugin needs a capability that is missing, add it under `api/K4/` rather
than importing a private Quickshell type in the plugin. Keep the wrapper small,
document its signals and properties, and update `docs/API.md` with an example.
Restart the bar after changing the `K4` module because QML caches imported
modules.
