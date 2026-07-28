# Pendiente

Lo que queda por hacer en k4, con lo que hace falta saber para retomarlo sin
tener que reconstruir el contexto. Ordenado por lo que más cambia el proyecto,
no por lo que menos cuesta.

---

## Grande

### Daño y defensa, físico y mágico

Ahora mismo hay un solo `daño` y una sola `armadura`. Separarlos en físico y
mágico da profundidad de verdad: el tanque aguanta espadas pero no hechizos, el
mago pega magia pero cae ante un bárbaro, y un objeto deja de ser «mejor» o
«peor» para ser «mejor contra esto».

Toca en cuatro sitios:

- `services/Game.qml` — `statsDe()` devuelve `daño` y `armadura`; pasan a cuatro
  campos. Las ocho más doce clases necesitan repartir sus curvas `porNivel`.
- El combate (`tic`) aplica una única reducción: `100 / (100 + armadura * 4)`.
  Hay que elegir la defensa según de qué tipo sea el golpe, y cada habilidad
  declarar el suyo en su `efecto`.
- `services/Items.qml` — el `reparte` de cada hueco se dobla. Con dos tipos de
  daño y dos de defensa hay sitio para bastantes más afijos.
- Las fichas de héroe y de objeto tienen que enseñarlo sin volverse una tabla.

Los enemigos también deberían pegar de un tipo u otro, y ahí engancha con los
rasgos: un espectro que pega mágico contra un grupo con toda la armadura física
es una oleada que se juega distinto.

### Megajefe al cambiar de bioma

Cada 80 oleadas cambia el bioma y la temática de los sprites. Ese salto no está
marcado con nada: es una oleada más. Debería ser un megajefe con mecánicas
propias —fases, invocaciones, un ataque que obligue a moverse— con su sprite
generado, sus habilidades y sus VFX.

El camino de los assets ya está montado y documentado en el README: `codex
imagegen` para una hoja y `tools/spritesheet.py` para cortarla. Los jefes
actuales son de 48×48; un megajefe pide más, 96 o 128.

Conviene hacerlo en la misma tanda de generación que cualquier otro arte que
haga falta, para no pagar dos veces el ir y venir.

---

## Módulos que faltan

Quedan **14 atajos llamando a `noctalia`**, la barra anterior. Seis podrían
apuntar a k4 hoy mismo, sin escribir código:

| Atajo | Ahora | Podría ser |
|---|---|---|
| `SUPER+X` | noctalia control-center | `k4 togglePanel` |
| `SUPER+Z` | noctalia settings | `k4 settings` |
| `SUPER+A` | noctalia notificaciones | `k4 toggleNotifications` |
| `SUPER+SHIFT+W` | noctalia wallpaper | `k4 theme` |
| Play/Next/Prev | noctalia media | `k4 togglePlay` |

Los otros ocho sí necesitan módulo nuevo:

- **Cambiador de ventanas** (`SUPER+Tab`) — es lo más usado que aún posee
  noctalia. Quickshell expone `ToplevelManagement`, así que sale nativo.
- **Sesión y bloqueo** (`SUPER+L`, `SUPER+ALT+C`) — `WlSessionLock` permite una
  pantalla de bloqueo de verdad, no un apaño.
- **Selector de emoji** (`SUPER+.`) — pequeño, y se lleva bien con el módulo de
  portapapeles que ya existe.
- **Brillo** (teclas `XF86MonBrightness*`) — es un sobremesa sin
  retroiluminación, así que solo tendría sentido por DDC contra el monitor.

---

## Traducciones

**77 de 520 cadenas** en inglés, o sea el 15%: está hecha la interfaz y falta el
grueso, que son los nombres de objetos, habilidades, clases y logros del juego.
Es trabajo de rellenar `traducciones/en.json`, sin tocar código.

Dos huecos del sistema, aparte del contenido:

- **`core/` no se traduce.** Dos cadenas, «Conectar» y «Desconectar». El
  envoltorio automático les tocaba los imports y las rompió una vez, así que se
  quedó fuera de su alcance; hay que hacerlo a mano.
- **Los guiones de Python no pasan por el traductor.** Las etiquetas del
  portapapeles —«enlace», «color», «orden», «ruta», «código»— salen de
  `tools/portapapeles.py`, y encima se comparan como claves en el QML para
  elegir el icono. Habría que separar la clave del texto antes de traducirlas.

---

## Deudas pequeñas

- **Aviso de QML al arrancar**: `widgets/JuegoPildora.qml:54` usa `anchors`
  dentro de un layout. Funciona, pero Qt lo llama comportamiento indefinido y lo
  avisa dos veces en cada arranque.
- **Las doce clases nuevas están sin medir.** El banco (`tools/banco-balance.qml`)
  solo prueba la plantilla de salida —tanque, mago, clérigo—, así que de
  nigromante, licántropo o caballero negro no sabemos si están equilibrados.
  Haría falta que el banco recorra plantillas.
- **Los iconos de objeto son de 32×32**, la mitad que héroes y monstruos. Ahora
  se dibujan a tamaño nativo y se ven nítidos, así que no corre prisa, pero
  regenerarlos a 48 daría más detalle sin cambiar nada del código.
- **Selector de idioma y de plantilla comparten patrón** (`tipo: "eleccion"` en
  `Settings.definicion`). Si aparece un tercer ajuste de varias respuestas,
  merece la pena sacarlo a un componente.

---

## Sin verificar

Nada de esto está roto que se sepa; simplemente no se ha podido comprobar desde
aquí, porque necesita ratón o teclado de verdad y el compositor no acepta
pulsaciones sintéticas:

- Arrastrar objetos en la rejilla del inventario para reordenarlos.
- La ficha flotante al pasar el ratón por encima de un objeto.
- Clic derecho sobre los iconos de la bandeja.
- Que **ESC** cierre cada módulo, y que en los de foco bajo demanda llegue tras
  interactuar con ellos.
- Pulsar un héroe en el campo de batalla para ir a su ficha.
