# Creating a game plugin

A k4 game is a visual plugin backed by a persistent simulation. Keep the game
state separate from the interface:

```text
services/MyGame.qml       ← state, rules, clock and persistence
plugins/MyGame/
├── MyGamePlugin.qml       ← island, IPC and lifecycle
├── MyGameView.qml         ← header, tabs and actions
├── Enemy.qml              ← visual components
└── qmldir
```

The included dungeon follows this pattern: `services/Game.qml` owns the idle
simulation and persistence; `GamePlugin.qml` owns opening, chests and IPC;
`GameView.qml` and its components render each tab.

## Simulation service

Declare the service as a singleton in `services/MyGame.qml`:

```qml
pragma Singleton
import QtQuick
import K4 as K4
import Quickshell
import Quickshell.Io

Singleton {
    id: game

    property int level: 1
    property int gold: 0
    property bool running: false
    property real lastTick: 0
    readonly property string path: K4.Paths.estado + "/my-game.json"

    signal waveCleared(int number)

    Timer {
        interval: 1000
        repeat: true
        running: game.running
        onTriggered: game.tick()
    }

    function tick() {
        lastTick = Date.now() / 1000
        gold += 1
        save()
    }

    function save() {
        state.setText(JSON.stringify({
            level: level, gold: gold, lastTick: lastTick
        }, null, 2))
    }

    K4.Fichero { id: state; path: game.path; blockLoading: true }
}
```

Include a timestamp in real games and calculate offline progress on startup,
with a sensible cap such as the dungeon's eight-hour limit. Never advance the
simulation only while the view is open: the service must continue to live when
the plugin is closed.

Add the singleton to `services/qmldir`:

```text
MyGame 1.0 MyGame.qml
```

## Game plugin

The plugin opens and closes the UI but does not contain the rules:

```qml
import QtQuick
import K4 as K4
import "../../core"
import "../../services"

K4Plugin {
    id: self
    name: "my-game"
    title: "My game"
    priority: 64
    active: habilitado && abierto
    tecladoOpcional: abierto
    property bool abierto: false
    property string tab: "game"
    property var panel: null

    islandWidth: 760
    islandHeight: tab === "game" ? 300 : 380

    function toggle() {
        abierto = !abierto
        if (abierto && panel)
            panel.close()
    }

    K4.Ipc {
        target: "k4.my-game"
        function toggle(): void { self.toggle() }
        function nueva(): void { MyGame.nuevaPartida() }
        function ver(name: string): void {
            self.tab = name
            self.abierto = true
        }
    }

    view: Component { MyGameView { plugin: self } }
}
```

User actions call service methods (`MyGame.buy()`,
`MyGame.launchAbility()`, `MyGame.equip()`), while the view reacts to service
properties and signals. Do not duplicate game state in the plugin and view.

## Tabs, components and data

For several game areas, keep a `tab` property in the plugin and split the view
into small components:

- `Battle.qml`: combat, timer and immediate actions.
- `Party.qml`: character selection and stats.
- `Inventory.qml`: items, equipment and contextual actions.
- `Achievements.qml`: progress and rewards.

Represent data as simple objects and replace collections when mutating them so
QML receives a change:

```qml
const copy = MyGame.items.slice()
copy[i] = Object.assign({}, copy[i], { equipped: true })
MyGame.items = copy
```

Use signals such as `hit`, `healed` and `levelUp` for temporary visual effects.
The simulation must remain deterministic and independent from QML animations.

## Indicators and settings

An idle game should report progress while closed:

```qml
Component.onCompleted: K4.Pildora.registrar(
    "my-game.status", "wave 1", 0xF04E5, "#bf5af2", 64, true)
```

Update the indicator on milestones or when a reward is available. Global
persistent options (for example, chaining runs or showing the indicator) belong
in `services/Settings.qml`, not in the view.

## Stage effects

A game earns a lot of feel from the bar itself. Tint the ambience for a boss
or a season (`K4.Tema.tintar`), shake the island on a critical hit or tug it
when a fish bites (`K4.Isla.efecto`), or let something physically peek out
of the island with a `K4.Ventana` anchored to `K4.Isla.rect` — and slide the
whole island along its edge for a scene with `K4.Isla.colocar`. Read
`K4.Isla.posicion` instead of assuming the bar lives at the top.

Spend these at the moments that matter. The bar is sober the rest of the
time, and that restraint is what makes the effect land.

## Balance and testing

Keep curves and constants at the top of the service with explicit names and
units. Separate pure simulation functions (`damageOf`, `rewardOf`, `levelOf`)
from functions that write state so they can be tested without starting
Quickshell. Cover:

- new and finished runs;
- offline progress and its cap;
- rewards and chests;
- unlocks and persistence after restart;
- pause and plugin disable behavior.

Register the plugin and service, run the validators, and document IPC commands
and dependencies before publishing.
