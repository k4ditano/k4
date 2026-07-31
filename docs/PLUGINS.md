# Crear un plugin

k4 carga plugins de dos sitios: los del repositorio (`plugins/`) y los del
usuario en **`~/.config/k4/plugins/<id>/`**. Esta guía es para los segundos:
no hace falta tocar el repositorio para escribir uno.

El ejemplo completo de esta guía está en `ejemplos/hola/` y se puede copiar
tal cual:

```sh
cp -r ejemplos/hola ~/.config/k4/plugins/
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4 pluginEnable hola
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.hola toggle
```

## 0 · Instalar uno que ya existe

Si alguien publicó un plugin en un repositorio:

```sh
python3 tools/plugins.py --instalar https://github.com/quien/su-plugin
```

Clona a un temporal, lo valida entero ahí, y **solo entonces** enseña qué
dice ser y qué permisos declara, y pregunta. Nada llega a tu directorio de
plugins sin haber pasado el mismo examen que pasan los ya instalados: no
existe el «medio instalado y roto». Si el QML usa algo que el manifiesto no
declara, se rechaza antes de tocar el disco.

Llega **apagado**. Encenderlo es otra decisión y se toma en Ajustes, viendo
esos mismos permisos.

```sh
python3 tools/plugins.py --instalados        # qué tienes y de dónde vino
python3 tools/plugins.py --actualizar snake  # reinstala desde su origen
python3 tools/plugins.py --quitar snake      # desinstala (--con-estado borra
                                             # también lo que guardó)
```

Con la barra en marcha, `k4 pluginRefresh` le hace releer el catálogo: lo
recién instalado aparece y lo quitado desaparece sin reiniciar nada. Y tras
actualizar uno encendido, `k4 pluginReload <id>` cambia el código que corre
—en la barra sigue vivo el de antes hasta que se lo digas.

## 1 · La carpeta y el manifiesto

```text
~/.config/k4/plugins/hola/
├── plugin.json
├── HolaPlugin.qml
└── HolaView.qml
```

`plugin.json` es el manifiesto:

```json
{
  "id": "hola",
  "entry": "HolaPlugin.qml",
  "version": "1.0.0",
  "title": "Hola",
  "description": "Qué hace, en una frase — sale en Ajustes",
  "host": ">=1.1.0",
  "permisos": []
}
```

- `id`: minúsculas, sin espacios, y **tiene que coincidir con el nombre de la
  carpeta**. Si choca con un plugin de la barra, pierde el tuyo.
- `entry`: el fichero que hereda de `K4.Plugin`, dentro de la propia carpeta.
- `host`: la versión mínima de barra que necesitas (`>=x.y.z`).
- `icono`: tu icono, de una de estas dos clases:
  - **un códice de la Nerd Font** en texto, `"0xF011A"` — búscalo con
    `python3 tools/glifos.py <palabra>`. Hereda el color del tema, así que
    queda como el resto de la barra y se apaga y se tiñe con ella.
  - **tu propia imagen**, `"icono.png"`: un fichero PNG o SVG **de tu
    carpeta** (sin rutas: tu icono es tuyo). El PNG tiene que ser de al menos
    **64×64** —por debajo se ve borroso justo donde más se mira, y un icono
    pixelado hace que un plugin bueno parezca malo— y pesar menos de 1 MB. El
    SVG no lleva mínimo, que para eso escala.

  Se valida al instalar: un icono que no existe, demasiado pequeño o en un
  formato raro es un error de instalación y no un cuadradito vacío en el
  centro de aplicaciones. Sale en Ajustes, en el centro de aplicaciones y en
  los accesos directos del centro de control.
- `aplicacion`: `true` si lo tuyo es algo que se **abre y se usa** —un juego,
  una herramienta— y no un indicador o un servicio. Con eso apareces en el
  centro de aplicaciones (SUPER+SHIFT+Space) y te pueden anclar a la franja
  del centro de control. Además apareces al escribir en el lanzador
  (SUPER+Space), que sigue siendo otro cajón —el de las aplicaciones del
  escritorio— pero encuentra las dos cosas.
- `permisos`: qué capacidades usas — ver más abajo. Vacío si solo pintas.

## 2 · El plugin y la vista

El plugin es el estado: vive siempre, tenga o no la island. La vista solo
pinta, y solo existe mientras el plugin tiene la island.

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

### El tamaño es tuyo

`islandWidth` e `islandHeight` los pides tú, y **puedes cambiarlos en vivo**:
un plugin puede ser una tira de 200×150 y convertirse en una pantalla grande
según lo que esté haciendo. El editor de vídeo de la barra hace justo eso.

```qml
islandWidth:  modo === "mini" ? 200 : 980
islandHeight: modo === "mini" ? 150 : K4.Isla.altoMaximo
```

El tope de alto es `K4.Isla.altoMaximo` (880 hoy). Pedir más no rompe nada
pero tampoco crece: lo que sobra se recorta, y una pantalla que no se puede
ver entera es peor que una más pequeña. Si tu contenido puede crecer sin
límite, mételo en un `K4.Rodillo` y deja el alto fijo.

Reglas que la barra hace cumplir:

- **Un plugin importa QtQuick y K4. Nada más.** Desde tu carpeta no hay ruta
  a los servicios internos, y así es a propósito: la API pública es el
  contrato que no se te rompe al actualizar.
- El id raíz conviene que sea `self`: una vista con `required property var
  plugin` puede tapar un id que se llame igual.
Si te declaras `aplicacion`, la barra te abrirá llamando a `abrir()`. Por
defecto usa tu `toggle()`, que es lo que ya tienen casi todos; redefínela si
necesitas otra cosa —por ejemplo abrir siempre en vez de alternar.

- Procesos, timers e IPC van como hijos del `K4.Plugin`, no de la vista: la
  vista se destruye cada vez que pierdes la island.

## 3 · Lo que la API te da

| Tipo | Para qué |
|---|---|
| `K4.Plugin` | el contrato: island, prioridad, teclado, vista |
| `K4.Tema` | la paleta (`tinta`, `superficie`, `apagado`…) y las fuentes |
| `K4.Etiqueta` | texto con los defaults de la barra |
| `K4.Glifo` | un icono de la Nerd Font (búscalos con `tools/glifos.py`) |
| `K4.Icono` | un icono del tema del escritorio, por nombre |
| `K4.Interruptor` | el switch de la barra; avisa, no cambia solo |
| `K4.Deslizador` | deslizador con etiqueta y valor |
| `K4.Baldosa` | la tarjeta pulsable del centro de control |
| `K4.Boton` | botón redondo de un glifo |
| `K4.Rodillo` | zona con scroll **que sí obedece a la rueda** |
| `K4.Aparicion` | entra con un fundido en vez de dar un salto |
| `K4.FocoInicial` | lleva el cursor a tu campo de texto al abrir |
| `K4.Idioma` | `t()` y `f()` — sin diccionario devuelven el texto tal cual |
| `K4.Guardado` | tu estado en JSON, en TU directorio, con `cargado`/`guardar` |
| `K4.Ipc` | tu target de IPC (`k4.<id>`) |
| `K4.Process` | procesos externos — requiere el permiso `procesos` |
| `K4.Sonido` | un sonido corto — requiere el permiso `sonido` |
| `K4.Fichero` | leer y escribir ficheros — requiere `ficheros` |
| `K4.Pildora` | un indicador en la píldora plegada |
| `K4.Paths` | rutas: `estadoDe(id)` es tu directorio de estado |

Y los datos vivos del sistema:

| Tipo | Qué da | Escribir pide |
|---|---|---|
| `K4.Audio` | volumen, silencio | `audio` |
| `K4.Medios` | qué suena: título, artista, carátula, posición | `medios` |
| `K4.Notificaciones` | las que llegan, con señal `llego()` | `notificaciones` |
| `K4.Red` | Wi‑Fi y Bluetooth — **solo lectura, sin excepción** | — |
| `K4.Escritorios` | cuáles hay y en cuál estás | — |
| `K4.Portapapeles` | el historial — **leer ya pide** `portapapeles` | `portapapeles` |
| `K4.Reloj` | la hora, del reloj único de la barra | — |

La línea la marca el efecto, no el módulo: mirar el volumen no le hace nada a
nadie, subirlo sí. El portapapeles va al revés porque guarda contraseñas y
tokens — ahí lo delicado es leer. Y conectarse a una red o emparejar un
aparato no se abre ni con permiso: equivocarse ahí cuesta quedarse sin red o
entregarle el portátil a un desconocido, y ninguna idea de plugin lo compensa.

`K4.Medios.posicion` solo avanza si alguien la mira: llama a
`seguirPosicion()` al montar tu vista y a `dejarPosicion()` al soltarla, o el
temporizador no corre.

Con esas piezas tu plugin tiene la MISMA cara que la barra sin dibujar un
rectángulo: `ejemplos/piezas/` es el muestrario, copiable y ejecutable. Y una
advertencia que te ahorra una tarde: si metes tu lista en un `Flickable`
normal y sus filas tienen hover o clic, **la rueda no funcionará** —un
MouseArea acepta la rueda tenga o no manejador— y no dará ningún error. Por
eso existe `K4.Rodillo`.

Para un juego: `K4.Guardado` es la partida y el récord, `grabKeyboard: true`
mientras se juega te da el teclado entero, y un `Timer` es el tick. La
Mazmorra del repo (`plugins/Game/`) es la referencia de que da para mucho.

## 3b · Salir en sitios que no son tuyos

Un plugin no tiene por qué vivir solo dentro de su island.

**Tus ajustes, en Ajustes.** Sin esto, dos opciones te obligaban a inventarte
una pantalla, un botón para abrirla y una forma de guardarlas — y el usuario
tenía que aprender un sitio nuevo por cada plugin.

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

Los valores los guardas TÚ: la barra pregunta por `valores` y avisa por
`cambiado`. Así lo que se enseña es siempre lo que de verdad tienes guardado
y no una copia que se desincroniza al primer fallo de escritura.

**Tus resultados, en el lanzador.** Contestas cuando puedes; si lo tuyo cuesta
—una consulta por red— no bloqueas a nadie.

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

**Y `K4.Isla`** para saber si estás a la vista: `abierta`, `ocupadaPor`,
`raton`, `altoMaximo`. Solo lectura — quién ocupa la island lo decide el host
comparando prioridades, que es la única forma de que dos plugins no se peleen
por la pantalla. Úsalo para no animar ni sondear cuando no te ve nadie.

Los tres se dan de baja solos cuando tu plugin se destruye —apagarlo,
recargarlo, desinstalarlo—, y el gestor barre además por id: una fila de
Ajustes que llame a un plugin muerto no puede existir.

## 4 · Permisos

El manifiesto declara lo que usas; la barra lo comprueba **antes de listar**:

| Permiso | Lo delata |
|---|---|
| `procesos` | `K4.Process` |
| `red` | `XMLHttpRequest`, `WebSocket` |
| `ficheros` | `K4.Fichero` |
| `sonido` | `K4.Sonido` |

Usar algo sin declararlo hace el plugin **no cargable**, con el motivo en
Ajustes. Y lo honesto: esto **no es un sandbox**. QML corre en el proceso de
la barra y un plugin cargado puede hacer lo que la barra pueda hacer. Los
permisos son consentimiento informado —el usuario los ve antes de encender—
más un análisis que atrapa el descuido y el engaño simple, no una jaula.
Instalar un plugin es confiar en su autor.

## 5 · El ciclo de vida

1. Los plugins de fuera llegan **deshabilitados**: se encienden en Ajustes
   (o `k4 pluginEnable <id>`), viendo antes descripción y permisos.
2. Deshabilitado = **no instanciado**: tu IPC ni existe.
3. Si tu QML no compila, la barra arranca sin ti y Ajustes enseña el error
   con fichero y línea; «reintentar» recarga del disco tras arreglarlo, sin
   reiniciar la barra.
4. `python3 tools/plugins.py` valida tu manifiesto y tus permisos sin
   arrancar nada.

### Mientras lo escribes

```sh
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4 pluginReload hola
```

Destruye tu plugin y lo vuelve a crear del disco: editas, recargas, miras. No
reinicia la barra ni toca a los demás. Recarga la carpeta ENTERA —entrada y
vistas—, así que vale igual para un retoque en la vista. Si la versión nueva
no compila, tu plugin queda en error con su motivo y el «reintentar» de
Ajustes; el resto de la barra ni se entera.

Un aviso honesto: recargar destruye tu objeto. Lo que tenga estado en memoria
y no hayas guardado con `K4.Guardado`, se pierde — que para desarrollar suele
ser justo lo que quieres.

## Plugins del repositorio

Para contribuir un plugin a la propia barra el camino es el mismo contrato,
con tres diferencias: la carpeta va en `plugins/`, se registra en
`plugins/catalog.json`, y la carpeta lleva un `qmldir` con todos sus tipos
(el esquema de URLs de Quickshell no resuelve hermanos sin él —
`tools/plugins.py` avisa si falta). Los del repo sí pueden usar los servicios
internos vía `"../../services"`, porque se actualizan con la barra.
