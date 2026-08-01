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
        { nombre: Idioma.t("Común"),      color: "#e4e4e4", valor: 10,     mult: 1.00 },
        { nombre: Idioma.t("Poco común"), color: "#54fc0c", valor: 30,     mult: 1.35 },
        { nombre: Idioma.t("Raro"),       color: "#2f8bfc", valor: 90,     mult: 1.80 },
        { nombre: Idioma.t("Legendario"), color: "#fc9c0c", valor: 270,    mult: 2.40 },
        { nombre: Idioma.t("Inmortal"),   color: "#fc2424", valor: 810,    mult: 3.20 },
        { nombre: Idioma.t("Arcano"),     color: "#b40cfc", valor: 2592,   mult: 4.30 },
        { nombre: Idioma.t("Más allá"),   color: "#fc246c", valor: 8294,   mult: 5.70 },
        { nombre: Idioma.t("Celestial"),  color: "#6ccce4", valor: 29029,  mult: 7.60 },
        { nombre: Idioma.t("Divino"),     color: "#fce454", valor: 101602, mult: 10.10 },
        { nombre: Idioma.t("Cósmico"),    color: "#fcfcfc", valor: 355607, mult: 13.50 }
    ]

    // Cuatro huecos por héroe, uno por categoría. El icono es el índice en la
    // hoja de sprites de objetos, que va en el mismo orden.
    readonly property var huecos: [
        {
            id: "arma", nombre: Idioma.t("Arma"), glifo: 0xF04E5,
            tipos: ["Espada", "Hacha", "Bastón", "Arco", "Daga"],
            generos: ["f", "f", "m", "m", "f"],
            iconos: [0, 1, 2, 3, 4],
            reparte: { daño: 4.0 }
        },
        {
            id: "escudo", nombre: Idioma.t("Mano izquierda"), glifo: 0xF0498,
            tipos: ["Escudo", "Tomo", "Orbe", "Carcaj", "Broquel"],
            generos: ["m", "m", "m", "m", "m"],
            iconos: [5, 6, 7, 8, 9],
            reparte: { armadura: 1.4, vida: 10 }
        },
        {
            id: "armadura", nombre: Idioma.t("Armadura"), glifo: 0xF0A38,
            tipos: ["Yelmo", "Coraza", "Guantes", "Botas", "Capa"],
            generos: ["m", "f", "mp", "fp", "f"],
            iconos: [10, 11, 12, 13, 14],
            reparte: { vida: 22, armadura: 0.8 }
        },
        {
            id: "amuleto", nombre: Idioma.t("Accesorio"), glifo: 0xF0DFA,
            tipos: ["Amuleto", "Anillo", "Brazal", "Pendiente", "Frasco"],
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
        { nombre: Idioma.t("Cofre corriente"), color: "#8e8e93", suelo: 0, empuje: 0.0,  glifo: 0xF04D6 },
        { nombre: Idioma.t("Cofre de jefe"),   color: "#2f8bfc", suelo: 2, empuje: 0.35, glifo: 0xF04D7 },
        { nombre: Idioma.t("Cofre de acto"),   color: "#fc9c0c", suelo: 3, empuje: 0.75, glifo: 0xF0A75 }
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

        // De acero o arcana: la mitad de las piezas convierten su daño en
        // mágico y su armadura en resistencia. El nombre no cambia —ya bastante
        // largo es— pero el resumen lo dice y el color del texto también.
        const arcana = Math.random() < 0.5
        if (arcana) {
            if (stats.daño !== undefined) {
                stats.dañoMag = stats.daño
                delete stats.daño
            }
            if (stats.armadura !== undefined) {
                stats.resistencia = stats.armadura
                delete stats.armadura
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
            escuela: arcana ? "arcana" : "acero",
            oleada: oleada,
            nombre: hueco.tipos[cual] + " " + prefijo + " " + sufijo,
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

    // ── combinar tres iguales ─────────────────────────────────────
    //
    //  Tres piezas del mismo tipo, grado y nivel salen una. Que sean TRES no
    //  es un capricho: cada grado vale el triple que el anterior, así que con
    //  3 -> 1 el mejor caso posible —subir siempre— es empatar en valor, y
    //  nunca imprimir. Con 2 -> 1 el sistema se rompe solo.
    //
    //  Aun así la probabilidad de subir baja con el grado, para que la cola
    //  alta se gane jugando y no moliendo lo que sobra.

    function probMejora(rareza) {
        return 0.5 * Math.pow(0.72, rareza)
    }

    function probEmpeora(rareza) {
        return Math.min(0.3, 0.08 + 0.035 * rareza)
    }

    // Qué sale de combinar. `piezas` son tres del mismo grupo.
    function combinar(piezas) {
        if (!piezas || piezas.length < 3)
            return null

        const base = piezas[0]
        const r = base.rareza
        const tirada = Math.random()
        const sube = probMejora(r)
        const baja = probEmpeora(r)

        let nuevaRareza = r
        let cambio = "igual"
        if (tirada < sube && r < rarezas.length - 1) {
            nuevaRareza = r + 1
            cambio = "mejor"
        } else if (tirada > 1 - baja && r > 0) {
            nuevaRareza = r - 1
            cambio = "peor"
        }

        // El nivel se conserva: si no, combinar sería una forma de perderlo y
        // nadie lo usaría con piezas altas.
        const nivel = Math.max.apply(null, piezas.map(function (o) {
            return nivelDe(o)
        }))

        // Se genera de cero con el grado que haya salido, a la altura que
        // corresponde a ese nivel, y se le calza el mismo hueco y dibujo para
        // que se reconozca como pariente de lo que echaste.
        const salida = generar(0, Math.round(nivel / 0.6), 0)
        salida.rareza = nuevaRareza
        salida.nivel = nivel
        salida.hueco = base.hueco
        salida.tipo = base.tipo
        salida.icono = base.icono
        salida.nombre = base.tipo + " " + salida.nombre.split(" ").slice(1).join(" ")

        // las estadísticas se rehacen al grado nuevo
        const factor = rarezaDe(nuevaRareza).mult / rarezaDe(r).mult
        const st = ({})
        for (const k in base.stats)
            st[k] = k === "recorte" ? base.stats[k]
                : Math.max(1, Math.round(base.stats[k] * factor * (0.9 + Math.random() * 0.25)))
        salida.stats = st
        salida.escuela = base.escuela
        salida.nuevo = true

        return { objeto: salida, cambio: cambio }
    }

    function puntuacion(objeto) {
        if (!objeto)
            return 0
        const s = objeto.stats
        // Cuentan los cuatro: si no, el clic que equipa solo daría por vacía
        // media pieza arcana y nunca la pondría.
        return ((s.daño || 0) + (s.dañoMag || 0)) * 3 + (s.vida || 0) * 0.5
            + ((s.armadura || 0) + (s.resistencia || 0)) * 6 + (s.cura || 0) * 4
            + (s.recorte || 0) * 2
    }

    // Lo que hay que tener para ponérselo. Que el nivel sea también un
    // requisito es lo que lo convierte en una meta: encontrar una pieza buena
    // pronto da algo por lo que seguir subiendo, en vez de equiparla y ya.
    function nivelRequerido(objeto) {
        return nivelDe(objeto)
    }

    function resumen(objeto) {
        if (!objeto)
            return ""
        const s = objeto.stats
        const partes = []
        if (s.daño) partes.push("+" + s.daño + " " + Idioma.t("daño"))
        if (s.dañoMag) partes.push("+" + s.dañoMag + " " + Idioma.t("daño mágico"))
        if (s.vida) partes.push("+" + s.vida + " " + Idioma.t("vida"))
        if (s.armadura) partes.push("+" + s.armadura + " " + Idioma.t("arm"))
        if (s.resistencia) partes.push("+" + s.resistencia + " " + Idioma.t("resist"))
        if (s.cura) partes.push("+" + s.cura + " " + Idioma.t("cura"))
        if (s.recorte) partes.push("-" + s.recorte + "% recarga")
        return partes.join(" · ")
    }
}
