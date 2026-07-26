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
| `setMode <modo>` | fuerza un estado de la island (depuración) |

## Dentro de la island

Teclas dentro de cada vista:

- **Lanzador**: `Enter` abre, `↑`/`↓` navegan, `Esc` cierra. En modo paquetes,
  `Esc` vuelve a las aplicaciones.
- **Consulta**: `Enter` envía, `Tab` adjunta el texto seleccionado, `Esc` cierra.
- **Contraseña de Wi‑Fi**: `Enter` conecta, `Esc` cancela.

## Estructura

```
shell.qml   toda la barra: estados, servicios y vistas
ask.sh      envoltorio de codex exec para las consultas
```

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
