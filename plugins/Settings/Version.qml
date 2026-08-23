//  ¿Hay k4 nuevo?
//
//  El actualizador es `./instalar` y lleva ahí desde el principio —hace el
//  `git pull`, repasa los paquetes y los atajos y ofrece reiniciar la barra—,
//  pero la barra no lo mencionaba nunca: te enterabas de que había versión
//  nueva si se te ocurría lanzarlo a mano. Esto es la mitad que faltaba: mirar,
//  y decirlo donde se mira todo lo demás.
//
//  Se averiguan TRES cosas y las tres hacen falta:
//
//   · en qué commit estás, que es lo que contesta «¿qué versión tengo?» —hasta
//     ahora no se enseñaba en ninguna parte—;
//   · cuántos commits te lleva `origin`, que es la novedad de verdad;
//   · y si tienes cambios sin guardar. Esto último no es un detalle: con el
//     árbol sucio `./instalar` NO toca el código a propósito —perder trabajo de
//     alguien por «actualizar» es exactamente lo que no puede pasar— así que
//     enseñar «hay novedad» sin decir eso es mandar a alguien a pulsar un botón
//     que no va a hacer nada, y encima sin explicar por qué.
//
//  Todo en UN proceso y no en cuatro: son cuatro órdenes de git encadenadas,
//  cada una con su fallo posible, y coordinarlas desde QML es cuatro `onSalida`
//  con una máquina de estados por el medio. En `sh` son seis líneas y el fallo
//  de cada una se contesta ahí mismo.

import QtQuick
import K4 as K4

QtObject {
    id: version

    //  Lo que se ha averiguado.
    //
    //  `detras` en -1 es «todavía no se sabe», que NO es lo mismo que 0: con
    //  cero se dice «al día» y con -1 no se dice nada, que es lo honesto
    //  mientras no se haya podido mirar.
    property string commit: ""
    property int detras: -1
    property bool sucio: false

    //  Y por qué no se sabe, cuando no se sabe. Vacío es «se sabe».
    //
    //   "sin-git"     no es un clon de git: instalado a mano o descomprimido.
    //   "sin-remoto"  la rama no sigue a ninguna, así que no hay con qué comparar.
    //   "sin-red"     no se ha podido traer nada. Lo que se enseñe entonces sale
    //                 de la última vez que hubo red, y hay que decirlo.
    property string pega: ""

    property bool mirando: false

    readonly property bool hayNovedad: version.detras > 0

    //  Cuándo se miró por última vez, para no salir a la red cada vez que se
    //  abren los Ajustes. En memoria y no guardado a disco: al reiniciar la
    //  barra volver a mirar es justo lo que se quiere, no lo que hay que evitar.
    property double ultima: 0
    readonly property int gracia: 10 * 60 * 1000

    function mirar(forzando) {
        if (version.mirando)
            return
        if (!forzando && version.ultima > 0
                && Date.now() - version.ultima < version.gracia)
            return
        version.mirando = true
        ojeada.running = true
    }

    //  Y actualizar es lanzar el instalador donde se pueda ver.
    //
    //  En una terminal y no en un proceso callado a propósito: `./instalar`
    //  pregunta —si reinicia la barra, si instala lo que falta— y puede pedir la
    //  contraseña al gestor de paquetes. Con k4term además sale DENTRO de la
    //  island, así que actualizar la barra se ve en la propia barra.
    function actualizar() {
        K4.Terminal.ejecutar("cd " + JSON.stringify(K4.Paths.raiz)
                             + " && ./instalar;" + K4.Terminal.cierre)
    }

    property K4.Process ojeada: K4.Process {
        //  `$0` es el nombre y `$1` el primer argumento: por eso el "sh" suelto
        //  entre el guion y la raíz. Es el mismo apaño que usa el modo dual para
        //  lanzar aplicaciones sin heredar el directorio de la barra.
        command: ["sh", "-c", [
            'cd "$1" 2>/dev/null || exit 0',
            'c=$(git rev-parse --short HEAD 2>/dev/null) || { echo pega=sin-git; exit 0; }',
            'echo "commit=$c"',
            '[ -n "$(git status --porcelain 2>/dev/null)" ] && echo sucio=1',
            //  Sin rama de seguimiento no hay nada con lo que comparar, y
            //  `rev-list HEAD..@{u}` fallaría en silencio dejando un -1 sin
            //  explicación. Se pregunta antes para poder decir cuál es la pega.
            'git rev-parse --abbrev-ref "@{u}" >/dev/null 2>&1 || { echo pega=sin-remoto; exit 0; }',
            //  Y si la red falla NO se sale: el `rev-list` de después sigue
            //  valiendo contra lo último que se trajo. Se contesta con la cuenta
            //  vieja y con la pega puesta, que es más útil que no contestar.
            'git fetch --quiet 2>/dev/null || echo pega=sin-red',
            'n=$(git rev-list --count "HEAD..@{u}" 2>/dev/null) && echo "detras=$n"'
        ].join("\n"), "sh", K4.Paths.raiz]

        //  En inglés, que es como se parsea igual en cualquier máquina.
        environment: ({ "LC_ALL": "C" })

        onSalida: function (texto) {
            let c = "", d = -1, su = false, pe = ""
            const lineas = String(texto).split("\n")
            for (let i = 0; i < lineas.length; ++i) {
                const l = lineas[i].trim()
                if (l.indexOf("commit=") === 0)
                    c = l.substring(7)
                else if (l.indexOf("detras=") === 0)
                    d = parseInt(l.substring(7), 10)
                else if (l === "sucio=1")
                    su = true
                else if (l.indexOf("pega=") === 0)
                    pe = l.substring(5)
            }
            version.commit = c
            version.detras = isNaN(d) ? -1 : d
            version.sucio = su
            version.pega = pe
        }

        //  El sello se pone al TERMINAR y no al leer: un proceso que muere sin
        //  escribir nada no emite `salida`, y sin sello la gracia no corre y se
        //  reintentaría en cada apertura de los Ajustes.
        onTerminado: function (codigo) {
            version.mirando = false
            version.ultima = Date.now()
        }
    }
}
