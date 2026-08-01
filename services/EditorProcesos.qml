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
    signal abrirFallo(string motivo)
    //  Sin rastro no hay zoom que proponer; el Editor decide reabrir a secas.
    signal proponerFallo()

    function abrir(video, rastro, extra) {
        abridor.command = [guion, "abrir", video,
                           "--rastro", rastro || "",
                           "--guardar", rutaPlan].concat(extra || [])
        abridor.running = true
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
                    procesos.abrirFallo(d && d.motivo ? d.motivo : "fallo")
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
    signal congelarFallo(string motivo)

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
                    procesos.congelarFallo(d && d.motivo ? d.motivo : "congelar")
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
    signal renderFallo(string motivo)

    //  Si el render sigue vivo para este fichero. Es lo que distingue un
    //  proceso que muere sin despedirse de uno que ya contó su final.
    property bool renderActivo: false

    function renderizar(salida, codec, formato, sonoridad) {
        renderActivo = true
        renderizador.ultimoError = ""
        renderizador.command = ["python3", guion, "render",
                                rutaPlan, salida, "--codec", codec,
                                "--formato", formato]
        if (sonoridad)
            renderizador.command = renderizador.command.concat(["--sonoridad"])
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
                    procesos.renderFallo(d.motivo || "fallo")
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
}
