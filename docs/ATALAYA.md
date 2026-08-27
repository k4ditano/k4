# Atalaya

Todas tus ventanas sobre un mismo plano. El escritorio se aleja, las ventanas
se despegan de donde estaban, y te mueves por ellas con la rueda y el ratón
hasta caer sobre la que quieras.

Siguen **vivas** ahí dentro: un vídeo se sigue reproduciendo dentro de su
miniatura y un compilado sigue escupiendo líneas. Media razón para abrir esto
es mirar si algo ha terminado ya.

## Qué lo separa de un Alt+Tab

Que no hay que recordar nada. Lo que falla de una lista de ventanas no es la
lista: es que hay que llevar la cuenta del orden para usarla. Aquí se mira. Y
lo que se mira es la ventana, no su título — tres terminales se llaman igual y
no se parecen en nada.

Salen también las que están en otro escritorio o tapadas del todo: cada ventana
se copia por separado (`hyprland-toplevel-export`), así que esto es un mapa y
no un recorte de lo que ya se veía.

## Cómo se usa

| | |
|---|---|
| rueda | acercarse y alejarse, sobre el punto que señalas |
| arrastrar | mover el plano |
| clic en una ventana | ir a ella |
| clic en el vacío | salir |
| escribir | filtrar por título o aplicación |
| flechas | moverse por la rejilla |
| ↵ | ir a la elegida |
| Tab / ⇧Tab | siguiente / anterior |
| + · − | acercarse y alejarse desde el centro |
| Inicio | volver a encuadrar todo |
| Esc | salir |

Si te pierdes acercándote, **Inicio** vuelve a encuadrarlo todo.

## El atajo

**SUPER+Tab**, que lo instala `./instalar` desde `hypr/k4.lua` (o `hypr/k4.conf`
con la configuración clásica). Ahí releva al selector `windows`, que sigue
instalado y se abre desde el centro de aplicaciones.

Se declara como un `K4.Atajo` con el nombre `atalaya`, y se ata por `global` y
no por `exec_cmd`: el compositor se lo entrega a la barra sin lanzar un proceso
en cada pulsación.

```lua
hl.bind(mod .. " + Tab", hl.dsp.global("k4:atalaya"))
```

### Y una trampa de Hyprland

Ir a una ventana se pide de dos maneras distintas según cómo esté configurado
el compositor. Con la configuración de siempre es
`hyprctl dispatch focuswindow address:0x…`; con la de **Lua**, `hyprctl
dispatch` no recibe un dispatcher y sus argumentos sino una expresión que
evalúa, así que esa orden se queda en un error de sintaxis y no enfoca nada —y
puede salir con código cero mientras falla—. El plugin prueba la clásica, mira
la RESPUESTA (no el código), y si no dice `ok` repite con
`hl.dsp.focus({ window = "address:0x…" })`.

## Por dentro

```
AtalayaPlugin.qml   el estado, hyprctl, el atajo y el IPC
Lienzo.qml          la ventana a pantalla completa: cámara, capas y teclado
Tarjeta.qml         una ventana sobre el plano
lente.js            el reparto en rejilla
trama.frag(.qsb)    el suelo: rejilla, halo del puntero, onda de apertura
lente.frag(.qsb)    la lente: curvatura, aberración cromática y viñeta
```

Tres capas, y el orden es la arquitectura entera:

1. **La trama** — el suelo. Un fondo que se mueve y se agranda con la cámara.
   Es lo que convierte esto en un canvas y no en un fondo negro con cosas
   encima: un campo de puntos dice cuánto te has movido, y las líneas de la
   rejilla grande dicen hacia dónde. Va en dos planos a distinta velocidad, y
   ese desajuste es la profundidad.
2. **El plano** — las tarjetas, dibujadas planas y sin doblar.
3. **La lente** — coge lo anterior *ya pintado* y lo dobla de una vez.

**Que la lente sea un paso aparte es la decisión de la que cuelga el resto.**
La primera versión inclinaba cada tarjeta por su cuenta para fingir la
curvatura, y se veía lo que era: rectángulos girados. Un ojo de pez no gira
cosas, dobla la imagen — así que hay que tener imagen primero. A cambio, la
curvatura es continua (una ventana ancha se arquea por el medio en vez de
inclinarse entera) y salen gratis las dos cosas que delatan que hay un cristal
delante y que por tarjetas eran imposibles: que los colores se separen en los
bordes y que la luz caiga hacia las esquinas.

El precio es un paso de dibujado a pantalla completa —lo que cuesta cualquier
post-proceso— y una regla que no se puede romper: **el ratón está sobre la
imagen doblada**, así que antes de buscar qué hay debajo hay que deshacer el
doblez. Esa cuenta (`aLienzo()`) es la misma que hace el shader, y tiene que
seguir siéndolo.

**Una sola propiedad manda en la entrada.** `apertura` va de 0 a 1 e interpola
cada tarjeta entre donde está su ventana de verdad ahora mismo y donde le toca
en el plano. Por eso al abrir no hay salto: las miniaturas arrancan tapando
exactamente a sus ventanas. Cada tarjeta arranca con un retardo proporcional a
su distancia al centro, que es también el orden en que el ojo las va a leer.

**Y la luz sale del centro de la pantalla.** Por eso la sombra de cada tarjeta
se aleja del centro y el canto que mira hacia dentro está más iluminado que el
de fuera. Nadie lo nombra al verlo; el ojo lo comprueba igual.

### Tocar los shaders

Son GLSL y hay que compilarlos antes de que Qt los pueda usar:

```sh
/usr/lib/qt6/bin/qsb --qt6 -o trama.frag.qsb trama.frag
/usr/lib/qt6/bin/qsb --qt6 -o lente.frag.qsb lente.frag
```

Se cargan por ruta de fichero (`"file://" + plugin.fichero(...)`) y no con
`Qt.resolvedUrl`, que devuelve una URL del esquema interno de Quickshell.

## Lo que cuesta

Una miniatura viva es una copia por cuadro de una ventana entera. Las que se
salen del encuadre o se quedan diminutas apagan la copia y conservan su último
cuadro: quietas, pero ahí. Todas nacen vivas medio segundo para tener ese
cuadro.

## IPC

```sh
qs=~/.config/quickshell/k4/shell.qml
quickshell ipc -p $qs call k4.atalaya alternar
quickshell ipc -p $qs call k4.atalaya estado
```

`cerrar` funciona aunque la ventana tenga el teclado en exclusiva, que es la
salida de emergencia si algo va mal. Y hay un guardián: a los 90 segundos sin
tocarla, se cierra sola.
