# Pendiente

Lo que queda por hacer en k4, con lo que hace falta saber para retomarlo sin
tener que reconstruir el contexto. Ordenado por lo que más cambia el proyecto,
no por lo que menos cuesta.

---

## Grande

### ~~Daño y defensa, físico y mágico~~ · HECHO

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

### ~~Megajefe al cambiar de bioma~~ · HECHO

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

Quedan **tres atajos llamando a `noctalia`**, la barra anterior. Los diez que
podían migrarse ya lo hicieron: el cambiador de ventanas y la sesión tienen
módulo propio.

Los que quedan necesitan módulo nuevo o no aplican:

- **Selector de emoji** (`SUPER+.`) — pequeño, y se lleva bien con el módulo de
  portapapeles que ya existe.
- **Brillo** (teclas `XF86MonBrightness*`) — es un sobremesa sin
  retroiluminación, así que solo tendría sentido por DDC contra el monitor.

### Cuidado con el bloqueo de sesión

`ext-session-lock` no perdona. Si el cliente que tiene puesto el bloqueo muere
sin soltarlo, el compositor se queda con un bloqueo huérfano y **toda petición
de bloquear posterior es un error de protocolo que mata la conexión Wayland del
cliente nuevo**, o sea la barra entera. No hay forma de arreglarlo sin cerrar
sesión, y está comprobado en un Hyprland anidado: cliente que bloquea → se le
mata → el siguiente muere al intentarlo.

De ahí dos reglas que el código ya respeta y conviene no romper:

- Al arrancar **nunca se escribe** en `locked`, solo se lee. Quien manda es el
  compositor. Quickshell recarga solo en cuanto tocas un fichero, así que la
  otra dirección —«el servicio dice que no estás bloqueado, suéltalo»— deja el
  bloqueo a medias y rompe la sesión.
- `unlock()` sale en la documentación pero **no está expuesto a QML**. Se abre
  y se cierra escribiendo `locked`.

Y por eso existe **«Probar contraseña»** en el menú: ensaya el mismo PAM que
usa el bloqueo sin bloquear nada. Conviene pasar por ahí antes de fiarle la
sesión a `SUPER+L`.

---

## Traducciones

**77 de 520 cadenas** en inglés, o sea el 15%: está hecha la interfaz y falta el
grueso, que son los nombres de objetos, habilidades, clases y logros del juego.
Es trabajo de rellenar `traducciones/en.json`, sin tocar código.

Dos huecos del sistema, aparte del contenido:

- **Los guiones de Python no pasan por el traductor.** Las etiquetas del
  portapapeles —«enlace», «color», «orden», «ruta», «código»— salen de
  `tools/portapapeles.py`, y encima se comparan como claves en el QML para
  elegir el icono. Habría que separar la clave del texto antes de traducirlas.

---

## API de plugins

Hecho el grueso: existe el módulo `K4` en `api/`, los 24 ficheros de `plugins/`
están migrados y `tools/api.py` comprueba que nadie se la salta. La guía está en
`api/LEEME.md`.

Lo que queda, por orden de lo que más cambia la experiencia:

- **`K4.Pildora`.** Hoy el indicador del juego y el de grabación se inyectan a
  mano en las vistas del reloj y del reproductor. Un plugin de fuera no puede
  hacer eso, y es justo lo que hace que se sienta vivo sin estar abierto.
- **`K4.Widgets`.** Publicar `IslandTile`, `IslandSlider`, `IconGlyph` y
  compañía, que ya existen en `core/` y son puros. Sin esto cada plugin de la
  comunidad traerá su propia estética.
- **Ajustes de plugin**: que un plugin declare sus opciones y salgan en el
  módulo de Ajustes.
- **Permisos**: hoy cualquier plugin puede lanzar cualquier proceso. Decidirlo
  antes de que exista un directorio público, porque después no se puede
  retrofitear.
- **Descubrimiento dinámico** desde `~/.config/k4/plugins/`, con recarga en
  caliente en modo desarrollo. Ojo: los plugins de fuera del árbol no llegan a
  los imports relativos (`"../../core"`), así que eso hay que resolverlo antes.

## Deudas pequeñas

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
aquí, porque necesita ratón de verdad.

Para el teclado ya hay salida: **`tools/teclas.py`** monta un teclado virtual
por uinput. El compositor no acepta pulsaciones sintéticas por Wayland, pero un
dispositivo del kernel lo ve como cualquier teclado enchufado.

    python3 tools/teclas.py escribe hola
    python3 tools/teclas.py pulsa ESC ENTER TAB

Queda por comprobar, y necesita ratón:

- La ficha flotante al pasar el ratón por encima de un objeto.
- Clic derecho sobre los iconos de la bandeja.
- Pulsar un héroe en el campo de batalla para ir a su ficha.
- **Que PAM acepte la contraseña correcta.** Solo se ha probado con una
  incorrecta —responde `Failed` limpio, o sea que la conversación funciona—,
  porque probar con la buena exige escribirla. El montón de reglas es
  `/etc/pam.d/login`, y `pam_shells` pasa porque `/bin/fish` está en
  `/etc/shells`. Se comprueba desde «Probar contraseña».
- Ojo con `pam_faillock`: **tres fallos seguidos bloquean la cuenta diez
  minutos**, y el aviso de PAM se enseña tal cual en la pantalla de bloqueo.
