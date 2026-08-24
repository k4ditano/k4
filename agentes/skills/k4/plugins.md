# Writing a k4 plugin

Read this before creating or editing anything under `~/.config/k4/plugins/`.

## Start from something that already runs

```sh
cd ~/.config/quickshell/k4
python3 tools/plugins.py --new mi-plugin
```

That writes `~/.config/k4/plugins/mi-plugin/` with a manifest and a QML file
that already work. Do not start from an empty folder and do not copy a
built-in plugin by hand — the generated one is the shortest path to something
on screen, and from there every change is small enough to see.

Then, still without touching the running bar:

```sh
python3 tools/plugins.py --test mi-plugin     # opens it in its own instance
python3 tools/plugins.py                        # validates it
```

## What `--new` gives you

This is the whole thing it writes, and it is worth reading before changing
anything — it is the shape every k4 plugin has.

`plugin.json`:

```json
{
  "id": "demo",
  "entry": "DemoPlugin.qml",
  "version": "0.1.0",
  "title": "Demo",
  "description": "Un plugin recién nacido",
  "host": ">=1.1.0",
  "permisos": [],
  "superficies": ["island"]
}
```

`DemoPlugin.qml`:

```qml
import QtQuick
import K4 as K4

K4.Plugin {
    id: raiz

    name: "demo"
    title: "Demo"

    //  How much room it asks for in the island.
    islandWidth: 320
    islandHeight: 120

    //  The host opens and closes through these.
    property bool abierto: false
    active: abierto
    function toggle() { abierto = !abierto }
    //  Without close(), ESC does nothing: the host closes by calling it.
    function close() { abierto = false }

    view: Component {
        Item {
            K4.Etiqueta {
                anchors.centerIn: parent
                text: "Hola desde Demo"
                font.pixelSize: 16
            }
        }
    }
}
```

Nine things that are easy to get wrong and cost an hour each:

- **The plugin object is created once and stays alive; the *view* comes and goes.** Keep state on the plugin, not in the view, or it resets every time the user closes it.
- **`close()` is not optional.** The host closes a plugin by calling it. Without it, ESC does nothing and the user has to click away.
- **Use `K4.Etiqueta`, not a bare `Text`.** It carries the theme, and it already sets `textFormat` — see the trap at the bottom of this file.
- **A separate view file needs its plugin handed to it, by the plugin.** Write `view: Component { MiVista { plugin: raiz } }`. The host injects nothing. Miss it and the view starts with "Required property plugin was not initialized" and renders blank. The generated template hides this because its view is inline.
- **Declare `K4.Ipc`, `K4.Process` and timers as plain children, never as named properties.** `services` is `K4.Plugin`'s default property, and it is where the manager looks for IpcHandlers to switch off when it tears a plugin down. Tucked inside `property K4.Ipc ordenes: ...` it never finds them, so hot-reloading leaves the target held by the corpse: the new instance registers in vain ("another handler is registered") and IPC answers "Function not found" from the dead one. Restarting the bar hides it, which is what makes it hard to see.

- **A panel that opens, gets read and gets closed needs `grabKeyboard`.** Without it the layer only receives keys if the user *clicks* it, and nobody clicks a panel opened from the app centre, the launcher or a shortcut — so ESC never arrives. The cruel part: it appears to work if you happened to hover it first, so testing by hand says it is fine. `api/K4/Plugin.qml` documents this at length under `tecladoOpcional`; read it before choosing.

- **And `grabKeyboard` only while the *user* has it open.** It leaves the
  desktop without a keyboard for as long as your panel is up. If your plugin
  ever opens *itself* — an alarm, a timer finishing, an alert — keeping
  someone's keystrokes because a countdown ended is theft. Bind it to who
  opened it: `grabKeyboard: abierto && !meAbriYo`.

- **`handlesBackgroundTap: true`, or a tap on your panel opens the control
  center on top of it.** That is the host's default for a tap nobody claimed,
  and it is the worst of both worlds: your panel stays and something else
  covers it. Claim the tap and close on it. Between Esc, the background and a
  visible ✕, ship all three — the first two have to be known, and a cross does
  not.

- **Choose `priority` above 50, or the clock eats your panel.** The bar's
  resting views — clock at 50, player at 55 — activate on `Island.hovered`, so
  a panel below them turns into the clock the moment the user puts the pointer
  on the island *to reach your close button*. Measured map: 40 volume, 50
  clock, 55 player, 59 toast, 60 control center, 64 dungeon, 66 settings, 80
  launcher. Above the resting views so you survive being touched; below what
  the user opens on purpose if yours can open itself.

- **`"aplicacion": true` in the manifest, or nobody finds you.** The app centre
  filters on exactly that key, so without it your plugin is installed, enabled,
  working — and absent from the grid where people look for what the bar can
  open. Give it an `"icono"` too (a `0x…` codepoint or a file): without one the
  grid paints the generic icon and a good plugin looks like filler.

**An animation that nobody sees still runs.** In Qt Quick an animation does
not stop because its item stopped being visible: it keeps running, and the
whole scene keeps repainting at the monitor's rate while it does. A bar that
should be idle was rendering **122 frames per second** because of a five-pixel
dot pulsing in the pill whenever the dungeon had unopened chests — the
condition asked about *data*, never about being seen. Anything with `loops:
Animation.Infinite`, a repeating `Timer` or a self-repainting `Canvas` asks
`K4.Isla.aLaVista` first. What lives inside your view is free: the view is
destroyed when you lose the island.

And one that is worse than an hour: **never run a probe that can block.** A `Process` a plugin fires on a timer will pile up if the command hangs — in testing, a probe that talked to another app over IPC left ten stuck processes, one every five seconds, in a live bar. Give any probe a watchdog timer that stops it, and prefer a command that cannot wait on anything.

## The two files

`plugin.json` — the manifest:

```json
{
  "id": "mi-plugin",
  "entry": "MiPluginPlugin.qml",
  "version": "1.0.0",
  "title": "Mi plugin",
  "description": "Una línea de qué hace",
  "host": ">=1.1.0",
  "permisos": [],
  "superficies": ["pildora"]
}
```

`id` must match the folder name and be lowercase with dashes. `permisos` and
`superficies` are the two lists that matter and both are checked; see below.

The entry QML is a `K4.Plugin`. From there you get the whole API under the
`K4` namespace — the same one the built-in plugins use.

## Permissions

`permisos` declares which parts of the API the plugin touches.
`tools/plugins.py` reads the QML, finds what it actually calls, and compares.
**Using something without declaring it makes the plugin fail to load**, with
the reason recorded — it is not a warning.

The current list is in `docs/PLUGINS.md`; `procesos`, `red`, `ficheros`,
`portapapeles`, `sonido` and `datos-personales` are the ones that come up
most. Declare the smallest set that works.

Permissions are honest about what they are: a plugin runs inside the bar and
can do whatever the bar can do. The list is what it *declares*, not a cage.
When you write a plugin for someone else, that is worth saying plainly rather
than implying a sandbox that does not exist.

## Surfaces

`superficies` says where the plugin *appears*, as opposed to what it touches:
`island`, `pildora`, `ventana`, `ipc`, `atajo`. It is optional, and worth
filling in — it is what lets the user see what a plugin will occupy before
turning it on.

## While you are writing it

- **Reload without restarting**: `quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4 pluginReload mi-plugin`. It swaps the running code for what is on disk. If you **added or renamed an IPC function**, the first reload may still answer "Function not found": call it twice before suspecting your code.
- **After adding or removing a plugin folder**: `... call k4 pluginRefresh` makes the bar re-read the catalog.
- **When it does not appear**: `... call k4 pluginStatus` returns JSON with every plugin's enabled state and error. That is faster than reading the log, and the error is usually a missing import or an undeclared permission.
- **Its own files**: `K4.Plugin.carpeta` is the plugin's real directory and `fichero("x.py")` resolves a path inside it. Use those to run your own scripts — `Qt.resolvedUrl` returns a `qs:@/qs/...` URL that a process cannot open.

## A trap worth knowing about

QML `Text` defaults to `Text.AutoText`, which *interprets markup*. If a plugin
shows anything the user did not type itself — a filename, a song title, the
response from a command — set `textFormat: Text.PlainText`. Otherwise a name
containing `<img src=...>` gets rendered as an image request rather than shown
literally. k4 has a check for this (`tools/prueba_texto.py`) because it has
gone wrong before.

## Publishing it

When it works, open the **Publish a plugin** issue form on the k4 repository
with the repository URL and the full 40-character commit SHA. A bot fetches
that exact commit, validates it without running any of it, and comments with
what it found: what the manifest declares, which permissions it asks for,
which surfaces it occupies.

Publishing a commit rather than a branch is the point — a branch moves after
it is reviewed, and then what people install is not what was looked at. To
publish a new version, open another submission with the new SHA.
