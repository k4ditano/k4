# k4

Una barra para Hyprland escrita en [Quickshell](https://quickshell.org), con la
forma y el comportamiento de la Dynamic Island de macOS. Inspirada en
[Atoll](https://github.com/Ebullioscopic/Atoll).

En reposo es una píldora negra pegada al borde superior de la pantalla. Se
expande al pasar el ratón, al recibir una notificación, al cambiar el volumen o
cuando la abres tú, y vuelve a encogerse sola.

## Qué hace

**Reproductor.** Al pasar el ratón sobre la píldora, si hay algo sonando, se
despliega el reproductor: carátula, título, artista, visualizador animado, línea
de tiempo con posición y tiempo restante (arrastrable para buscar) y controles
de transporte. Los navegadores no publican `mpris:artUrl`, así que la carátula
se deduce de `xesam:url`: miniatura de YouTube o preview de Twitch, y si no,
favicon del sitio o icono de la aplicación.

**Centro de control.** Clic en la island (o `SUPER+I`). Wi‑Fi, Bluetooth y
volumen, más reproducción y accesos directos. Pulsando el círculo del icono
enciendes o apagas la radio; pulsando el resto de la tarjeta entras al detalle,
donde puedes ver las redes con su intensidad, conectarte —pidiendo contraseña si
hace falta—, desconectarte u olvidarlas. En Bluetooth, lo mismo con emparejar,
conectar y nivel de batería.

**Notificaciones.** Servidor de notificaciones propio: aparecen como toast en la
island y se acumulan en una pestaña del panel, con borrado individual y "borrar
todo".

**Lanzador.** `SUPER+Space` abre un buscador de aplicaciones estilo Spotlight.
Escribiendo aparece además la opción **Instalar**, que busca paquetes en los
repos oficiales (`pacman`, instantáneo) y en AUR (`yay`, con retardo para no
abusar del RPC) y los instala en una terminal.

**Consultas a Codex.** `SUPER+G` abre un prompt en la island que habla con
[Codex CLI](https://developers.openai.com/codex/cli) usando tu cuenta de
ChatGPT. Conversación multi‑turno, y puedes adjuntar una captura de pantalla o
el texto que tengas seleccionado. Cada vez que se abre arranca una sesión nueva
para no mezclar contextos con otras sesiones de Codex.

**Tema de Hyprland.** Desde el centro de control (o `k4.theme toggle`) se
cambian presets de color, separaciones, borde, redondeo, desenfoque, sombras,
opacidades, animaciones y fondo de pantalla, viendo el resultado al momento.
Ver [Tema de Hyprland](#tema-de-hyprland) para cómo se aplica y se guarda.

**Bandeja del sistema.** Los iconos salen en la píldora, pero ahí son solo
indicadores: acercar el ratón cambia la island a la vista de reloj o de
reproductor, así que la píldora se desmonta antes de que puedas pulsar nada.
La fila se repite en esas dos vistas, ya desplegadas y quietas, y es ahí donde
se pincha: clic izquierdo abre la aplicación, el derecho despliega el módulo
con su menú, el central hace la acción secundaria y la rueda se le pasa tal
cual (subir el volumen, por ejemplo). El menú se dibuja dentro de la island,
no en una ventana emergente aparte.

Instanciar el servicio es lo que registra a k4 como anfitrión de bandeja, así
que **las aplicaciones que ya estaban abiertas antes puede que no aparezcan
hasta reiniciarlas**.

**El tiempo.** Estado actual, siguientes horas y seis días, con datos de
[Open-Meteo](https://open-meteo.com) —sin clave ni cuenta—. La ubicación se
adivina por IP la primera vez, que es aproximada, así que el buscador de
ciudades manda: lo que elijas se guarda y es lo que se usa a partir de
entonces. En el centro de control la tarjeta enseña ya la temperatura.

## Requisitos

| Para | Necesitas |
|---|---|
| Base | `quickshell` ≥ 0.3, Hyprland, `Adwaita Sans`, `MesloLGS Nerd Font` |
| Audio | `wireplumber` (`wpctl`) |
| Red | NetworkManager (`nmcli`) |
| Bluetooth | `bluez` |
| Capturas | `grim`, `slurp`, `wl-clipboard` |
| Consultas | `codex` autenticado con tu cuenta de ChatGPT |
| Instalar paquetes | `yay`, `pacman`, `kitty` |
| Fondo de pantalla | `awww` (o `swww`); si no, `swaybg` sin transiciones |
| El tiempo | `curl` y conexión a internet |

Todo lo que no sea la base es opcional: la parte correspondiente simplemente no
aparece o no hace nada.

## Instalación

```sh
git clone git@github.com:k4ditano/k4.git ~/.config/quickshell/k4
quickshell -p ~/.config/quickshell/k4/shell.qml --no-duplicate -d
```

Para que arranque con la sesión, en la configuración de Hyprland:

```lua
hl.exec_cmd("quickshell -p /home/TU_USUARIO/.config/quickshell/k4/shell.qml --no-duplicate -d")
```

## Atajos

Los atajos se envían por IPC, así que puedes atarlos a la tecla que quieras:

```lua
local k4 = "quickshell ipc -p /home/TU_USUARIO/.config/quickshell/k4/shell.qml call k4 "

hl.bind("SUPER + Space",       hl.dsp.exec_cmd(k4 .. "toggleLauncher"))
hl.bind("SUPER + I",           hl.dsp.exec_cmd(k4 .. "togglePanel"))
hl.bind("SUPER + N",           hl.dsp.exec_cmd(k4 .. "toggleNotifications"))
hl.bind("SUPER + G",           hl.dsp.exec_cmd(k4 .. "ask"))
hl.bind("SUPER + SHIFT + G",   hl.dsp.exec_cmd(k4 .. "askScreen"))
hl.bind("SUPER + ALT + G",     hl.dsp.exec_cmd(k4 .. "askRegion"))
hl.bind("SUPER + CONTROL + G", hl.dsp.exec_cmd(k4 .. "askSelection"))
```

### Todas las llamadas IPC

| Llamada | Qué hace |
|---|---|
| `toggleLauncher` | buscador de aplicaciones |
| `togglePanel` | centro de control |
| `toggleNotifications` | panel en la pestaña de notificaciones |
| `clearNotifications` | descarta todas las notificaciones |
| `wifi` / `bluetooth` | abre directamente esa lista |
| `ask` | prompt de consulta (alterna) |
| `askScreen` / `askRegion` | consulta adjuntando pantalla completa o región |
| `askSelection` | consulta adjuntando el texto seleccionado |
| `askNow <texto>` | lanza una consulta sin escribirla |
| `install <texto>` | buscador de paquetes con esa búsqueda |
| `search <texto>` | lanzador de apps con esa búsqueda |
| `togglePlay` | play/pausa del reproductor activo |
| `theme` | módulo de tema de Hyprland |
| `weather` | módulo del tiempo |
| `tray` | bandeja del sistema |
| `setMode <modo>` | fuerza un estado de la island (depuración) |

Además, cada módulo publica su propio target. El de arriba se mantiene por
compatibilidad con los atajos ya configurados; en módulos nuevos usa el suyo:

| Target | Llamadas |
|---|---|
| `k4.panel` | `toggle` · `notifications` · `wifi` · `bluetooth` · `close` |
| `k4.launcher` | `toggle` · `search <texto>` · `install <texto>` |
| `k4.ask` | `toggle` · `selection` · `screen` · `region` · `now <texto>` · `followUp <texto>` |
| `k4.theme` | `toggle` · `close` · `tab <pestaña>` · `preset <id>` · `wallpaper <ruta>` · `apply` · `save` |
| `k4.weather` | `toggle` · `close` · `refresh` · `locate` · `place <ciudad>` |
| `k4.tray` | `toggle` · `close` |

## Dentro de la island

Teclas dentro de cada vista:

- **Lanzador**: `Enter` abre, `↑`/`↓` navegan, `Esc` cierra. En modo paquetes,
  `Esc` vuelve a las aplicaciones.
- **Consulta**: `Enter` envía, `Tab` adjunta el texto seleccionado, `Esc` cierra.
- **Contraseña de Wi‑Fi**: `Enter` conecta, `Esc` cancela.

## Estructura

```
shell.qml    host: monta la superficie, dibuja la silueta y decide qué
             plugin se queda la island
core/        Theme (tokens), K4Plugin (el contrato) y widgets sin estado
services/    singletons de dominio: Audio, Media, Wifi, Bt, Notifs, Clock,
             Workspaces, Island
widgets/     widgets que sí leen datos: Artwork, Visualizer
plugins/     un módulo por carpeta
ask.sh       envoltorio de codex exec para las consultas
```

Las capas van en un solo sentido —`core` → `services` → `widgets` →
`plugins`— y ninguna importa hacia atrás. Es lo que evita el ciclo entre
`Artwork`, que necesita datos de media, y `Wifi`, que necesita iconos del
tema.

## Escribir un plugin

Un módulo es una carpeta con un `K4Plugin` que declara cuándo quiere la
island, qué tamaño necesita y qué pinta dentro. Sus procesos, timers e
`IpcHandler` van como hijos suyos y viven mientras viva la barra, esté o no
montada la vista:

```qml
K4Plugin {
    id: self

    name: "ejemplo"
    priority: 60          // quién gana si varios la piden a la vez
    active: open          // ¿la quiere ahora mismo?
    islandWidth: 600
    islandHeight: 300

    property bool open: false

    view: Component { EjemploView { plugin: self } }

    IpcHandler {
        target: "k4.ejemplo"
        function toggle(): void { self.open = !self.open }
    }
}
```

Si el módulo se abre con el ratón, `closeOnHoverExit: true` hace que el host
avise con `hoverTimedOut` cuando el puntero lleva `hoverExitDelay` fuera de la
island. Qué hacer entonces lo decide el plugin: el panel, por ejemplo, se
queda abierto si el lanzador está encima. El temporizador solo se arma al
salir, así que un módulo abierto por atajo sigue abierto hasta que lo toques.

Registrarlo son dos líneas en `shell.qml`: el `import` de su carpeta y una
entrada en la lista `plugins`. Las referencias entre módulos se inyectan ahí
(`PanelPlugin { launcher: launcherPlugin }`), así ninguno importa a otro.

El `id: self` no es capricho: si lo llamas `plugin`, la línea
`EjemploView { plugin: plugin }` se autoasigna —la propiedad del hijo tapa al
`id` del padre— y la vista recibe `undefined`.

Prioridades de los que ya hay: `idle` 0 · `volume` 40 · `clock` 50 ·
`player` 55 · `panel` 60 · `weather` 62 · `tray` 63 · `hyprtheme` 65 ·
`toast` 70 · `launcher` 80 · `ask` 90.

## Tema de Hyprland

El módulo aplica en caliente con `hyprctl eval`, que evalúa Lua en el
Hyprland vivo. `hyprctl keyword` no vale con una configuración en Lua:
responde *keyword can't work with non-legacy parsers*.

Para que sobreviva al reinicio, k4 es dueño de `~/.config/hypr/config/k4-theme.lua`
y añade un `require` al final de `hyprland.lua`. Al cargarse el último, sus
valores ganan sin tocar ninguna otra línea de tu configuración. Para
revertirlo del todo: borra ese archivo y su línea `require`.

Lo aplicado se ve al momento; solo se guarda al pulsar **Guardar**, así que
puedes trastear sin miedo: si no guardas, el próximo reinicio de Hyprland lo
deja como estaba.

## Detalles de implementación

Algunas decisiones que no son evidentes leyendo el código:

- **La ventana no se redimensiona cada frame.** Cambiar el tamaño de una
  *layer surface* obliga a un ciclo `configure`/`ack` con el compositor; hacerlo
  60 veces por segundo produce parpadeos. La superficie crece una vez al empezar
  a expandirse y encoge una vez al terminar; entre medias solo se anima la
  island dentro de ella.
- **El contenido se mide al tamaño final,** no al animado, así que los layouts
  no se recalculan en cada frame: la island simplemente los va destapando.
- **La silueta lleva MSAA por capa.** `Shape.CurveRenderer` suaviza mejor, pero
  descarta las esquinas invertidas que unen la island con el borde de la
  pantalla, así que se usa el renderer de geometría con `layer.samples: 8`.
- **La zona exclusiva es fija** (el alto de la píldora): las ventanas nunca se
  meten debajo, y todo lo que crece por encima flota sin re‑acomodar nada.
- **`codex exec` recibe el prompt por stdin.** Bloquea esperando EOF cuando
  stdin no es una tty, y `--image` es multi‑valor y se tragaría un prompt
  posicional como si fuera otra imagen.

## Licencia

MIT. Ver [LICENSE](LICENSE).
