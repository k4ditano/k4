# Creating a plugin

k4 loads plugins from two places: the repository's (`plugins/`) and the
user's in **`~/.config/k4/plugins/<id>/`**. This guide is for the latter:
you do not need to touch the repository to write one.

The complete example for this guide lives in `ejemplos/hola/` and can be
copied as is:

```sh
cp -r ejemplos/hola ~/.config/k4/plugins/
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4 pluginEnable hola
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.hola toggle
```

> **You may not need to read this.** k4 installs a skill for coding agents
> (`agentes/skills/k4/`, linked by `./instalar`), so Claude Code, Codex and
> anything else that reads `~/.claude/skills/` or `~/.config/agents/skills/`
> already know everything on this page. Asking for the plugin you want is a
> legitimate way to get one — this guide is here for when you want to know
> what it is doing, or when you are doing it yourself.

## 0 · Installing one that already exists

To see what is published in the public registry:

```sh
python3 tools/plugins.py --search
python3 tools/plugins.py --search snake
```

Each entry prints its exact install command, with the commit already in it.
To publish yours, open a PR adding an entry to `plugins/registro.json`: id,
title, description, git repo, **commit** (the full 40-character SHA you want
published) and `carpeta` if the plugin does not live at the repo root.

**A registry entry publishes a commit, not a branch.** A branch moves after
it is reviewed, so what someone installs next month would not be what was
looked at — the point of pinning is that those two are the same thing. To
publish a new version, open another submission with the new SHA.

The easier route is the **Publish a plugin** issue form. Opening it (or
editing it afterwards) makes a bot fetch that exact commit, validate it with
`tools/plugins.py` — **without running any of your plugin** — and comment
with what it found: what the manifest declares, which permissions it asks
for, which surfaces it occupies. It then labels the issue `validado`, or
`revision-de-seguridad` if the plugin asks for permissions, or
`necesita-arreglos` with the reason.

The bot never publishes. Only a maintainer applying the `publicado` label
does, and even then the entry is written **only if the commit still matches
the one that was reviewed** — otherwise approving would mean approving "that
repository", which is a promise nobody can keep.

### Named rules

Beyond permissions — which say which *k4 API* a plugin touches — the checker
looks for patterns that make the code you end up running **not** the code
someone reviewed. Each one carries why it matters and how to fix it, because
a warning that doesn't say what to do gets ignored:

| Rule | What it looks for |
|---|---|
| `descarga-y-ejecuta` | downloading something and piping it to a shell |
| `sudo-sin-contrasena` | `NOPASSWD`, `sudo -n`, `pkexec` |
| `clon-sin-commit` | `git clone` of a remote without a pinned SHA |
| `qml-desde-texto` | `Qt.createQmlObject`, `eval`, `new Function` |
| `borra-a-lo-ancho` | recursive deletes with wildcards |

Only the first two **block publication**, and that split is deliberate. They
are unambiguous: whatever the URL serves, or whatever runs as root, was never
part of the commit anyone looked at. The rest can be perfectly reasonable in
context, so they mark the submission for a person to read rather than stopping
it — and even a maintainer's label cannot publish past a blocking rule.

Blocking applies to *publishing*, never to installing. If you bring your own
plugin to your own machine, the bar tells you what fired and why, and the
button says "Install anyway". Taking the choice away without explaining it
would be worse than letting you make it having read the reason.

None of this is a security audit and the report says so. Static checks on one
commit are what it is: a plugin runs inside the bar and can do whatever the
bar can do.

And if someone handed you a repository directly:

```sh
python3 tools/plugins.py --install https://github.com/quien/su-plugin
python3 tools/plugins.py --install https://github.com/quien/su-plugin \
                         --commit 4f1c2ab...   # that exact one
```

Without `--commit` you get the tip of the default branch, which is fine for
your own code and worth thinking about for someone else's. Either way the
commit that landed is written down, so you can always answer "what exactly
do I have installed?".

It clones to a temporary directory, validates the whole thing there, and
**only then** shows what it claims to be and which permissions it declares,
and asks. Nothing reaches your plugin directory without passing the same
exam the installed ones pass: there is no "half installed and broken". If
the QML uses something the manifest does not declare, it is rejected before
touching the disk.

It arrives **off**. Turning it on is a separate decision, made in Settings,
looking at those same permissions.

```sh
python3 tools/plugins.py --installed        # what you have, from where, at which commit
python3 tools/plugins.py --check         # what no longer matches the registry
python3 tools/plugins.py --update snake  # reinstall from its origin (tip)
python3 tools/plugins.py --update snake --commit 4f1c2ab...   # or that one
python3 tools/plugins.py --remove snake      # uninstall (--con-estado also
                                             # deletes what it saved)
```

`--check` answers the question the old installer could not: it compares
the commit each installed plugin actually came from against what the registry
publishes today, and tells you which ones have something new upstream — and
which ones were installed before any of this existed, so their commit is
simply unknown.

With the bar running, `k4 pluginRefresh` makes it re-read the catalog: what
you just installed appears and what you removed disappears without
restarting anything. And after updating an enabled one, `k4 pluginReload
<id>` swaps the running code — the old one stays alive in the bar until you
say so.

## 0b · Starting one

Do not start from an empty directory:

```sh
tools/plugins.py --new mi-plugin
```

That writes a manifest and a plugin that already opens, and tells you the three
commands that come next. The rest of this page explains what it wrote.

## 1 · The directory and the manifest

```text
~/.config/k4/plugins/hola/
├── plugin.json
├── HolaPlugin.qml
└── HolaView.qml
```

`plugin.json` is the manifest:

```json
{
  "id": "hola",
  "entry": "HolaPlugin.qml",
  "version": "1.0.0",
  "title": "Hola",
  "description": "Qué hace, en una frase — sale en Ajustes",
  "host": ">=1.1.0",
  "permisos": [],
  "superficies": ["island"]
}
```

- `superficies`: what your plugin **occupies**, as opposed to what it touches.
  `island` (it has a `view`), `pildora`, `ventana`, `ipc`, `atajo`. It is
  optional — a manifest without it still validates — but if you declare it,
  the validator checks it against what your QML actually does, the same way it
  already does with `permisos`. Declaring lets Settings describe your plugin
  without loading it.
- `id`: lowercase, no spaces, and it **must match the directory name**. If
  it collides with one of the bar's plugins, yours loses.
- `entry`: the file that inherits from `K4.Plugin`, inside the directory
  itself.
- `host`: the minimum bar version you need (`>=x.y.z`).
- `icono`: your icon, of one of these two kinds:
  - **a Nerd Font codepoint** as text, `"0xF011A"` — find it with
    `python3 tools/glifos.py <word>`. It inherits the theme's color, so it
    looks like the rest of the bar and dims and tints along with it.
  - **your own image**, `"icono.png"`: a PNG or SVG file **from your
    directory** (no paths: your icon is yours). A PNG must be at least
    **64×64** — below that it looks blurry exactly where people look the
    most, and a pixelated icon makes a good plugin look bad — and weigh
    less than 1 MB. SVG has no minimum, that is what scaling is for.

  It is validated at install time: an icon that does not exist, is too
  small or comes in a strange format is an installation error, not an empty
  little square in the application center. It shows up in Settings, in the
  application center and in the control center's shortcuts.
- `aplicacion`: `true` if yours is something that is **opened and used** —
  a game, a tool — and not an indicator or a service. With it you appear in
  the application center (SUPER+SHIFT+Space) and you can be pinned to the
  control center strip — where shortcuts are also reordered by dragging.
  You also appear when typing in the launcher (SUPER+Space), which remains
  a different drawer — the desktop applications' one — but finds both.
- `permisos`: which capabilities you use — see below. Empty if you only
  paint.

## 2 · The plugin and the view

The plugin is the state: it lives always, island or no island. The view
only paints, and only exists while the plugin holds the island.

```qml
// HolaPlugin.qml
import QtQuick
import K4 as K4

K4.Plugin {
    id: self
    name: "hola"                 // el mismo id del manifiesto
    priority: 65
    active: abierto              // ¿quiero la island ahora?
    islandWidth: 360
    islandHeight: 100

    property bool abierto: false

    view: Component { HolaView { plugin: self } }

    K4.Ipc {
        target: "k4.hola"
        function toggle(): void { self.abierto = !self.abierto }
        function close(): void { self.abierto = false }
    }
}
```

```qml
// HolaView.qml
import QtQuick
import K4 as K4

Item {
    required property var plugin
    K4.Etiqueta {
        anchors.centerIn: parent
        text: K4.Idioma.t("Hola desde un plugin de fuera")
    }
}
```

### Pick a priority above 50, or the clock eats your panel

`priority` decides who gets the island when more than one plugin wants it,
and the number is not decoration. The bar's **resting views sit at 50 and
55** — the clock and the player — and they activate on `Island.hovered`.

So a panel below 50 cannot be closed. To reach your close button the user
puts the pointer on the island; that turns the clock on; the clock outranks
you; and your panel becomes the clock **exactly as they were reaching for
it**. It is not a rare case: it is what happens every single time, and with
the bar in *Hidden* space mode it happens sooner, because entering with the
pointer is the first thing anyone does.

The map, so you can place yourself:

| | |
|---|---|
| 0 | the pill at rest |
| 40 | volume |
| 50 · 55 | **clock · player** — the hover views. Be above these. |
| 59 | notification toast |
| 60 · 64 · 66 | control center · dungeon · settings |
| 80 · 83 | launcher · window switcher |

Above the resting views so you survive being touched; below the things the
user opens on purpose if yours can open **itself**. A module that appears
over what someone was already doing is rude, and a plugin that announces
something is announcing it, not demanding the screen.

### The size is yours

You ask for `islandWidth` and `islandHeight`, and **you can change them
live**: a plugin can be a 200×150 strip and turn into a big screen
depending on what it is doing. The bar's video editor does exactly that.

```qml
islandWidth:  modo === "mini" ? 200 : 980
islandHeight: modo === "mini" ? 150 : K4.Isla.altoMaximo
```

The height ceiling is `K4.Isla.altoMaximo` (880 today). Asking for more
breaks nothing but does not grow either: the excess is clipped, and a
screen that cannot be seen whole is worse than a smaller one. If your
content can grow without limit, put it in a `K4.Rodillo` and keep the
height fixed.

Rules the bar enforces:

- **A plugin imports QtQuick and K4. Nothing else.** From your directory
  there is no path to the internal services, and that is on purpose: the
  public API is the contract that does not break under your feet on update.
- The root id should be `self`: a view with `required property var plugin`
  can shadow an id with the same name.
If you declare yourself `aplicacion`, the bar will open you by calling
`abrir()`. By default it uses your `toggle()`, which is what almost all of
them already have; redefine it if you need something else — for example
always opening instead of toggling.

- Processes, timers and IPC go as children of the `K4.Plugin`, not of the
  view: the view is destroyed every time you lose the island.

### An animation nobody sees still runs

**In Qt Quick an animation does not stop because its item stopped being
visible.** It keeps running, and while it runs the whole scene keeps
repainting — at the refresh rate, on every monitor, for as long as its
condition holds.

That is not a warning from the manual. k4's own pill had a five-pixel dot
pulsing whenever the dungeon had unopened chests:

```qml
SequentialAnimation on opacity {
    running: Game.cofres > 0        // ← data, not visibility
    loops: Animation.Infinite
    NumberAnimation { to: 0.3; duration: 900 }
    NumberAnimation { to: 1;   duration: 900 }
}
```

The condition asks about *data*, never about being seen. With 61 chests
sitting there it had been true for weeks, so the bar rendered **122 frames per
second while collapsed with nothing open** — around 6% of a core, day and
night, for a dot nobody was looking at. Fixing that one line took the bar to
**0 fps and 0.0% at rest**.

So an animation with `loops: Animation.Infinite` asks whether anyone can see
it:

```qml
running: hayAlgoQueContar && K4.Isla.aLaVista
```

`K4.Isla.aLaVista` is false while the island is retracted (the *Hidden* mode
in Settings), while a capture or a system dialog has it out of the way, and on
a monitor whose bar is not showing. It is published per screen, so with two
monitors the answer is "yes" when any of them shows it. With no bar behind it
— a `--test` run — it answers "yes", because an animation too many is easier
to notice than one that never starts.

Your view is destroyed when you lose the island, so an animation that lives
inside it goes away with it and costs nothing. The trap is everything drawn
where the view survives: what you contribute to the pill, your own
`K4.Ventana`, anything you hang in a place that is not yours.

The same reasoning covers anything that repeats without an end: a `Timer` with
`repeat: true`, a `Canvas` that repaints itself, an `AnimatedImage`. If it
runs forever, it needs a reason to be running *now*.

### Your own files

Your plugin knows where it lives. `carpeta` is its directory on disk, filled in
by the host when it creates you, and `fichero(...)` builds a path inside it:

```qml
K4.Process {
    command: ["python3", fichero("tools/mine.py")]
}
```

That is what lets you **ship your own things** — a script, a binary, a model, a
data file. `Qt.resolvedUrl("assets/x.png")` was already enough to *paint* an
image, but a `Process` wants a path, not a URL, and `K4.Paths.raiz` is the
bar's directory, not yours.

## 3 · What the API gives you

| Type | What for |
|---|---|
| `K4.Plugin` | the contract: island, priority, keyboard, view |
| `K4.Tema` | the palette (`tinta`, `superficie`, `apagado`…) and the fonts |
| `K4.Etiqueta` | text with the bar's defaults |
| `K4.Glifo` | a Nerd Font icon (find them with `tools/glifos.py`) |
| `K4.Icono` | a desktop-theme icon, by name |
| `K4.Miniatura` | the live thumbnail of an open window, by its address |
| `K4.Interruptor` | the bar's switch; it notifies, it does not flip itself |
| `K4.Deslizador` | slider with label and value |
| `K4.Medidor` | a bar that measures and is not touched: volume, progress, how much of a quota is gone |
| `K4.Baldosa` | the control center's pressable card |
| `K4.Boton` | round one-glyph button |
| `K4.Rodillo` | a scrolling area **that actually obeys the wheel**, house scroll bar included |
| `K4.Desplazador` | the house scroll bar — thin, fades away; attach it to your own lists |
| `K4.Estela` | the house caret, with the trail k4term leaves — use it as `cursorDelegate` |
| `K4.Aparicion` | enters with a fade instead of popping |
| `K4.FocoInicial` | moves the cursor to your text field on open |
| `K4.Idioma` | `t()` and `f()` — with no dictionary they return the text as is |
| `K4.Guardado` | your state as JSON, in YOUR directory, with `cargado`/`guardar` |
| `K4.Ipc` | your IPC target (`k4.<id>`) |
| `K4.Process` | external processes — requires the `procesos` permission |
| `K4.Terminal` | the house terminal: run a script where it best fits, open one — `ejecutar`/`abrir` require `procesos` |
| `K4.Sonido` | a short sound — requires the `sonido` permission |
| `K4.Fichero` | reading and writing files — requires `ficheros` |
| `K4.Pildora` | an indicator on the folded pill |
| `K4.Capsula` | a flank extension: the capsule grows toward a screen edge with your text |
| `K4.Submapas` | the Hyprland submap in force right now, read only |
| `K4.Paths` | paths: `estadoDe(id)` is your state directory |
| `K4.IconoPlugin` | a plugin's icon: its image if it brings one, its glyph if not |

And what you need when yours grows past the island:

| Type | What for |
|---|---|
| `K4.Ventana` | a window of your own, apart from the island: a full-screen picker, an editor, something worth real space |
| `K4.PorPantalla` | one copy of yours per monitor — with two screens almost nothing wants to exist once |
| `K4.Cargador` | loads the expensive part only when needed and drops it when not |
| `K4.Atajo` | a global shortcut, the kind that works no matter who has focus. Here you declare the name; binding it to a key belongs to the compositor's configuration |
| `K4.Apps` | the installed applications: name, icon, how to launch them |
| `K4.Sistema` | the loose ends: launching things, reading the environment, finding icons |
| `K4.MenuBandeja` | the menu a tray icon publishes |
| `K4.BloqueoSesion` | locking the session for real (`ext-session-lock`) |
| `K4.SuperficieBloqueo` | what is drawn while locked, one per monitor |
| `K4.Autenticacion` | checking that whoever is in front is who they claim, via PAM |

The last four are for replacing pieces of the bar — a lock screen of your
own, another tray — more than for an ordinary plugin. They are here because
the built-in modules use them and the rule is the same for everyone: if a
repository plugin can, an outside one can too.

(`K4.Puente` also exists and **is not for you**: it is how the bar hands
the API what it needs. Only someone implementing the API on another host
touches it.)

And the live system data:

| Type | What it gives | Writing requires |
|---|---|---|
| `K4.Audio` | volume, mute | `audio` |
| `K4.Medios` | what is playing: title, artist, artwork, position | `medios` |
| `K4.Notificaciones` | the ones that arrive, with the `llego()` signal | `notificaciones` |
| `K4.Red` | Wi‑Fi and Bluetooth — **read-only, no exceptions** | — |
| `K4.Escritorios` | which ones exist and which one you are on | — |
| `K4.Portapapeles` | the history — **just reading already requires** `portapapeles` | `portapapeles` |
| `K4.Reloj` | the time, from the bar's single clock | — |
| `K4.Huella` | the user's personal footprint, AGGREGATED (Steam library, package inventory) — double-keyed: your `datos-personales` permission AND the user turning each source on in Settings, everything off by default | `datos-personales` |

The line is drawn by the effect, not the module: looking at the volume does
nothing to anyone, raising it does. The clipboard goes the other way
because it holds passwords and tokens — there, the delicate part is
reading. And connecting to a network or pairing a device does not open even
with a permission: a mistake there costs your connectivity or hands your
laptop to a stranger, and no plugin idea makes up for that.

`K4.Medios.posicion` only advances if someone is watching: call
`seguirPosicion()` when your view mounts and `dejarPosicion()` when you
drop it, or the timer does not run.

With those pieces your plugin has the SAME face as the bar without drawing
a rectangle: `ejemplos/piezas/` is the showcase, copyable and runnable. And
a warning that saves you an afternoon: if you put your list in a plain
`Flickable` and its rows have hover or click, **the wheel will not work** —
a MouseArea accepts the wheel whether it handles it or not — and no error
will be raised. That is why `K4.Rodillo` exists.

For a game: `K4.Guardado` is the save and the high score,
`tecladoAlPasar: true` gives you the keys while the pointer is over the
island and hands them back when it leaves, and a `Timer` is the tick. Use
`grabKeyboard` only for something you open, look at and close: a game stays
open, and exclusive focus would leave the whole desktop unable to type. Do
NOT use `tecladoOpcional` for keys you expect to just work — on-demand means
the compositor only grants them if you CLICK the surface, so a game opened
by shortcut never sees a keystroke.

And the second half of the keyboard, which is a separate problem: the layer
having the keys does not mean your view receives one. The island's root also
claims focus — that is where ESC lives — so claim it back with
`K4.FocoInicial`, and not only on open: with `tecladoAlPasar` the keys arrive
when the pointer enters, and by then `FocoInicial` has already given up.

```qml
property var foco: K4.FocoInicial { objetivo: raiz }
Component.onCompleted: foco.reclamar()
HoverHandler { onHoveredChanged: if (hovered) raiz.foco.reclamar() }
```

Four more things every game needs, and none of them raises an error when
missing:

- `function close()` — the host closes the active module on ESC by calling
  it. Without it the key does nothing and your view becomes a trap.
- `handlesBackgroundTap: true` with an empty `onBackgroundTapped` — or a
  click on any gap in your view opens the control center.
- `closeOnHoverExit: false` — a game must not vanish when the pointer
  leaves mid-fight.
- Anything you put in `services/` is NOT hot-reloaded: `pluginReload`
  reloads your plugin directory only, so rule changes need the bar
  restarted.

The repo's dungeon (`plugins/Game/`) and the Digivice
(`plugins/Digivice/`, see `docs/DIGIVICE.md`) are the proof it can go far.
And what a game draws with is plain Qt: `AnimatedSprite`, `SpriteSequence`,
`ParticleSystem`, `Shape`, `ShaderEffect` and `Canvas` are all importable —
the rule is only that Quickshell stays hidden, not Qt.

## 3b · Showing up in places that are not yours

A plugin does not have to live only inside its island.

**Your settings, in Settings.** Without this, two options forced you to
invent a screen, a button to open it and a way to save them — and the user
had to learn a new place for every plugin.

```qml
K4.Ajustes {
    plugin: "hola"
    grupo: K4.Idioma.t("Hola")
    opciones: [{ id: "saludar", nombre: K4.Idioma.t("Saludar al abrir"),
                 desc: K4.Idioma.t("Si no, solo enseña el contador"),
                 glifo: 0xF1821 }]
    valores: ({ saludar: self.saludar })
    onCambiado: function (id, valor) { self.saludar = valor; self.apuntar() }
}
```

YOU keep the values: the bar asks through `valores` and notifies through
`cambiado`. That way what is shown is always what you actually have saved,
and not a copy that desynchronizes on the first failed write.

A switch per option is the default; `tipo` unlocks the other two:

```qml
opciones: [
    { id: "modelo", tipo: "eleccion", nombre: K4.Idioma.t("Modelo"),
      desc: K4.Idioma.t("Con cuál contesta"), glifo: 0xF06A9,
      alternativas: [{ codigo: "rapido", nombre: K4.Idioma.t("Rápido") },
                     { codigo: "capaz",  nombre: K4.Idioma.t("Capaz") }] },
    { id: "clave", tipo: "texto", secreto: true,
      nombre: K4.Idioma.t("Clave de API"),
      desc: K4.Idioma.t("Se guarda donde tú digas; la barra no la retiene"),
      pista: "sk-…", glifo: 0xF0306 },
    { id: "ancho", tipo: "numero", nombre: K4.Idioma.t("Ancho"),
      desc: K4.Idioma.t("Hasta dónde puede crecer"), glifo: 0xF046D,
      min: 60, max: 1200, paso: 20, unidad: "px" }
]
```

`opciones` is live: change it and the section redraws. An **empty list hides
the whole section**, which is how you say "this does not apply right now" —
useful when your options depend on something you only learn later, like
whether a program is installed or whether there is network. It has to be a
binding for that, not a value computed once:

```qml
//  Sin el programa detrás, la sección entera no sale.
opciones: !Consola.esNuestra ? [] : [ /* … */ ]
```

A number is two steppers with the value between them, for something you
nudge rather than type — a width, a cap, a count. `min`, `max` and `paso`
clamp it on every step and `unidad` is printed after the figure; what
arrives through `cambiado` is already an INTEGER inside those bounds, so
there is nothing for you to validate. A spent stepper stops answering
instead of offering a value you were going to reject.

A choice shows its `alternativas` as chips and `cambiado` delivers the
chosen `codigo`. A text is a free field — a URL, a model, a key: `pista` is
the empty field's gray, `secreto: true` masks it with dots once typing
stops, and the value arrives on confirm — Enter or a click outside — not
keystroke by keystroke. With this, a plugin that talks to a service, an AI
or a CLI configures itself in Settings like everything else, without
inventing a screen of its own.

**The pill's flank, and the capsule growing.** `K4.Pildora` gives you an
indicator *inside* the pill — a glyph and a few characters, arbitrated with
everyone else's. When that is too small to read at a glance, `K4.Capsula`
grows the capsule itself toward a screen edge carrying your text: for a
thing that is GOING ON and that the user must not have to remember — a mode
that grabbed the keyboard, a recording running, a long job in flight.

```qml
K4.Capsula {
    plugin: "rec"
    extension: grabando ? ({
        lado: "derecha",            // "izquierda" · "derecha"
        texto: K4.Idioma.t("Grabando"),
        glifo: 0xF037E,             // md-record_circle_outline
        color: K4.Tema.rojo,
        largoMaximo: 300            // px it may grow to
    }) : null
}
```

`extension` is a binding or it is nothing: it must produce a NEW object
when your state changes, since mutating the old one in place tells nobody.
Set it to `null` to fold the capsule back.

The width is not yours to fight for, and that is the point: the bar hugs
your text with the pill's own font and caps it twice — at your
`largoMaximo` and at the room left to the screen edge, so a capsule parked
at an aligned end never runs off the screen. The pill also stays itself:
its art, clock and tray do not move a pixel while the capsule stretches,
because the host anchors the island to keep the body still and grows toward
that one side only. Two plugins asking for opposite flanks both get one.

While a deployed view owns the island — the control center, the launcher —
the extension folds away with the pill and comes back when the pill does.
That rule is the capsule's, not yours.

`K4.Submapas.actual` is the first customer and a useful one on its own: the
Hyprland submap in force right now, `""` when there is none. A plugin may
not reach for Hyprland's event socket itself, so the bar listens and
publishes it. `plugins/Submap/` is the whole worked example — it imports
`QtQuick` and `K4`, nothing else, and could be dropped into
`~/.config/k4/plugins` as it stands.

**Your results, in the launcher.** You answer when you can; if yours is
expensive — a network query — you block nobody. Yours shows up **below**
the system's applications: that panel is theirs, and you are there to be
findable, not to compete.

```qml
K4.Lanzador {
    plugin: "hola"
    onBuscando: function (texto) {
        resultados = texto.length < 2 ? []
            : [{ id: "abrir", titulo: K4.Idioma.t("Abrir Hola"), desc: "…" }]
    }
    onElegido: function (id) { self.abierto = true }
}
```

## 3c · The island as a stage

Three pieces turn the bar into part of the game, not just its frame.

**Tinting the ambience.** `K4.Tema.tintar(tuId, color, fuerza, duracionMs)`
tints the whole neutral scaffold — island, surfaces, tracks — and
everything painted with the theme recolors itself. The ink and the colors
with meaning (green, red…) are not touched, so text stays readable and an
alert stays an alert. Strength is capped at 0.45 by the host; `duracionMs`
0 means "until you call `destintar(tuId)`", and disabling your plugin
untints on its own.

```qml
K4.Tema.tintar("mi-juego", "#26324f", 0.35, 4000)   // abismo, 4 segundos
```

**Asking for gestures.** `K4.Isla.efecto(tuId, nombre, fuerza)` moves the
island like a physical object: `"sacudida"` (a hit), `"empujon"` (something
heavy lands on it), `"tiron"` (something pulls at it, like a fish on the
line). The host animates and arbitrates: one gesture every half second at
most. The rare effect impresses because the bar is sober the rest of the
time — ask for it at the moment that matters and let it breathe.

**Painting outside.** `K4.Isla.rect` gives the island's real on-screen
geometry (`{ x, y, ancho, alto }`, the primary one if there are several);
with several monitors, `K4.Isla.rectEn(name)` gives each screen's own, and
a `K4.Ventana` picks its monitor with `pantalla`.
With a transparent `K4.Ventana` above everything and that rect, anything
can peek over the edge, fall off the bar or stroll across it — a waving
hand, the pet climbing down. `ejemplos/efectos/` ships all three pieces
working, hand included.

And since the bar no longer lives only at the top — the edge is chosen in
Settings — `K4.Isla.posicion` says which one it is (`"arriba"` or
`"abajo"`). The host takes care of its side (anchoring, flipped silhouette,
gestures pointing into the screen); your side is reading `rect` and
`posicion` instead of assuming up is up.

**Sliding it along the edge.** The island is not nailed to the center
either: the user picks its alignment in Settings, and a plugin can move it
TEMPORARILY with `K4.Isla.colocar(tuId, fraccion, duracionMs)` — 0 flush
left, 1 flush right, animated with the same spring as opening. It returns
to the user's base on its own: on timeout, with `soltar(tuId)`, or when
your plugin is disabled. It is for what a scene lasts — the island dodging
a hit, playing paddle, stepping aside to show something behind — not for
staying: the permanent position belongs to the user. `K4.Isla.colocacion`
tells the effective fraction right now.

**And `K4.Isla`** to know whether you are on display: `abierta`,
`ocupadaPor`, `raton`, `altoMaximo`. Read-only — who holds the island is
decided by the host comparing priorities, which is the only way two plugins
do not fight over the screen. Use it to skip animating and polling when
nobody is watching.

All three deregister on their own when your plugin is destroyed — disabled,
reloaded, uninstalled — and the manager also sweeps by id: a Settings row
that calls a dead plugin cannot exist.

## 3b · Commands: IPC targets and shortcuts

An `K4.Ipc` target and a `K4.Atajo` name are **shared between every plugin
on the bar**. Two plugins cannot hold `k4.notes`: the compositor and
Quickshell hand it to whoever registered first, and the loser stays loaded,
without errors, simply not answering. That failure is invisible — it only
shows up in the log, and only for IPC; duplicate shortcut names say nothing
at all.

So the bar checks it for you. `tools/plugins.py` reads the targets and
shortcut names **out of your QML** — not out of the manifest, because what
is registered is what the code says — and cross-checks them against
everything already installed. Whoever asks for a taken command is listed as
not loadable, with the reason:

```
  - notas: el comando k4.launcher ya lo registra «launcher»
```

Repo plugins come first in the combined catalog, so an outside plugin never
takes a command away from one of the bar's own — the same rule that already
governs ids. The commands each plugin registers travel in the catalog under
`comandos`, so Settings and the store can show them before you turn
anything on.

Two things this does not do yet, and it is better to know: the scan looks
for `target` and `name` in the first 400 characters of the block, so a
target hidden far below is not seen; and a shortcut **name** is not a key —
the key lives in the compositor's config (`hypr/k4.conf`), so a plugin
installed from the store declares its shortcut but nobody presses it until
that binding exists.

## 4 · Permissions

The manifest declares what you use; the bar checks it **before listing**:

| Permission | What betrays it |
|---|---|
| `procesos` | `K4.Process`, `K4.Terminal.ejecutar`, `K4.Terminal.abrir` |
| `red` | `XMLHttpRequest`, `WebSocket` |
| `ficheros` | `K4.Fichero` |
| `sonido` | `K4.Sonido` |
| `audio` | `K4.Audio.ponerVolumen`, `K4.Audio.alternarSilencio` |
| `medios` | `K4.Medios.alternarPausa`, `.siguiente`, `.anterior`, `.buscar` |
| `notificaciones` | `K4.Notificaciones.limpiar` |
| `portapapeles` | `K4.Portapapeles` — **even just reading it** |
| `datos-personales` | `K4.Huella` — **just naming it**: there is no innocent read of personal data |

All nine, and note where the line falls: `ponerVolumen` is watched and
`K4.Audio` is not, because looking at the volume does nothing to anyone and
changing it does. The clipboard is the only one reversed, because there the
delicate part is reading.

Using something without declaring it makes the plugin **not loadable**,
with the reason in Settings. And the honest part: this **is not a
sandbox**. QML runs inside the bar's process and a loaded plugin can do
whatever the bar can do. The permissions are informed consent — the user
sees them before turning it on — plus an analysis that catches carelessness
and simple deception, not a cage. Installing a plugin is trusting its
author.

## 5 · The lifecycle

1. Outside plugins arrive **disabled**: they are turned on in Settings (or
   `k4 pluginEnable <id>`), seeing description and permissions first.
2. Disabled = **not instantiated**: your IPC does not even exist.
3. If your QML does not compile, the bar starts without you and Settings
   shows the error with file and line; "retry" reloads from disk after you
   fix it, without restarting the bar.
4. `python3 tools/plugins.py` validates your manifest and permissions
   without starting anything.

### While you write it

The fastest loop does not involve your bar at all:

```sh
tools/plugins.py --test hola
```

That opens **only your plugin**, in a separate Quickshell instance: no bar, no
services, no notifications, none of your session. If it hangs, it hangs there.
Click outside to leave. It works for plugins written against the K4 API — which
is every plugin from outside — because the API falls back to sane defaults when
there is no bar behind it.

When you do want it in the real bar:

```sh
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4 pluginReload hola
```

It destroys your plugin and recreates it from disk: edit, reload, look. It
does not restart the bar or touch the others. It reloads the WHOLE
directory — entry and views — so it works just as well for a view tweak. If
the new version does not compile, your plugin is left in error with its
reason and the "retry" in Settings; the rest of the bar does not even
notice.

An honest warning: reloading destroys your object. Whatever holds state in
memory and was not saved with `K4.Guardado` is lost — which for development
is usually exactly what you want.

## Repository plugins

Contributing a plugin to the bar itself follows the same contract, with
three differences: the directory goes in `plugins/`, it is registered in
`plugins/catalog.json`, and the directory carries a `qmldir` with all its
types (Quickshell's URL scheme does not resolve siblings without it —
`tools/plugins.py` warns if it is missing). Repo plugins CAN use the
internal services via `"../../services"`, because they update together with
the bar.
