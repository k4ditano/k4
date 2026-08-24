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

**One pass is not enough.** A launch leaves a parent that respawns its child
when you kill it, so the count after a single `pkill` is one, not zero. Loop
until it is really empty, and filter out zombies while counting — `<defunct>`
entries from earlier restarts inflate every naive count:

```sh
vivos() { ps -eo pid,stat,cmd | grep -i quickshell \
    | grep -v defunct | grep -vE "wl-paste|[g]rep"; }
until [ -z "$(vivos)" ]; do
  for p in $(vivos | awk '{print $1}'); do kill $p; done
  sleep 1
done
```

A fast tell that you got it wrong: `hyprctl monitors -j` and look at
`reserved`. The bar reserves 34 px at its edge, so **68 means two bars**.
Anything measuring double is two instances before it is a bug in your maths.

Every launch also orphans a pair of `wl-paste` clipboard watchers, and they
never die on their own — they pile up by the hundred over a debugging session.
With the bar stopped they are all orphans, so clear them before starting:

```sh
for p in $(ps -eo pid,cmd | grep "[p]ortapapeles.py guardar" | awk '{print $1}'); do
  kill $p
done
```

## The bar may be hidden on purpose

Before diagnosing "the bar is not showing", check the space mode: Settings →
Island → *How it takes up space*. In **Hidden** the island retreats past the
edge and only comes back when something happens or the pointer brushes the
4-px strip where the pill lives — a working bar looks like a missing one.
`quickshell ipc -p shell.qml call k4 settings` opens Settings if the pill is
not reachable.

## Settings, shortcuts, translations

- Settings live in the panel; plugins contribute their own rows through the API rather than editing a central file.
- Shortcuts are installed by `./instalar` into the Hyprland config and are listed in the bar's own searchable viewer.
- The UI is Spanish with translation files in `traducciones/`. `python3 tools/textos.py` reports coverage and can wrap new literals. A string only gets translated if it goes through `Idioma.t("...")`.
