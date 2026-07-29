# Escribir un plugin para k4

> Un plugin importa `QtQuick` y `K4`. Nada más.

Esa es la regla, y `tools/api.py` la comprueba. Si te hace falta algo que `K4`
no da, se añade a la API o se baja a un servicio — no se importa a pelo.

## Por qué

Todo lo que un plugin importe de Quickshell solo existe donde existe Quickshell:
Linux con Wayland. El día que haya un host propio para Windows o Mac, lo escrito
contra `Quickshell.Io` hay que reescribirlo; lo escrito contra `K4` se porta
reescribiendo únicamente esta carpeta.

Pero el beneficio se nota ya, sin esperar a ningún host: en vez de aprenderte
Quickshell entero tienes una API pequeña y documentada en un sitio. Menos
superficie, menos formas de romperse.

La línea se traza donde de verdad está: **Qt es portable, Quickshell no**.
`QtQuick`, `QtMultimedia`, `QtQml`, `Timer`, `Canvas`, animaciones, `Shape`…
existen igual en los tres sistemas y se usan tal cual. No hay nada que envolver.

## Lo mínimo

Una carpeta en `plugins/` con un fichero que herede de `K4Plugin`:

```qml
import QtQuick
import K4 as K4
import "../../core"

K4Plugin {
    id: self

    name: "saludo"
    priority: 70
    active: abierto
    islandWidth: 300
    islandHeight: 120

    property bool abierto: false

    view: Component {
        Item {
            IslandLabel { anchors.centerIn: parent; text: "hola" }
        }
    }

    K4.Ipc {
        target: "k4.saludo"
        function toggle(): void { self.abierto = !self.abierto }
    }
}
```

`K4Plugin` (en `core/`) es el contrato: cuándo quieres la island, qué tamaño
necesitas, qué pintas dentro y si quieres el teclado. Está documentado arriba
del propio fichero.

Los `Process`, `Timer` e `IpcHandler` van como **hijos sueltos del plugin**, no
dentro de la vista: la vista solo existe mientras tu módulo tiene la island, y
casi todo lo que hace un plugin tiene que seguir vivo con la island cerrada.

## Qué ofrece `K4`

| | Para qué |
|---|---|
| `K4.Process` | Lanzar algo y leer su salida |
| `K4.Ipc` | Recibir órdenes de fuera, normalmente de un atajo |
| `K4.Fichero` | Leer y escribir un fichero de texto |
| `K4.Paths` | `estado`, `guion(nombre)`, `enRaiz(ruta)` |
| `K4.Sistema` | `lanzar`, `abrir`, `avisar`, `copiar`, `entorno` |
| `K4.Apps` | Las aplicaciones instaladas y sus iconos |
| `K4.Icono` | Pintar un icono del tema |
| `K4.Ventana` | Una superficie propia, aparte de la island |
| `K4.PorPantalla` | Una copia de algo por cada monitor |
| `K4.Cargador` | Cargar algo caro solo cuando hace falta |
| `K4.Atajo` | Un atajo global |
| `K4.Autenticacion` | Comprobar la contraseña del usuario |
| `K4.BloqueoSesion` | Bloquear la sesión de verdad |
| `K4.MenuBandeja` | El menú que publica un icono de bandeja |

Cada uno está documentado en su fichero, con las trampas que ya se han pagado.

### Procesos

Dos formas de leer la salida, y solo dos, porque son las que hacen falta:

```qml
// una línea cada vez, mientras trabaja
K4.Process {
    command: ["python3", K4.Paths.guion("sistema.py")]
    running: mirando
    porLineas: true
    onLinea: function (l) { const d = JSON.parse(l); ... }
}

// todo de golpe, al terminar
K4.Process {
    command: ["pacman", "-Qq"]
    running: true
    onSalida: function (texto) { ... }
}
```

Para pararlo, `parar()`, que manda SIGINT. Importa: matar a secas algo que esté
escribiendo un fichero lo deja a medias — un vídeo sin su índice no lo abre
nadie.

## Lo que todavía no está

- **Presencia en la píldora.** Hoy el indicador del juego se inyecta a mano en
  las vistas del reloj y del reproductor; un plugin externo no puede. Falta un
  `K4.Pildora` para registrar un indicador con su acción de clic. Es lo que hace
  que un plugin se sienta vivo sin estar abierto.
- **El kit de widgets.** `IslandTile`, `IslandSlider`, `IconGlyph`… existen en
  `core/` y son puros; publicarlos haría que un plugin de fuera se vea nativo en
  vez de traer su propia estética.
- **Ajustes de plugin**, para que declares tus opciones y salgan en el módulo de
  Ajustes en vez de inventarte una pantalla.
- **Permisos.** Hoy cualquier plugin puede lanzar cualquier proceso. Antes de
  que exista un directorio público de plugins hay que decidir si eso sigue así o
  se declara en un manifiesto.
