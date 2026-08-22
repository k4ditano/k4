# Writing a k4 plugin

Read this before creating or editing anything under `~/.config/k4/plugins/`.

## Start from something that already runs

```sh
cd ~/.config/quickshell/k4
python3 tools/plugins.py --nuevo mi-plugin
```

That writes `~/.config/k4/plugins/mi-plugin/` with a manifest and a QML file
that already work. Do not start from an empty folder and do not copy a
built-in plugin by hand — the generated one is the shortest path to something
on screen, and from there every change is small enough to see.

Then, still without touching the running bar:

```sh
python3 tools/plugins.py --probar mi-plugin     # opens it in its own instance
python3 tools/plugins.py                        # validates it
```

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

- **Reload without restarting**: `quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4 pluginReload mi-plugin`. It swaps the running code for what is on disk.
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
