pragma Singleton

//  Objetos, rarezas y cofres.
//
//  Replica el esqueleto de TBH: diez grados de rareza con sus colores, cuatro
//  categorías de equipo y tres clases de cofre. Los objetos no están escritos
//  a mano: se generan por afijos —tipo + prefijo + sufijo— que es como se
//  consiguen cientos de piezas distintas sin dibujar ni nombrar ninguna.

import QtQuick
import Quickshell

Singleton {
    id: items

    // Los diez grados de TBH, con sus colores. El valor de desguace sube
    // ~×3,2 por grado, igual que allí.
    readonly property var rarezas: [
        { nombre: Idioma.t("Común"),      color: Idioma.t("#e4e4e4"), valor: 10,     mult: 1.00 },
        { nombre: Idioma.t("Poco común"), color: Idioma.t("#54fc0c"), valor: 30,     mult: 1.35 },
        { nombre: Idioma.t("Raro"),       color: Idioma.t("#2f8bfc"), valor: 90,     mult: 1.80 },
        { nombre: Idioma.t("Legendario"), color: Idioma.t("#fc9c0c"), valor: 270,    mult: 2.40 },
        { nombre: Idioma.t("Inmortal"),   color: Idioma.t("#fc2424"), valor: 810,    mult: 3.20 },
        { nombre: Idioma.t("Arcano"),     color: Idioma.t("#b40cfc"), valor: 2592,   mult: 4.30 },
        { nombre: Idioma.t("Más allá"),   color: Idioma.t("#fc246c"), valor: 8294,   mult: 5.70 },
        { nombre: Idioma.t("Celestial"),  color: Idioma.t("#6ccce4"), valor: 29029,  mult: 7.60 },
        { nombre: Idioma.t("Divino"),     color: Idioma.t("#fce454"), valor: 101602, mult: 10.10 },
        { nombre: Idioma.t("Cósmico"),    color: Idioma.t("#fcfcfc"), valor: 355607, mult: 13.50 }
    ]

    // Cuatro huecos por héroe, uno por categoría. El icono es el índice en la
    // hoja de sprites de objetos, que va en el mismo orden.
    readonly property var huecos: [
        {
            id: "arma", nombre: Idioma.t("Arma"), glifo: 0xF04E5,
            tipos: [Idioma.t("Espada"), Idioma.t("Hacha"), Idioma.t("Bastón"), Idioma.t("Arco"), Idioma.t("Daga")],
            generos: ["f", "f", "m", "m", "f"],
            iconos: [0, 1, 2, 3, 4],
            reparte: { daño: 4.0 }
        },
        {
            id: "escudo", nombre: Idioma.t("Mano izquierda"), glifo: 0xF0498,
            tipos: [Idioma.t("Escudo"), Idioma.t("Tomo"), Idioma.t("Orbe"), Idioma.t("Carcaj"), Idioma.t("Broquel")],
            generos: ["m", "m", "m", "m", "m"],
            iconos: [5, 6, 7, 8, 9],
            reparte: { armadura: 1.4, vida: 10 }
        },
        {
            id: "armadura", nombre: Idioma.t("Armadura"), glifo: 0xF0A38,
            tipos: [Idioma.t("Yelmo"), Idioma.t("Coraza"), Idioma.t("Guantes"), Idioma.t("Botas"), Idioma.t("Capa")],
            generos: ["m", "f", "mp", "fp", "f"],
            iconos: [10, 11, 12, 13, 14],
            reparte: { vida: 22, armadura: 0.8 }
        },
        {
            id: "amuleto", nombre: Idioma.t("Accesorio"), glifo: 0xF0DFA,
            tipos: [Idioma.t("Amuleto"), Idioma.t("Anillo"), Idioma.t("Brazal"), Idioma.t("Pendiente"), Idioma.t("Frasco")],
            generos: ["m", "m", "m", "m", "m"],
            iconos: [15, 16, 17, 18, 19],
            reparte: { vida: 9, daño: 1.6, cura: 1.2 },
            // Solo los accesorios recortan recargas: es lo que les da un
            // papel propio frente a armadura y escudo, que son vida a secas.
            recorta: true
        }
    ]

    // Declinados: en castellano el adjetivo concuerda, y "Botas tosco" canta
    // muchísimo. Los invariables en género (feroz, abisal, estelar) solo
    // cambian en plural.
    readonly property var prefijos: [
        { m: "roto",     f: "rota",     mp: "rotos",     fp: "rotas" },
        { m: "tosco",    f: "tosca",    mp: "toscos",    fp: "toscas" },
        { m: "sólido",   f: "sólida",   mp: "sólidos",   fp: "sólidas" },
        { m: "afilado",  f: "afilada",  mp: "afilados",  fp: "afiladas" },
        { m: "feroz",    f: "feroz",    mp: "feroces",   fp: "feroces" },
        { m: "rúnico",   f: "rúnica",   mp: "rúnicos",   fp: "rúnicas" },
        { m: "sagrado",  f: "sagrada",  mp: "sagrados",  fp: "sagradas" },
        { m: "abisal",   f: "abisal",   mp: "abisales",  fp: "abisales" },
        { m: "estelar",  f: "estelar",  mp: "estelares", fp: "estelares" },
        { m: "eterno",   f: "eterna",   mp: "eternos",   fp: "eternas" }
    ]

    readonly property var sufijos: [
        "del lobo", "del oso", "del águila", "de la sombra", "del titán",
        "de la aurora", "del vacío", "del dragón", "de los ancestros", "del cosmos"
    ]

    // Los tres cofres de TBH: el corriente cae de los monstruos, el de jefe
    // cada diez oleadas y el de acto cada cincuenta. Lo que cambian es el
    // suelo de rareza y cuánto empujan hacia arriba.
    readonly property var cofres: [
        { nombre: Idioma.t("Cofre corriente"), color: Idioma.t("#8e8e93"), suelo: 0, empuje: 0.0,  glifo: 0xF04D6 },
        { nombre: Idioma.t("Cofre de jefe"),   color: Idioma.t("#2f8bfc"), suelo: 2, empuje: 0.35, glifo: 0xF04D7 },
        { nombre: Idioma.t("Cofre de acto"),   color: Idioma.t("#fc9c0c"), suelo: 3, empuje: 0.75, glifo: 0xF0A75 }
    ]

    function rarezaDe(indice) {
        return rarezas[Math.max(0, Math.min(rarezas.length - 1, indice))]
    }

    function huecoDe(id) {
        for (let i = 0; i < huecos.length; ++i) {
            if (huecos[i].id === id)
                return huecos[i]
        }
        return huecos[0]
    }

    // ── tirada de rareza ──────────────────────────────────────────
    // Geométrica: cada grado es bastante menos probable que el anterior. La
    // oleada alcanzada y la fortuna acumulada empujan la cola hacia arriba,
    // que es lo que hace que seguir jugando merezca la pena.
    function tirarRareza(tipoCofre, oleada, fortuna) {
        const cofre = cofres[Math.max(0, Math.min(cofres.length - 1, tipoCofre))]
        // Logarítmico y sin techo. Con `Math.min(0.45, oleada / 220)` el
        // empuje se estancaba en la oleada 99: medido, la rareza media de un
        // cofre corriente era 0,54 en la 99 y 0,55 en la 600, o sea que llegar
        // más lejos no daba mejor botín y solo compensaba farmear. Así sigue
        // subiendo siempre y cada vez más despacio: en la 1600 un cofre de
        // jefe saca grado 4 o mejor el 38% de las veces, contra el 10% del
        // principio.
        const empuje = cofre.empuje + Math.log(1 + oleada / 30) * 0.22 + fortuna

        let grado = cofre.suelo
        while (grado < rarezas.length - 1 && Math.random() < 0.20 + empuje * 0.34)
            grado += 1

        return grado
    }

    // ── generación ────────────────────────────────────────────────
    function generar(tipoCofre, oleada, fortuna) {
        const rareza = tirarRareza(tipoCofre, oleada, fortuna)
        const hueco = huecos[Math.floor(Math.random() * huecos.length)]
        const cual = Math.floor(Math.random() * hueco.tipos.length)

        const genero = (hueco.generos && hueco.generos[cual]) || "m"
        const prefijo = prefijos[Math.min(prefijos.length - 1,
            Math.floor(rareza * 0.75 + Math.random() * 2.5))][genero]
        const sufijo = sufijos[Math.floor(Math.random() * sufijos.length)]

        // Escala con la oleada en que cayó: un objeto de la oleada 40 debe
        // valer más que el mismo de la 3, aunque compartan rareza.
        //
        // Y crece en exponencial, no en línea recta. Los héroes suben ~11% de
        // vida por nivel, así que con una escala lineal el botín se quedaba
        // atrás enseguida: en la oleada 64, con el grupo a nivel 39 y 12.000
        // de vida, la mejor coraza daba 705. Un 6%. Se notaba tan poco que
        // parecía no haber objetos, que es justo lo que se sentía jugando.
        // Al 6% por oleada una pieza vale siempre en torno al 12% de lo que
        // tiene un héroe de su nivel, y el juego de cuatro se nota de verdad.
        const escala = 1.25 * Math.pow(1.06, oleada - 1) * rarezaDe(rareza).mult
        const stats = ({})

        // cuántas estadísticas trae: de una a cuatro según el grado
        const cuantas = 1 + Math.floor(rareza / 3)
        const claves = Object.keys(hueco.reparte)

        for (let i = 0; i < Math.min(cuantas, claves.length); ++i) {
            const clave = claves[i]
            const variacion = 0.85 + Math.random() * 0.3
            stats[clave] = Math.max(1, Math.round(hueco.reparte[clave] * escala * variacion))
        }

        // los grados altos añaden una estadística extra de otro hueco
        if (rareza >= 5 && Object.keys(stats).length < 4) {
            const extra = ["daño", "vida", "armadura", "cura"][Math.floor(Math.random() * 4)]
            if (stats[extra] === undefined) {
                const bases = { daño: 2.2, vida: 12, armadura: 0.9, cura: 0.8 }
                stats[extra] = Math.max(1, Math.round(bases[extra] * escala * 0.6))
            }
        }

        // El recorte de recarga va en porcentaje, así que no puede escalar con
        // la oleada como el resto: subiría a miles. Depende solo del grado, y
        // el tope de acumulación lo pone el juego.
        if (hueco.recorta) {
            stats.recorte = Math.round((2.5 + rareza * 1.35
                + Math.random() * 2.5) * 10) / 10
        }

        return {
            id: Math.floor(Math.random() * 1e9),
            // El nivel exigido sigue al que de verdad llevas a esa altura:
            // con oleada/3 caían piezas de nivel 22 cuando el grupo iba por el
            // 39, y sobraban todas. A 0,6 por oleada la pieza que cae es justo
            // la que puedes ponerte, que es donde está la gracia.
            nivel: Math.max(1, Math.round(oleada * 0.6)),
            hueco: hueco.id,
            tipo: hueco.tipos[cual],
            icono: hueco.iconos[cual],
            rareza: rareza,
            oleada: oleada,
            nombre: hueco.tipos[cual] + " Idioma.t(" + prefijo + ") " + sufijo,
            stats: stats
        }
    }

    // Nivel de la pieza, como en TBH: la rareza dice de qué familia es y el
    // nivel cuánto rinde. Así un común de nivel alto puede valer más que un
    // legendario recogido en las primeras oleadas, y mirar el botín deja de
    // ser leer un color.
    function nivelDe(objeto) {
        if (!objeto)
            return 1
        if (objeto.nivel !== undefined)
            return objeto.nivel
        return Math.max(1, Math.round((objeto.oleada || 1) / 3) + 1)   // piezas antiguas
    }

    function valorDesguace(objeto) {
        if (!objeto)
            return 0
        return Math.ceil(rarezaDe(objeto.rareza).valor * (1 + nivelDe(objeto) * 0.24))
    }

    // Puntuación para ordenar la bolsa y para decidir si algo es mejor que lo
    // puesto. No es exacta —depende de la clase— pero ordena bien.
    function puntuacion(objeto) {
        if (!objeto)
            return 0
        const s = objeto.stats
        return (s.daño || 0) * 3 + (s.vida || 0) * 0.5
            + (s.armadura || 0) * 6 + (s.cura || 0) * 4
    }

    // Lo que hay que tener para ponérselo. Que el nivel sea también un
    // requisito es lo que lo convierte en una meta: encontrar una pieza buena
    // pronto da algo por lo que seguir subiendo, en vez de equiparla y ya.
    function nivelRequerido(objeto) {
        return nivelDe(objeto)
    }

    function etiqueta(objeto) {
        if (!objeto)
            return ""
        return rarezaDe(objeto.rareza).nombre + " · nivel " + nivelDe(objeto)
    }

    function resumen(objeto) {
        if (!objeto)
            return ""
        const s = objeto.stats
        const partes = []
        if (s.daño) partes.push("+" + s.daño + " daño")
        if (s.vida) partes.push("+" + s.vida + " vida")
        if (s.armadura) partes.push("+" + s.armadura + " arm")
        if (s.cura) partes.push("+" + s.cura + " cura")
        if (s.recorte) partes.push("-" + s.recorte + "% recarga")
        return partes.join(" · ")
    }
}
