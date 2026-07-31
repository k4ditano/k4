//  El centro de aplicaciones: todo lo que la barra sabe abrir, en una rejilla.
//
//  La barra tiene once cosas que son aplicaciones —la mazmorra, el editor, el
//  portapapeles, los atajos…— y hasta ahora la única forma de llegar a ellas
//  era saberse el atajo o el nombre del comando. Eso está bien para quien la
//  configuró y es invisible para todos los demás, y sobre todo deja fuera a
//  los plugins instalados: un juego que te bajas no tiene atajo hasta que te
//  lo pones.
//
//  Es el cajón de aplicaciones del móvil, y a propósito: rejilla, buscador
//  arriba, escribes y filtras, Enter abre. Nadie tiene que aprender nada.
//
//  Qué sale aquí lo dice el catálogo (`aplicacion: true`), no el código: así
//  un plugin de fuera entra solo con declararlo en su manifiesto.

import QtQuick
import K4 as K4
import "../../services"

K4.Plugin {
    id: self

    name: "apps"
    title: "Aplicaciones"
    priority: 72
    active: abierto
    grabKeyboard: abierto
    islandWidth: 700
    islandHeight: 520

    property bool abierto: false
    property string busqueda: ""
    property int seleccion: 0

    //  Las de la barra, filtradas por lo que se escribe. Una apagada NO
    //  desaparece: sale en gris. Que algo se esfume al apagarlo obliga a
    //  adivinar dónde se fue; en gris se ve que está y por qué no se abre.
    readonly property var lista: {
        const todas = PluginManager.aplicaciones
        const q = busqueda.trim().toLowerCase()
        if (q.length === 0)
            return todas
        return todas.filter(function (a) {
            return a.nombre.toLowerCase().indexOf(q) >= 0
        })
    }

    readonly property int columnas: 5

    view: Component { AppsView { plugin: self } }

    function abrirse() {
        busqueda = ""
        seleccion = 0
        abierto = true
    }

    function toggle() {
        if (abierto)
            cerrar()
        else
            abrirse()
    }

    function cerrar() { abierto = false }
    function close() { cerrar() }

    //  Abrir la elegida: se cierra ANTES, que si no las dos piden la island a
    //  la vez y gana la de más prioridad —que es esta— y parece que no ha
    //  pasado nada.
    function lanzar(id) {
        cerrar()
        PluginManager.abrirAplicacion(id)
    }

    function lanzarSeleccion() {
        if (seleccion >= 0 && seleccion < lista.length)
            lanzar(lista[seleccion].id)
    }

    function mover(dx, dy) {
        if (lista.length === 0)
            return
        let n = seleccion + dx + dy * columnas
        //  En los bordes se queda, no da la vuelta: saltar de la última a la
        //  primera con una flecha desorienta más de lo que ayuda.
        seleccion = Math.max(0, Math.min(lista.length - 1, n))
    }

    K4.Ipc {
        target: "k4.apps"
        function toggle(): void { self.toggle() }
        function open(): void { self.abrirse() }
        function close(): void { self.cerrar() }
    }
}
