//  Los submapas de Hyprland, anunciados en la píldora.
//
//  Un submapa es el teclado hablando otro idioma un rato: las teclas de la
//  captura, las de redimensionar ventanas, lo que hayas montado tú. Es
//  invisible por diseño, justo hasta que se te olvida qué idioma habla y cada
//  tecla empieza a hacer lo que no es. Este plugin lee el submapa activo por
//  `K4.Submapas` y declara una extensión de la cápsula por `K4.Capsula`
//  mientras haya uno puesto — y eso es TODO lo que le hace a la barra. Ni
//  tripas de la píldora ni geometría: está escrito contra la API pública y
//  nada más, la misma que recibe un plugin instalado en ~/.config/k4/plugins,
//  y se podría coger y dejar ahí tal cual.
//
//  Nunca se queda la island (`active` es siempre false): la extensión es parte
//  de la PÍLDORA, no una vista. La píldora sigue siendo ella —carátula, hora,
//  bandeja— y el nombre viaja en su flanco. Cuando una vista desplegada se
//  queda la island, la extensión se pliega con la píldora y vuelve con ella;
//  esa regla es de la cápsula, no de este plugin.

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "submap"
    title: K4.Idioma.t("Submapa")
    priority: 10
    active: false

    // ── lo que dice Hyprland ──────────────────────────────────
    readonly property string mapaActual: K4.Submapas.actual

    readonly property bool enMarcha: habilitado && mostrar
        && mapaActual.length > 0

    //  El nombre tal como se lee: «shot-manager» y «shot_manager» acaban los
    //  dos en «Shot manager». El id crudo se queda de id; lo que enseña la
    //  píldora es una palabra.
    readonly property string etiqueta: {
        if (mapaActual.length === 0)
            return ""
        const s = mapaActual.replace(/[-_]+/g, " ")
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    // ── ajustes ───────────────────────────────────────────────
    //
    //  Si la extensión pasa siquiera, hacia qué lado crece y hasta dónde puede
    //  llegar — un número libre y no cuatro presets, porque el nombre más
    //  largo que declare alguien no se sabe de antemano. Viven en la sección
    //  propia del plugin dentro de Ajustes y se guardan en su fichero.
    property bool mostrar: true
    property string lado: "derecha"        // "izquierda" · "derecha"
    property int largoMaximo: 300          // px, entre 60 y 1200

    // ── la extensión de la cápsula ────────────────────────────
    //
    //  Toda la integración es esto. `extension` es una binding que construye
    //  un objeto NUEVO cuando cambia el estado, y null cuando no hay nada que
    //  decir — que es el contrato de la API para entrar y para salir. Medir,
    //  capar y crecer son cosa de la barra.
    K4.Capsula {
        plugin: "submap"
        extension: self.enMarcha ? ({
            lado: self.lado,
            texto: self.etiqueta,
            glifo: 0xF030E,               // md-keyboard_caps
            color: K4.Tema.azul,
            largoMaximo: self.largoMaximo
        }) : null
    }

    // ── los ajustes, guardados ────────────────────────────────
    //
    //  Se acota al LEER y no al recibir: por `cambiado` llega un entero ya
    //  dentro de los límites —lo garantiza el tipo «numero»—, pero el
    //  fichero de estado se puede editar a mano, y de ahí puede venir
    //  cualquier cosa.
    function acotarLargo(v) {
        const n = Math.floor(Number(v))
        if (!isFinite(n))
            return 300
        return Math.max(60, Math.min(1200, n))
    }

    property var almacen: K4.Guardado {
        plugin: "submap"
        onCargado: function (d) {
            if (d.mostrar !== undefined)
                self.mostrar = d.mostrar === true
            if (d.lado === "izquierda" || d.lado === "derecha")
                self.lado = d.lado
            if (d.largoMaximo !== undefined)
                self.largoMaximo = self.acotarLargo(d.largoMaximo)
        }
    }

    function guardar() {
        almacen.guardar({ mostrar: mostrar, lado: lado,
                          largoMaximo: largoMaximo })
    }

    K4.Ajustes {
        plugin: "submap"
        grupo: K4.Idioma.t("Submapa")
        glifo: 0xF030E   // md-keyboard_caps
        desc: K4.Idioma.t("La píldora crece hacia un borde con el nombre del modo activo.")

        opciones: [
            { id: "mostrar", nombre: K4.Idioma.t("Enseñar el submapa activo"),
              desc: K4.Idioma.t("La cápsula se extiende mientras hay un modo puesto"),
              glifo: 0xF030E },
            { id: "lado", nombre: K4.Idioma.t("Hacia qué lado crece"),
              desc: K4.Idioma.t("Hacia el borde izquierdo o el derecho de la pantalla"),
              glifo: 0xF0E73, tipo: "eleccion",
              alternativas: [{ codigo: "izquierda", nombre: K4.Idioma.t("Izquierda") },
                             { codigo: "derecha", nombre: K4.Idioma.t("Derecha") }] },
            { id: "largoMaximo", tipo: "numero",
              nombre: K4.Idioma.t("Largo máximo"),
              desc: K4.Idioma.t("Píxeles hasta los que puede crecer; el nombre se recorta al pasarlos"),
              glifo: 0xF046D,
              min: 60, max: 1200, paso: 20, unidad: "px" }
        ]
        valores: ({
            mostrar: self.mostrar,
            lado: self.lado,
            largoMaximo: self.largoMaximo
        })
        onCambiado: function (id, valor) {
            if (id === "mostrar")
                self.mostrar = valor === true
            else if (id === "lado" && (valor === "izquierda" || valor === "derecha"))
                self.lado = valor
            else if (id === "largoMaximo")
                self.largoMaximo = self.acotarLargo(valor)
            else
                return
            self.guardar()
        }
    }
}
