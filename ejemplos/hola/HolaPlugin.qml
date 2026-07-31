//  El plugin mínimo: un saludo en la island.
//
//  Es el ejemplo de docs/PLUGINS.md, completo y cargable tal cual: copia la
//  carpeta a ~/.config/k4/plugins/hola, enciéndelo en Ajustes, y
//  `quickshell ipc -p <ruta>/shell.qml call k4.hola toggle` lo abre.

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "hola"
    title: "Hola"
    priority: 65
    active: abierto
    islandWidth: 360
    islandHeight: 100

    property bool abierto: false
    property int visitas: 0
    property bool saludar: true
    property string aQuien: ""

    view: Component { HolaView { plugin: self } }

    //  El estado propio: sobrevive a reiniciar la barra.
    property var guardado: K4.Guardado {
        plugin: "hola"
        onCargado: function (d) {
            self.visitas = d.visitas || 0
            self.saludar = d.saludar !== false
            self.aQuien = d.aQuien || ""
        }
    }

    function apuntar() {
        guardado.guardar({ visitas: visitas, saludar: saludar,
                           aQuien: aQuien })
    }

    //  Mis ajustes, dentro de los Ajustes de la barra. Los valores los guardo
    //  yo; la barra solo pregunta y avisa.
    property var misAjustes: K4.Ajustes {
        plugin: "hola"
        grupo: K4.Idioma.t("Hola")
        opciones: [
            { id: "saludar", nombre: K4.Idioma.t("Saludar al abrir"),
              desc: K4.Idioma.t("Si no, solo enseña el contador"),
              glifo: 0xF1821 },
            //  Un campo libre: aquí un nombre; en un plugin de verdad, la
            //  URL de un servicio o —con `secreto: true`— su clave.
            { id: "aQuien", tipo: "texto",
              nombre: K4.Idioma.t("A quién saludar"),
              desc: K4.Idioma.t("Sale en el saludo de la island"),
              pista: K4.Idioma.t("el mundo"), glifo: 0xF17C4 }
        ]
        valores: ({ saludar: self.saludar, aQuien: self.aQuien })
        onCambiado: function (id, valor) {
            if (id === "saludar")
                self.saludar = valor
            if (id === "aQuien")
                self.aQuien = String(valor).trim()
            self.apuntar()
        }
    }

    //  Y una entrada en el lanzador, para abrirse escribiendo.
    property var enElLanzador: K4.Lanzador {
        plugin: "hola"
        onBuscando: function (texto) {
            const t = texto.trim().toLowerCase()
            resultados = (t.length >= 2 && "hola".indexOf(t) === 0)
                ? [{ id: "abrir", titulo: K4.Idioma.t("Abrir Hola"),
                     desc: K4.Idioma.t("El plugin de ejemplo") }]
                : []
        }
        onElegido: function (id) { if (id === "abrir") self.abierto = true }
    }

    K4.Ipc {
        target: "k4.hola"
        function toggle(): void {
            self.abierto = !self.abierto
            if (self.abierto) {
                self.visitas += 1
                self.apuntar()
            }
        }
        function close(): void { self.abierto = false }
    }
}
