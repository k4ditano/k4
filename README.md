# k4

Lo que queda por hacer está en [PENDIENTE.md](PENDIENTE.md).

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
island, se acumulan en una pestaña del panel y las recientes salen también al
pasar el ratón por la island, bajo el reloj o bajo el reproductor, para llegar
a ellas sin abrir nada.

Pulsar el cuerpo lleva a la aplicación: su acción por defecto si la manda y,
si no, enfocando su ventana. Si no se puede hacer ninguna de las dos, la
notificación **se queda donde está** en vez de desaparecer sin llevarte a
ningún sitio. Los botones que ofrezca la aplicación se pintan en el toast y en
la tarjeta.

Las herramientas de terminal no traen identidad que casar con una ventana, así
que se resuelven con un mapa de alias en `services/Notifs.qml`: `claude code` y
`codex` van a `kitty`. Para añadir la tuya, mira el nombre que sale en la
tarjeta del panel, encima del título.

**Lanzador.** `SUPER+Space` abre un buscador de aplicaciones estilo Spotlight.
Escribiendo aparece además la opción **Instalar**, que busca paquetes en los
repos oficiales (`pacman`, instantáneo) y en AUR (`yay`, con retardo para no
abusar del RPC) y los instala en una terminal.

**Consultas a Codex.** `SUPER+G` abre un prompt en la island que habla con
[Codex CLI](https://developers.openai.com/codex/cli) usando tu cuenta de
ChatGPT. Conversación multi‑turno, y puedes adjuntar una captura de pantalla o
el texto que tengas seleccionado. Las respuestas se pintan con formato
—negrita, cursiva, código y enlaces pulsables, que abren el navegador— y las
imágenes, tanto las que adjuntas como las que devuelva, salen como miniatura
con vista ampliada, guardado en Imágenes y apertura fuera. Cada vez que se abre arranca una sesión nueva
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

**Mazmorra.** Un roguelite por oleadas dentro de la island, siguiendo a
[TBH: Task Bar Hero](https://store.steampowered.com/app/3678970/). Un grupo de
tres héroes —guardián, hechicero y clériga— pelea **solo** contra oleadas cada
vez más duras: tú decides el equipo, en qué gastas el oro y cuándo lanzar las
habilidades, no los golpes. El guardián acapara los ataques, la clériga cura de
fondo y el hechicero revienta la oleada entera.

Cada diez oleadas llega un jefe. Cuando cae el grupo se acaba la partida: se
pierden el oro y el progreso de esa partida, y **se conservan el equipo, los
cofres y las reliquias**. Tras el resumen arranca sola la siguiente, salvo que
lo apagues en Ajustes. Hay botón de pausa para dejar de pelear mientras miras
la bolsa.

Los héroes **suben de nivel matando**, no comprando: cada nivel mejora lo suyo
—el guardián gana aguante, el hechicero pega más— y en ciertos niveles
aprenden habilidades nuevas. El guardián empieza provocando y acaba poniendo
muros de escudos, devolviendo daño y volviéndose intocable; el hechicero pasa
de la llamarada a cadenas que crecen con cada salto, meteoros y detener a la
oleada entera; la clériga suma escudos, regeneración y levantar a un caído.
Todas se lanzan solas al recargarse, o las lanzas tú antes.

El oro ya no compra estadísticas —subirlas a mano no era una decisión, era un
peaje— sino **cofres**, que es elegir qué botín te llevas.

**Ocho héroes**, tres en el campo. Empiezas con guardián, hechicero y clériga;
los otros cinco se desbloquean con retos —llegar a cierta oleada, tumbar
jefes, abrir cofres, subir de nivel—. La plantilla se cambia cuando quieras,
aunque hacerlo reinicia la partida en curso.

**28 logros** en familias escalonadas —cazador I a V, explorador I a V…— con
metas que van de cien monstruos a cien mil. Cada uno da reliquias, y los
altos, cofres.

Seis pestañas: **Lucha** (la pelea y la tienda de la partida), **Grupo**
(cuatro huecos de equipo por héroe), **Plantilla** (quién sale al campo y qué
falta para desbloquear al resto), **Logros**, **Bolsa** (abrir cofres, equipar con clic
izquierdo, desguazar con el derecho) y **Altar** (mejoras permanentes por
reliquias).

El escenario cambia cada 80 oleadas —bosque, cueva, infierno y vacío— y con
él la fauna: los monstruos no son hojas distintas por bioma, sino un reparto
por afinidad de la que ya hay. El fondo va en parallax de dos capas, el
paisaje despacio y el suelo deprisa, y entre oleada y oleada el grupo camina
un par de segundos mientras la siguiente entra por la derecha.

Los objetos se generan por afijos —tipo, prefijo declinado y sufijo— con las
**diez rarezas de TBH** y sus colores, de Común a Cósmico. Cada pieza lleva
además **nivel**, que escala lo que da y marca el nivel de héroe necesario
para ponérsela: la rareza dice de qué familia es y el nivel cuánto rinde, así
que un común alto puede valer más que un legendario recogido pronto. Van
también y tres clases de
cofre: corriente cada cinco oleadas, de jefe cada diez y de acto cada cincuenta.
Con la barra cerrada siguen cayendo cofres corrientes, uno cada cuarto de hora
y con tope de ocho horas.

En la píldora queda un indicador con la oleada y un punto morado cuando hay
cofres sin abrir; al pasar el ratón —tanto en el reloj como en el reproductor—
se puede pulsar para abrir la mazmorra. Ver
[Los sprites](#los-sprites) para cómo se generaron.

**Ajustes.** Interruptores de la barra dentro de la island: si la mazmorra
encadena partidas sola, si sale en la píldora, si la bandeja muestra iconos
ahí y si las notificaciones recientes aparecen al pasar el ratón. Antes esa
tarjeta del centro de control lanzaba directamente `nm-connection-editor`, una
ventana del sistema con su propio marco y su propia tipografía que no tenía
nada que ver con la barra; ahora esa herramienta y `pavucontrol` quedan como
accesos dentro del módulo.

Solo hay interruptores conectados a algo: cada opción declara en
`services/Settings.qml` qué módulo la lee, para que no queden huérfanas al
refactorizar.

**El tiempo.** Estado actual, siguientes horas y seis días, con datos de
[Open-Meteo](https://open-meteo.com) —sin clave ni cuenta—. La ubicación se
adivina por IP la primera vez, que es aproximada, así que el buscador de
ciudades manda: lo que elijas se guarda y es lo que se usa a partir de
entonces. En el centro de control la tarjeta enseña ya la temperatura.

## Instalación

```sh
curl -fsSL https://raw.githubusercontent.com/k4ditano/k4/main/instalar | sh
```

Eso clona k4 en `~/.config/quickshell/k4` y a partir de ahí hace todo lo demás:
mira qué te falta, te enseña el mandato de `pacman` **antes** de lanzarlo, deja
los atajos puestos y arranca la barra.

Para actualizar, el mismo mandato desde el repositorio:

```sh
~/.config/quickshell/k4/instalar
```

Si prefieres ver qué haría sin que toque nada:

```sh
~/.config/quickshell/k4/instalar --seco
```

| Opción | Qué hace |
|---|---|
| `--seco` | solo diagnostica; no escribe nada |
| `--si` | no pregunta (para guiones) |
| `--opcionales` | instala también lo opcional |
| `--sin-paquetes` | salta el gestor de paquetes |
| `--sin-reiniciar` | no toca la barra que esté corriendo |

### Qué toca de tu sistema

Poco, y se puede deshacer a mano:

- **Escribe `~/.config/hypr/config/k4.lua`** (o `~/.config/hypr/k4.conf` si usas
  la configuración clásica) con los atajos y el arranque. Ese fichero es de k4 y
  se reescribe en cada actualización.
- **Añade una línea** —`require("config.k4")` o `source = …`— a tu `hyprland.lua`
  o `hyprland.conf`. Una sola, y solo si no estaba.
- **No edita ningún otro fichero tuyo.** Si encuentra atajos de k4 que pusiste a
  mano, te los enumera con fichero y línea para que los quites tú.

Para revertirlo: borra ese fichero y esa línea.

### Arrancar a mano

```sh
~/.config/quickshell/k4/arrancar
```

Y no `quickshell -p …/shell.qml`: `arrancar` es quien pone `QML_IMPORT_PATH`
apuntando a `api/`, sin lo cual los plugins no pueden hacer `import K4` y la
barra no levanta.

## Requisitos

La lista de verdad está en [`dependencias.tsv`](dependencias.tsv), que es lo que
lee el instalador. En Arch está todo en los repositorios oficiales; no hace falta
ningún ayudante de AUR.

| Necesario | Para |
|---|---|
| `quickshell` | El motor sobre el que corre la barra |
| `hyprland` | Compositor: atajos, ventanas, espacios y tema |
| `git` | Instalar y actualizar k4 |
| `python` | Todas las herramientas de `tools/` |
| `qt6-multimedia` · `qt6-multimedia-ffmpeg` | Reproducir vídeo y audio en el editor |
| `ttf-meslo-nerd` | Los iconos de la interfaz (sin esto, cuadrados) |
| `adwaita-fonts` | Texto de la interfaz y rótulos del editor |
| `grim` · `slurp` | Capturas y selección de región |
| `satty` | Anotar una captura antes de guardarla |
| `wf-recorder` | Grabar la pantalla en vídeo |
| `ffmpeg` | Montar y renderizar en el editor |
| `imagemagick` | Miniaturas y capas de imagen |
| `zenity` | El diálogo «Examinar…» para abrir un vídeo |
| `wl-clipboard` | Portapapeles e historial |
| `fd` | Buscar ficheros en el lanzador y en el editor |
| `libpulse` · `wireplumber` | Volumen y dispositivos de audio |
| `networkmanager` · `bluez` | Red y Bluetooth |
| `libnotify` | Enviar notificaciones |
| `xdg-utils` · `xdg-user-dirs` · `desktop-file-utils` | Abrir ficheros, carpetas del usuario, índice del lanzador |
| `curl` | El tiempo y las consultas al asistente |

| Opcional | Para |
|---|---|
| `whisper-cpp` | Transcribir el audio de un vídeo en el editor |
| `kitty` | Terminal donde instalar paquetes desde el lanzador |
| `uwsm` | Lanzar aplicaciones en su propio ámbito de systemd |
| `yay` | Buscar e instalar paquetes de AUR desde el lanzador |
| `swaybg` (o `awww`, `swww`) | Fondo de pantalla; con `swaybg`, sin transiciones |
| `nvidia-utils` | Temperatura y uso de la GPU NVIDIA |
| `codex` | El asistente, autenticado con tu cuenta de ChatGPT |

Lo opcional no se instala salvo que se pida con `--opcionales`. Sin ello, esa
parte concreta no aparece o no hace nada; la barra funciona igual.

## Atajos

Los pone el instalador en `hypr/k4.lua` o `hypr/k4.conf`. Ahí están todos, con
comentarios; esto es un resumen.

| Tecla | Qué hace |
|---|---|
| `SUPER + Space` | lanzador de aplicaciones |
| `SUPER + I` · `SUPER + X` | centro de control |
| `SUPER + N` · `SUPER + A` | notificaciones |
| `SUPER + Z` | ajustes de la barra |
| `SUPER + Tab` | ventanas |
| `SUPER + V` | portapapeles |
| `SUPER + B` | ficheros |
| `SUPER + K` | atajos de teclado |
| `SUPER + L` · `SUPER + ALT + C` | bloquear · sesión |
| `SUPER + SHIFT + W` | tema de Hyprland |
| `SUPER + G` | consulta al asistente |
| `SUPER + SHIFT/ALT/CONTROL + G` | consulta con pantalla · región · selección |
| `Print` · `SUPER + C` | capturar una región |
| `SHIFT + Print` · `CONTROL + Print` | pantalla completa · ventana |
| `SUPER + Print` | menú de captura |
| `SUPER + CONTROL + C` | capturar y anotar |
| `SUPER + SHIFT + C` | empezar o parar la grabación |
| `SUPER + SHIFT + E` | abrir un vídeo en el editor |
| `SUPER + ALT + E` | retomar la última edición |

Todo va por IPC, así que puedes atarlo a la tecla que quieras:

```lua
local k4 = "quickshell ipc -p /home/TU_USUARIO/.config/quickshell/k4/shell.qml call k4 "

hl.bind("SUPER + Space",       hl.dsp.exec_cmd(k4 .. "toggleLauncher"))
hl.bind("SUPER + I",           hl.dsp.exec_cmd(k4 .. "togglePanel"))
hl.bind("SUPER + G",           hl.dsp.exec_cmd(k4 .. "ask"))
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
| `nextTrack` / `prevTrack` | siguiente / anterior |
| `windows` | cambiador de ventanas |
| `lock` | bloquear la pantalla |
| `session` | menú de sesión (apagar, reiniciar, salir) |
| `theme` | módulo de tema de Hyprland |
| `weather` | módulo del tiempo |
| `tray` | bandeja del sistema |
| `game` | la mazmorra |
| `settings` | ajustes de la barra |
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
| `k4.settings` | `toggle` · `close` · `alternar <opción>` |
| `k4.game` | `toggle` · `close` · `nueva` · `habilidad <0-2>` · `ver <pestaña>` · `cofre <tipo>` · `adelantar <segundos>` · `estado` |
| `k4.captura` | `menu` · `close` · `pantalla` · `region` · `ventana` · `anotar` · `grabar` · `grabarRegion` · `grabarAlternar` · `parar` · `grande` · `encoger` |
| `k4.editor` | `abrir` · `editar <ruta>` · `retomar` · `imagen <ruta> <t>` · `imagenEncima <ruta> <t>` · `congelar <t> <dur>` · `subtitular` · `formato <mp4|webm|gif>` · `silencios` · `quitarSilencios` · `olvidarSilencios` · `grande` · `encoger` |

El editor tiene canal propio y no cuelga de `k4.captura` a propósito: llegar a
él ya no pasa por haber grabado nada.

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
`player` 55 · `panel` 60 · `weather` 62 · `tray` 63 · `game` 64 ·
`hyprtheme` 65 · `settings` 66 · `toast` 70 · `launcher` 80 · `ask` 90.

## Tema de Hyprland

El módulo aplica en caliente con `hyprctl eval`, que evalúa Lua en el
Hyprland vivo. `hyprctl keyword` no vale con una configuración en Lua:
responde *keyword can't work with non-legacy parsers*.

La misma regla vale para cualquier otra orden: enfocar la ventana de una
aplicación al pulsar su notificación se envía como
`hl.dsp.focus({ window = "address:0x…" })`, no como el `focuswindow` de
siempre, que con este parser ni siquiera compila.

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

## Los sprites

Los 60 sprites de la mazmorra —monstruos, jefes y héroes— se generaron con
`imagegen`, que viene dentro de Codex, pidiendo hojas de 20 en rejilla de 4×5
sobre fondo magenta plano. No hace falta instalar nada: basta `codex exec` con
el mismo patrón que usa `ask.sh`.

`tools/spritesheet.py` corta la hoja en PNG sueltos. Tres cosas que hicieron
falta y no son evidentes:

- **El fondo se quita por inundación desde los bordes**, no buscando el color
  magenta por toda la imagen. Filtrando por color, una oruga morada pierde el
  cuerpo, porque su tono cae dentro de lo que se considera fondo.
- **Los huecos encerrados se barren aparte**, con tolerancia estrecha: el fondo
  que queda entre las alas de un dragón no se alcanza desde fuera.
- **Se cuantiza la paleta a 24 colores** tras escalar. Lo que devuelve el
  generador es un render suave de ~280 px, no pixel art; sin cuantizar se ve
  emborronado al tamaño al que se juega.

Para generar más:

```sh
python3 tools/spritesheet.py hoja.png plugins/Game/assets/monstruos --lado 48 --prefijo m
```

## Idiomas

La barra está escrita en español y se traduce a lo que pida el sistema. Si tu
`LANG` es `en_US.UTF-8`, arranca en inglés sin tocar nada.

**La clave de cada texto es el propio texto en español.** No hay identificadores
inventados, y eso da tres cosas: lo que no esté traducido sale en español en vez
de salir roto, se puede traducir un trozo sin romper el resto, y quien traduce
lee frases con sentido en lugar de etiquetas como `ui.btn.42`.

### Añadir un idioma

1. Copia `traducciones/plantilla.json` a `traducciones/<código>.json` —`fr`,
   `de`, `pt_BR`…
2. Rellena los valores. Lo que dejes vacío sale en español, así que se puede
   mandar a medias sin problema.
3. Añade tu idioma a `disponibles` en `services/Idioma.qml`, dos líneas.
4. Manda el fichero por GitHub.

```json
{
 "_meta": { "idioma": "Français", "codigo": "fr", "traducido por": "tu nombre" },
 "Oleada ": "Vague ",
 "Ajustes": "Paramètres",
 "El grupo espera": ""
}
```

### La herramienta

```sh
python3 tools/textos.py plantilla   # rehace la plantilla con lo que hay ahora
python3 tools/textos.py estado      # cuánto lleva cada idioma
python3 tools/textos.py envolver    # prepara las cadenas nuevas del código
```

`envolver` recorre el QML y envuelve en `Idioma.t(...)` los textos que aún estén
sueltos. Reconoce los que viven dentro de ternarios y concatenaciones, que son
la mitad: mirando solo `text: "literal"` se escapaban 359 de 552.

No traduce todo lo que encuentra: `id`, `command`, `source` y compañía llevan
cadenas que son identificadores. `etiqueta` también queda fuera aunque se vea,
porque el portapapeles la compara contra `"enlace"`, `"color"`… para elegir el
icono.
