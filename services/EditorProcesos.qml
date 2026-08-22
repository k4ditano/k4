//  Los procesos del editor.
//
//  Esto vivía dentro de services/Editor.qml, y aquel fichero acabó siendo dos
//  cosas trenzadas: el estado del montaje —clips, capas, selección, historial—
//  y diez procesos hablando con tools/editar.py y tools/transcribir.py. Cada
//  bloque `Process` con su parseo, sus reintentos y su red de seguridad, en
//  medio de las funciones del modelo.
//
//  Ahora los procesos están aquí y SOLO los procesos: este fichero lanza
//  mandatos, parsea lo que contestan y lo cuenta por señales. No decide nada:
//  qué hacer con un plan recibido, con un fallo o con una medida es cosa del
//  Editor, que es quien tiene la máquina de estados. Por eso casi todas las
//  señales llevan el dato crudo —incluso null cuando el parseo falla— y es el
//  Editor quien lo interpreta: mover la interpretación aquí habría sido partir
//  la máquina de estados en dos sitios, que es peor que no partir nada.
//
//  La única memoria que guarda es la que pertenece a los procesos: si hay un
//  congelado en marcha, si el render sigue vivo, la última línea de stderr.

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: procesos

    readonly property string guion: Quickshell.shellPath("tools/editar.py")
    readonly property string guionTranscribir:
        Quickshell.shellPath("tools/transcribir.py")

    //  Dónde está el plan. Lo fija el Editor y aquí solo se lee: los procesos
    //  trabajan siempre sobre el plan que esté abierto.
    property string rutaPlan: ""

    // ── abrir y proponer ──────────────────────────────────────────
    signal planRecibido(var d)
    signal abrirFallo(string motivo, string detalle)
    //  Sin rastro no hay zoom que proponer; el Editor decide reabrir a secas.
    signal proponerFallo()

    function abrir(video, rastro, extra) {
        abridor.command = [guion, "abrir", video,
                           "--rastro", rastro || "",
                           "--guardar", rutaPlan].concat(extra || [])
        abridor.running = true
    }

    // ── la onda de una pista ──────────────────────────────────────
    //
    //  En cola y de una en una: un montaje con seis capas de audio lanzaría seis
    //  ffmpeg a la vez y se comería la máquina justo mientras editas, que es el
    //  peor momento. Cada una tarda décimas, así que en fila no se nota.
    //  Con la duración de lo medido: sin ella no se sabe a qué pico
    //  corresponde un instante. Ver `orden_onda` en editar.py.
    signal ondaLista(string clave, var picos, real dur)

    property var colaOndas: []

    function pedirOnda(ruta, pista) {
        colaOndas = colaOndas.concat([{ ruta: ruta, pista: pista }])
        siguienteOnda()
    }

    function siguienteOnda() {
        if (ondeador.running || colaOndas.length === 0)
            return
        const t = colaOndas[0]
        ondeador.clave = t.ruta + "|" + t.pista
        ondeador.command = [guion, "onda", t.ruta,
                            "--pista", String(t.pista), "--puntos", "400"]
        ondeador.running = true
    }

    Process {
        id: ondeador
        property string clave: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                procesos.ondaLista(ondeador.clave,
                                   d && d.picos ? d.picos : [],
                                   d && d.dur ? d.dur : 0)
            }
        }
        //  La cola avanza al MORIR el proceso y no al leer su salida: si se
        //  avanzara antes, `running` seguiría en true y la siguiente se quedaría
        //  esperando para siempre.
        onExited: {
            procesos.colaOndas = procesos.colaOndas.slice(1)
            procesos.siguienteOnda()
        }
    }

    // ── la escoba, para poder OÍRLA ───────────────────────────────
    //
    //  Un botón que solo se nota al renderizar no sirve para decidir: hay que
    //  oír el resultado y ver si te gusta. Pero Qt no sabe aplicar un filtro de
    //  ffmpeg mientras reproduce, así que se le prepara el fichero YA limpio y
    //  reproduce ese. El render sigue filtrando él sobre el original, con la
    //  misma constante, así que lo que oyes es lo que va a salir.
    //
    //  Cuesta poco: un minuto y medio de audio se limpia en algo más de un
    //  segundo. Va en cola de uno en uno, como las ondas, por lo mismo —varios
    //  ffmpeg a la vez compiten con la barra justo cuando estás editando—.
    signal limpiaLista(string clave, string ruta)
    signal limpiaFallo(string clave)

    property var colaLimpias: []

    function pedirLimpia(clave, fichero, pista, salida, escoba, ganancia, prefijo, dentro) {
        colaLimpias = colaLimpias.concat([{ clave: clave, fichero: fichero,
                                            pista: pista, salida: salida,
                                            escoba: !!escoba,
                                            ganancia: ganancia || 1,
                                            prefijo: prefijo || "",
                                            dentro: dentro || "" }])
        siguienteLimpia()
    }

    function siguienteLimpia() {
        if (limpiador.running || colaLimpias.length === 0)
            return
        const t = colaLimpias[0]
        limpiador.clave = t.clave
        limpiador.command = ["python3", guion, "limpiar", t.fichero, t.salida,
                             "--pista", String(t.pista),
                             "--ganancia", String(t.ganancia),
                             "--prefijo", t.prefijo]
                             .concat(t.dentro ? ["--dentro", t.dentro] : [])
                             .concat(t.escoba ? ["--escoba"] : [])
        limpiador.running = true
    }

    Process {
        id: limpiador
        property string clave: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                if (d && d.ok && d.ruta)
                    procesos.limpiaLista(limpiador.clave, d.ruta)
                else
                    procesos.limpiaFallo(limpiador.clave)
            }
        }
        //  La cola avanza al MORIR el proceso, no al leer su salida: la misma
        //  trampa que documenta `ondeador`.
        onExited: {
            procesos.colaLimpias = procesos.colaLimpias.slice(1)
            procesos.siguienteLimpia()
        }
    }

    // ── ponerle nombre al proyecto ────────────────────────────────
    //
    //  Renombrar es cosa de python porque son dos ficheros —el `.k4v` y su
    //  carpeta adjunta— y hay que esquivar los nombres ocupados sin pisar el
    //  montaje de nadie. Aquí solo se pide y se cuenta lo que contesta.
    signal renombrado(string plan)
    signal renombrarFallo(string motivo, string detalle)

    function renombrar(nombre) {
        if (rutaPlan.length === 0)
            return
        renombrador.command = [guion, "renombrar", rutaPlan, nombre]
        renombrador.running = true
    }

    Process {
        id: renombrador
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                if (d && d.ok && d.plan)
                    procesos.renombrado(d.plan)
                else
                    procesos.renombrarFallo(d && d.motivo ? d.motivo : "fallo",
                                            (d && d.detalle) || "")
            }
        }
        stderr: SplitParser {
            onRead: function (l) {
                if (String(l).trim().length > 0)
                    console.warn("editor:", l)
            }
        }
    }

    function proponer(rastro, video, nivel, extra) {
        proponedor.command = [guion, "proponer", rastro,
                              "--video", video,
                              "--guardar", rutaPlan,
                              "--nivel", String(nivel)].concat(extra || [])
        proponedor.running = true
    }

    Process {
        id: abridor
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                if (!d || !d.ok) {
                    procesos.abrirFallo(d && d.motivo ? d.motivo : "fallo",
                                        (d && d.detalle) || "")
                    return
                }
                procesos.planRecibido(d)
            }
        }
    }

    Process {
        id: proponedor
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { return }
                if (!d.ok) {
                    procesos.proponerFallo()
                    return
                }
                procesos.planRecibido(d)
            }
        }
    }

    // ── congelar ──────────────────────────────────────────────────
    //  El plan lo cambia python entero —sacar el fotograma, partir,
    //  recolocar—, así que al acabar hay que RELEERLO; eso lo hace el Editor
    //  al recibir la señal.
    property bool congelando: false

    signal congelado()
    signal congelarFallo(string motivo, string detalle)

    function congelar(t, segundos) {
        congelando = true
        congelador.command = ["python3", guion, "congelar", rutaPlan,
                              String(t), "--dur", String(segundos || 2)]
        congelador.running = true
    }

    Process {
        id: congelador
        stdout: StdioCollector {
            onStreamFinished: {
                procesos.congelando = false
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                if (!d || !d.ok) {
                    procesos.congelarFallo(d && d.motivo ? d.motivo : "congelar",
                                           (d && d.detalle) || "")
                    return
                }
                procesos.congelado()
            }
        }
    }

    // ── silencios ─────────────────────────────────────────────────
    signal silenciosListos(var tramos)
    signal silenciosFallo()

    function buscarSilencios() {
        buscador.command = ["python3", guion, "silencios", rutaPlan]
        buscador.running = true
    }

    Process {
        id: buscador
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                if (!d || !d.ok) {
                    procesos.silenciosFallo()
                    return
                }
                procesos.silenciosListos(d.tramos || [])
            }
        }
    }

    // ── medir ─────────────────────────────────────────────────────
    //  Cuánto dura (y cuánto mide, si es un vídeo) un fichero. La señal
    //  entrega el dato tal cual, null incluido: quién estaba esperando la
    //  medida y qué hace con ella lo sabe el Editor.
    signal medido(var d)

    function medir(ruta) {
        medidor.command = ["python3", guion, "medir", ruta]
        medidor.running = true
    }

    Process {
        id: medidor
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                procesos.medido(d)
            }
        }
    }

    // ── transcribir ───────────────────────────────────────────────
    //  Dos procesos encadenados: comprobar que whisper.cpp está —son 1,4 GB
    //  entre binario y modelo, no se instalan solos— y transcribir de verdad.
    //  El encadenado lo decide el Editor: comprobar bien no significa querer
    //  transcribir ya.
    signal transcripcionComprobada(var d)
    //  Una línea del transcriptor, ya parseada: estados, fallos o el fin con
    //  sus segmentos. Las líneas que no son JSON se tiran aquí.
    signal transcripcionLinea(var d)

    function comprobarTranscripcion() {
        comprobador.running = true
    }

    function transcribir(video, idioma, salida) {
        transcriptor.command = ["python3", guionTranscribir,
                                "hacer", video,
                                "--idioma", idioma,
                                "--salida", salida]
        transcriptor.running = true
    }

    Process {
        id: comprobador
        command: ["python3", procesos.guionTranscribir, "comprobar"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                procesos.transcripcionComprobada(d)
            }
        }
    }

    Process {
        id: transcriptor
        stdout: SplitParser {
            onRead: function (linea) {
                let d = null
                try { d = JSON.parse(linea) } catch (e) { return }
                procesos.transcripcionLinea(d)
            }
        }
    }

    // ── los niveles de las pistas ─────────────────────────────────
    signal nivelesListos(var d)

    function medirNiveles(video) {
        nivelador.command = ["python3", guion, "niveles", video]
        nivelador.running = true
    }

    Process {
        id: nivelador
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                if (d && d.ok)
                    procesos.nivelesListos(d)
            }
        }
    }

    // ── la miniatura ──────────────────────────────────────────────
    signal miniaturaLista(var d)

    function miniatura(t) {
        miniaturero.command = ["python3", guion, "miniatura", rutaPlan,
                               String(t)]
        miniaturero.running = true
    }

    Process {
        id: miniaturero
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                procesos.miniaturaLista(d)
            }
        }
    }

    // ── guardar el plan ───────────────────────────────────────────
    //  El Editor arma el estado a guardar; aquí solo se escribe. `escribiendo`
    //  existe para que el rebote de guardado espere: dos procesos sobre el
    //  mismo fichero acaban con uno pisando al otro.
    readonly property bool escribiendo: escritorPlan.running

    function escribirPlan(datos) {
        escritorPlan.command = ["python3", "-c",
            //  Se parchean las claves que conocemos y se deja el resto como
            //  esté: así lo que añada una fase futura no se pierde por pasar
            //  por aquí. Las pistas de audio cuelgan de la fuente, no del plan,
            //  y por eso van por su propio camino.
            "import json,sys; p=json.load(open(sys.argv[1])); " +
            "d=json.loads(sys.argv[2]); " +
            "p['momentos']=d['momentos']; " +
            //  Una lista vacía significa «el plan aún no ha terminado de
            //  cargarse», no «quítale el audio» ni «quítale los trozos»: no hay
            //  forma de borrar una pista, solo de silenciarla, ni de dejar la
            //  línea sin ningún clip. Sin estos `or`, un guardado que llegara
            //  antes que la carga dejaba el plan vacío para siempre.
            "p['fuentes'][0]['pistas']=d['pistas'] or p['fuentes'][0]['pistas']; " +
            "p['clips']=d['clips'] or p['clips']; " +
            //  Las capas SÍ se escriben aunque estén vacías, al revés que las
            //  otras: no tener ninguna es un estado legítimo, y con el `or` no
            //  habría forma de quitar la última.
            "p['capas']=d['capas']; " +
            "p['bandas']=d['bandas']; " +
            "p['transcripcion']=d['transcripcion']; " +
            "p['clics']=d['clics']; " +
            "p['fundidos']=d['fundidos']; " +
            "p['transicion']=d['transicion']; " +
            "p['marcadores']=d['marcadores']; " +
            "json.dump(p, open(sys.argv[1],'w'), ensure_ascii=False, indent=1)",
            rutaPlan, datos]
        escritorPlan.running = true
    }

    Process {
        id: escritorPlan
        // La trayectoria depende del plan, así que se rehace cuando el plan ya
        // está escrito en disco y no antes.
        onExited: recalcular.restart()
    }

    // ── la trayectoria de la cámara ───────────────────────────────
    signal camaraLista(var d)

    //  Al editar hay que rehacer la trayectoria, pero no a cada tecla: si
    //  mantienes pulsada una flecha se lanzarían veinte procesos. Un respiro
    //  corto y solo se calcula la última.
    function recalcularCamara() {
        recalcular.restart()
    }

    Timer {
        id: recalcular
        interval: 180
        onTriggered: {
            if (procesos.rutaPlan.length === 0)
                return
            camarero.command = ["python3", procesos.guion, "camara",
                                procesos.rutaPlan]
            camarero.running = true
        }
    }

    Process {
        id: camarero
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(this.text) } catch (e) { }
                if (d && d.ok)
                    procesos.camaraLista(d)
            }
        }
    }

    // ── renderizar ────────────────────────────────────────────────
    signal renderProgreso(real progreso)
    signal renderFin(string ruta)
    signal renderFallo(string motivo, string detalle)

    //  Si el render sigue vivo para este fichero. Es lo que distingue un
    //  proceso que muere sin despedirse de uno que ya contó su final.
    property bool renderActivo: false

    function renderizar(salida, codec, formato, sonoridad, vertical) {
        renderActivo = true
        renderizador.ultimoError = ""
        renderizador.command = ["python3", guion, "render",
                                rutaPlan, salida, "--codec", codec,
                                "--formato", formato]
        if (sonoridad)
            renderizador.command = renderizador.command.concat(["--sonoridad"])
        if (vertical)
            renderizador.command = renderizador.command.concat(["--vertical"])
        renderizador.running = true
    }

    Process {
        id: renderizador

        //  La última línea de error, para que un traceback de python o un
        //  fallo de ffmpeg no muera en silencio: es lo que se enseña si el
        //  proceso acaba sin haber contado nada por stdout.
        property string ultimoError: ""

        stdout: SplitParser {
            onRead: function (linea) {
                let d = null
                try { d = JSON.parse(linea) } catch (e) { return }
                if (d.progreso !== undefined)
                    procesos.renderProgreso(d.progreso)
                if (d.estado === "fin" && d.ruta) {
                    procesos.renderActivo = false
                    procesos.renderFin(d.ruta)
                }
                if (d.ok === false) {
                    procesos.renderActivo = false
                    procesos.renderFallo(d.motivo || "fallo", d.detalle || "")
                }
            }
        }

        stderr: SplitParser {
            onRead: function (linea) {
                const l = String(linea).trim()
                if (l.length > 0)
                    renderizador.ultimoError = l.substring(0, 200)
            }
        }

        //  Si el guion muere sin despedirse —traceback, ffmpeg ausente, un
        //  kill— la interfaz se quedaba en «renderizando» PARA SIEMPRE: nadie
        //  limpiaba el estado. El veredicto de salida es la red de seguridad.
        onExited: function (code) {
            if (!procesos.renderActivo)
                return
            procesos.renderActivo = false
            procesos.renderFallo(renderizador.ultimoError.length > 0
                ? renderizador.ultimoError
                : "el renderizador terminó sin avisar (código " + code + ")")
        }
    }

    // ── la locución ───────────────────────────────────────────────
    //
    //  Ponerle voz a un vídeo que ya está montado: se mira la previa y se
    //  habla encima. Es lo único del editor que GRABA en vez de editar, y por
    //  eso lo hace ffmpeg directamente y no `editar.py` —no hay plan que tocar
    //  hasta que la voz existe—.
    //
    //  El orden importa y no es el obvio. Primero se abre el micro, y solo
    //  cuando ffmpeg dice que ya está corriendo se manda reproducir: al revés,
    //  el vídeo llevaría medio segundo andando antes de que nadie escuchara, y
    //  ese medio segundo no hay forma de recuperarlo después. Por eso hay una
    //  señal para «micro abierto» y no se arranca la previa hasta oírla.
    //  Lleva CUÁNTO había capturado ya el micro en ese instante. Ver abajo.
    signal vozAbierta(real capturado)
    signal vozCerrada(int codigo, string queja)

    readonly property bool grabandoVoz: grabadorVoz.running

    //  La carpeta adjunta puede no existir todavía —se crea cuando hace falta
    //  escribir algo en ella, y una locución puede ser lo primero—, así que se
    //  asegura antes. Con un `mkdir` propio y no con `sh -c 'mkdir … && ffmpeg'`:
    //  por ahí entrarían las comillas, y las rutas de esta casa llevan espacios
    //  y tildes («Pa twitter.k4»). Encadenar dos procesos no tiene ese problema.
    function grabarVoz(ruta, dispositivo, carpeta) {
        grabadorVoz.queja = ""
        //  `-y` porque el nombre lo elige el Editor y ya se ha asegurado de
        //  que no pisa nada; sin él, ffmpeg se queda esperando una respuesta
        //  que nadie va a escribir y la grabación no arranca nunca.
        grabadorVoz.primerAviso = true
        //  `-progress` no es un adorno de depuración: es lo que quita la
        //  incógnita.
        //
        //  «El proceso ha arrancado» y «el micro está capturando» no son lo
        //  mismo: entre una cosa y otra ffmpeg abre PulseAudio y eso tarda
        //  —medido en este equipo: entre 160 y 250 ms de arranque más cierre—.
        //  Arrancando el vídeo al nacer el proceso, la voz caía como un décimo
        //  de segundo ADELANTADA sobre lo que estabas mirando, y ese número no
        //  se puede observar desde fuera ni vale restar uno medido un martes.
        //
        //  Con `-progress`, ffmpeg dice él mismo cuánto audio lleva metido. Se
        //  espera al primer parte, se avisa con ESE número, y ahí se sabe
        //  exactamente qué trozo del fichero es «antes de que el vídeo se
        //  moviera». `-stats_period` lo baja de medio segundo a cincuenta
        //  milisegundos: es lo que se tarda en empezar a ver el vídeo.
        grabadorVoz.command = ["ffmpeg", "-v", "error", "-y",
                               "-f", "pulse", "-i", dispositivo,
                               "-c:a", "aac", "-b:a", "160k",
                               "-progress", "pipe:1", "-nostats",
                               "-stats_period", "0.05", ruta]
        if (!carpeta || carpeta.length === 0) {
            grabadorVoz.running = true
            return
        }
        abrecarpeta.command = ["mkdir", "-p", carpeta]
        abrecarpeta.running = true
    }

    Process {
        id: abrecarpeta
        //  Salga bien o mal se sigue: si la carpeta no se pudo crear, quien lo
        //  dirá con detalle es ffmpeg al no poder escribir, y ese motivo es
        //  mejor que uno inventado aquí.
        onExited: grabadorVoz.running = true
    }

    //  Por las buenas, con SIGINT: un m4a al que no se le escribe el índice
    //  del final no lo abre nadie, y ahí se habría ido la toma entera.
    function pararVoz() {
        if (grabadorVoz.running)
            grabadorVoz.signal(2)
    }

    Process {
        id: grabadorVoz
        property string queja: ""
        property bool primerAviso: true

        //  Y NO en `onStarted`: eso es el proceso naciendo, que es justo lo que
        //  no sirve. Ver el comentario de `grabarVoz`.
        stdout: SplitParser {
            onRead: function (linea) {
                if (!grabadorVoz.primerAviso)
                    return
                const m = String(linea).match(/^out_time_us=(-?\d+)/)
                if (!m)
                    return
                grabadorVoz.primerAviso = false
                //  Al principio ffmpeg puede dar un tiempo negativo; eso es
                //  «todavía nada», no un número que restar.
                procesos.vozAbierta(Math.max(0, parseInt(m[1], 10) / 1000000))
            }
        }

        stderr: SplitParser {
            onRead: function (linea) {
                const l = String(linea).trim()
                if (l.length > 0 && grabadorVoz.queja.length === 0)
                    grabadorVoz.queja = l.substring(0, 200)
            }
        }

        //  ffmpeg sale con 255 cuando lo paras con SIGINT, y eso aquí es el
        //  final normal de una toma: quien decide si hay voz o no es el
        //  Editor, mirando si el fichero mide algo.
        onExited: function (codigo) {
            procesos.vozCerrada(codigo, grabadorVoz.queja)
        }
    }
}
