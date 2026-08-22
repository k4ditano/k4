# Driving and debugging the k4 bar

## Talk to it

```sh
qs=~/.config/quickshell/k4/shell.qml
quickshell ipc -p $qs show                    # every target and function
quickshell ipc -p $qs call k4 pluginStatus    # returns JSON: id, enabled, error
quickshell ipc -p $qs call k4 settings        # toggles the settings panel
```

`show` is the authoritative list. Do not guess a function name from this file
— targets come and go with the plugins that publish them.

## When something is wrong

1. `pluginStatus` — a plugin that failed carries its error here.
2. `~/.local/state/k4/k4.log` — QML errors, `console.log`, everything the bar
   prints. The previous session is kept in `k4.log.1`, because a crash that
   forces a restart used to take the log explaining it with it.

## Restarting

Ask the user first. The bar holds live state — games in progress, terminal
islands, an unsaved editor session — and a restart loses it.

If you do restart, **count first**:

```sh
ps -eo pid,cmd | grep '[q]uickshell -p'    # must be empty before starting
```

Killing "the" bar and starting a new one is how you end up with several at
once, all answering IPC, with one of them serving stale answers. Kill every
pid, confirm zero, then start one.

Use `pkill -x quickshell`, never `pkill -f quickshell` — the pattern matches
your own command line — and never `pkill -x qs`, which would also take down an
unrelated Quickshell instance.

## Settings, shortcuts, translations

- Settings live in the panel; plugins contribute their own rows through the API rather than editing a central file.
- Shortcuts are installed by `./instalar` into the Hyprland config and are listed in the bar's own searchable viewer.
- The UI is Spanish with translation files in `traducciones/`. `python3 tools/textos.py` reports coverage and can wrap new literals. A string only gets translated if it goes through `Idioma.t("...")`.
