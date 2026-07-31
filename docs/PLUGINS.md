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

Reglas que la barra hace cumplir:

- **Un plugin importa QtQuick y K4. Nada más.** Desde tu carpeta no hay ruta
  a los servicios internos, y así es a propósito: la API pública es el
  contrato que no se te rompe al actualizar.
- El id raíz conviene que sea `self`: una vista con `required property var
  plugin` puede tapar un id que se llame igual.
- Procesos, timers e IPC van como hijos del `K4.Plugin`, no de la vista: la
  vista se destruye cada vez que pierdes la island.

## 3 · Lo que la API te da

| Tipo | Para qué |
|---|---|
| `K4.Plugin` | el contrato: island, prioridad, teclado, vista |
| `K4.Tema` | la paleta (`tinta`, `superficie`, `apagado`…) y las fuentes |
| `K4.Etiqueta` | texto con los defaults de la barra |
| `K4.Idioma` | `t()` y `f()` — sin diccionario devuelven el texto tal cual |
| `K4.Guardado` | tu estado en JSON, en TU directorio, con `cargado`/`guardar` |
| `K4.Ipc` | tu target de IPC (`k4.<id>`) |
| `K4.Process` | procesos externos — requiere el permiso `procesos` |
| `K4.Fichero` | leer y escribir ficheros — requiere `ficheros` |
| `K4.Pildora` | un indicador en la píldora plegada |
| `K4.Paths` | rutas: `estadoDe(id)` es tu directorio de estado |

Para un juego: `K4.Guardado` es la partida y el récord, `grabKeyboard: true`
mientras se juega te da el teclado entero, y un `Timer` es el tick. La
Mazmorra del repo (`plugins/Game/`) es la referencia de que da para mucho.

## 4 · Permisos

El manifiesto declara lo que usas; la barra lo comprueba **antes de listar**:

| Permiso | Lo delata |
|---|---|
| `procesos` | `K4.Process` |
| `red` | `XMLHttpRequest`, `WebSocket` |
| `ficheros` | `K4.Fichero` |

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
