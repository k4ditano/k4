pragma Singleton

//  Dónde se apuntan los plugins que quieren aparecer en sitios de la barra
//  que no son suyos: sus ajustes en Ajustes, sus resultados en el lanzador.
//
//  Un registro y no una lista de importaciones cruzadas, por lo de siempre:
//  Ajustes no puede conocer a un plugin que todavía no existe, y menos a uno
//  que vive en ~/.config/k4/plugins. Aquí cada uno se apunta al nacer y se
//  borra al morir.
//
//  Lo de «al morir» no es un detalle: los plugins se destruyen de verdad
//  —apagarlos, recargarlos en caliente, desinstalarlos— y un enganche
//  huérfano sería una fila en Ajustes que al pulsarla llama a un cadáver. Por
//  eso se limpia por partida doble: el propio enganche se da de baja al
//  destruirse, y el gestor barre por id cuando tumba un plugin.

import QtQuick
import Quickshell

Singleton {
    id: registro

    // ── ajustes aportados ─────────────────────────────────────────
    //
    //  Cada entrada: { plugin, grupo, opciones: [...], fuente }
    //  `fuente` es el objeto K4.Ajustes, que es quien sabe los valores.
    property var ajustes: []

    //  El prefijo que hace que Ajustes sepa a quién preguntar. Va con el id
    //  del plugin dentro para que dos plugins puedan usar el mismo nombre de
    //  opción sin pisarse.
    function idExterno(plugin, opcion) {
        return "ext_" + plugin + "_" + opcion
    }

    function _partes(id) {
        //  "ext_<plugin>_<opcion>": el plugin no lleva guiones bajos porque
        //  RE_ID no los admite, así que la primera partición es la buena.
        const resto = String(id).substring(4)
        const corte = resto.indexOf("_")
        if (corte < 0)
            return null
        return { plugin: resto.substring(0, corte),
                 opcion: resto.substring(corte + 1) }
    }

    function _fuente(plugin) {
        for (let i = 0; i < ajustes.length; ++i)
            if (ajustes[i].plugin === plugin)
                return ajustes[i].fuente
        return null
    }

    //  Solo reemplaza SU entrada de ajustes. Antes barría con `quitarDe`, que
    //  es la escoba de «este plugin ha muerto» y se lleva también su enganche
    //  del lanzador — y como K4.Ajustes se vuelve a registrar cada vez que
    //  cambian sus `opciones`, un plugin con las dos cosas perdía la del
    //  lanzador al primer cambio, sin un solo error por ningún lado. No se
    //  notó antes porque hasta ahora ningún plugin tenía las dos.
    function registrarAjustes(fuente) {
        if (!fuente || !fuente.plugin)
            return
        ajustes = ajustes.filter(function (x) {
            return x.plugin !== fuente.plugin
        }).concat([{ plugin: fuente.plugin,
                     grupo: fuente.grupo,
                     opciones: fuente.opciones || [],
                     fuente: fuente }])
    }

    //  Esta sí barre las dos: es para cuando el plugin se va.
    function quitarDe(plugin) {
        const quedan = ajustes.filter(function (x) { return x.plugin !== plugin })
        if (quedan.length !== ajustes.length)
            ajustes = quedan
        const quedanL = lanzador.filter(function (x) { return x.plugin !== plugin })
        if (quedanL.length !== lanzador.length)
            lanzador = quedanL
    }

    //  Lo que Ajustes añade al final de su lista de grupos.
    readonly property var gruposAjustes: {
        const salida = []
        for (let i = 0; i < ajustes.length; ++i) {
            const a = ajustes[i]
            if (!a.opciones || a.opciones.length === 0)
                continue
            salida.push({
                grupo: a.grupo || a.plugin,
                //  Para la barra lateral de la ventana de Ajustes: un icono y
                //  una línea por sección. Si el plugin no dice nada, se coge
                //  el icono que ya declara en su manifiesto — que es el que la
                //  gente asocia con él en el centro de aplicaciones, así que
                //  pedirle otro sería pedirle lo mismo dos veces.
                glifo: a.fuente && a.fuente.glifo ? a.fuente.glifo : 0,
                desc: a.fuente && a.fuente.desc ? a.fuente.desc : "",
                dePlugin: a.plugin,
                //  No salen como sección propia en la lateral: viven dentro de
                //  la fila de SU plugin, al lado del interruptor que los
                //  enciende. Tenerlos en dos cajones distintos obligaba a
                //  cruzar la ventana para apagar lo que acabas de configurar.
                //
                //  Pero siguen en `Settings.definicion`, y eso importa: el
                //  buscador recorre la lista entera, así que escribir el nombre
                //  de un ajuste de plugin lo sigue encontrando.
                enLateral: false,
                opciones: a.opciones.map(function (o) {
                    return Object.assign({}, o, {
                        id: registro.idExterno(a.plugin, o.id)
                    })
                })
            })
        }
        return salida
    }

    function valorAjuste(id) {
        const p = _partes(id)
        if (!p)
            return false
        const f = _fuente(p.plugin)
        return f ? (f.valores ? f.valores[p.opcion] : false) : false
    }

    function alternarAjuste(id) {
        const p = _partes(id)
        if (!p)
            return
        const f = _fuente(p.plugin)
        if (f)
            f.cambiado(p.opcion, !valorAjuste(id))
    }

    function ponerAjuste(id, valor) {
        const p = _partes(id)
        if (!p)
            return
        const f = _fuente(p.plugin)
        if (f)
            f.cambiado(p.opcion, valor)
    }

    // ── resultados en el lanzador ─────────────────────────────────
    //
    //  Cada entrada: { plugin, fuente }. El lanzador pregunta a todos al
    //  escribir y cada uno contesta cuando puede: nadie bloquea a nadie.
    property var lanzador: []

    signal buscando(string texto)

    function registrarLanzador(fuente) {
        if (!fuente || !fuente.plugin)
            return
        lanzador = lanzador.filter(function (x) {
            return x.plugin !== fuente.plugin
        }).concat([{ plugin: fuente.plugin, fuente: fuente }])
    }

    function buscar(texto) {
        buscando(texto)
    }

    //  Lo que hay que pintar ahora mismo, de todos los que hayan contestado.
    readonly property var resultados: {
        const salida = []
        for (let i = 0; i < lanzador.length; ++i) {
            const f = lanzador[i].fuente
            const rs = (f && f.resultados) || []
            for (let j = 0; j < rs.length; ++j)
                salida.push(Object.assign({}, rs[j],
                                          { _plugin: lanzador[i].plugin }))
        }
        return salida
    }

    function elegir(resultado) {
        if (!resultado || !resultado._plugin)
            return
        for (let i = 0; i < lanzador.length; ++i)
            if (lanzador[i].plugin === resultado._plugin)
                lanzador[i].fuente.elegido(resultado.id)
    }
}
