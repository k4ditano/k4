//  El viaje: la barra se parte en dos y cada mitad recorre su borde hasta que
//  las dos se juntan abajo.
//
//  Lo que hace que se separen y se junten COMO AGUA no es la animación, es un
//  filtro: los dos trozos se pintan en blanco sobre una capa que nadie ve, se
//  desenfoca, y de ese desenfoque se recorta el alfa por un umbral duro. Donde
//  dos manchas desenfocadas se acercan, sus alfas se suman, cruzan el umbral
//  antes de que las siluetas lleguen a tocarse y aparece el CUELLO. Al alejarse
//  el cuello adelgaza y se rompe solo. Es la receta de los metaballs, y sale
//  sin escribir un shader: los de Qt6 van precompilados y un plugin no puede
//  traerlos.
//
//  El color no sale del desenfoque —eso pintaría un degradado por muy duro que
//  fuera el corte— sino de una lámina de color sólido a la que el alfa
//  recortado solo le dice DÓNDE.
//
//  Medido: con `blurMax` a 64 y el umbral en 0.35, el cuello aguanta hasta unos
//  25 px de separación. Estrecho, pero es justo la distancia a la que están los
//  trozos al partirse y al reencontrarse.
//
//  Esta ventana no reserva sitio y solo existe mientras algo viaja: pasa por
//  encima de las ventanas sin recolocar nada.

import QtQuick
import QtQuick.Shapes
import K4 as K4

K4.Ventana {
    id: escena

    required property var plugin

    nombre: "k4-dual-viaje"
    encima: true

    //  En la pantalla de la barra que se va, no en la que el compositor
    //  prefiera: si no, el viaje se pinta en un monitor y el dock en otro.
    pantalla: escena.plugin.pantalla

    //  Existe SOLO mientras haya trozos en pantalla.
    //
    //  La tuve siempre puesta —primero por las capas del filtro de fusión,
    //  después para que el compositor no la desvaneciera al entrar— y salió
    //  caro: es una superficie a pantalla completa por ENCIMA de todo, el
    //  dock incluido, así que se quedaba delante todo el rato y el dock
    //  dejaba de responder al ratón. Un desvanecido de entrada se nota mucho
    //  menos que un dock que no se puede pulsar.
    visible: escena.plugin.trozosFuera

    //  No captura NADA. Ojo con dejarlo en `null`: K4.Ventana hace
    //  `mask: zonaActiva ? region : null`, y un mask nulo en una capa a pantalla
    //  completa se queda todos los clics del escritorio. Con una zona de 0×0 la
    //  región existe y está vacía, que es lo que se quiere.
    //  Se salta las reservas ajenas: tiene que pintar SOBRE la franja de la
    //  barra, no debajo. Mientras el viaje dura, esa franja sigue reservada
    //  —para que el escritorio no pegue el salto—, y sin esto la ventana
    //  empezaba justo donde acaba la barra: los trozos salían 34 px más abajo,
    //  despegados del borde de la pantalla. Medido: `y: 34-67` en vez de 0-33.
    reserva: -1

    zonaActiva: nada

    Item { id: nada; width: 0; height: 0 }

    //  0 arriba (en la barra) · 1 abajo (juntas).
    property real t: 0

    //  ── a dónde van los trozos ──────────────────────────────────
    //
    //  El destino lo pone la ESCENA y no el plugin porque hace falta el tamaño
    //  de la pantalla y el plugin solo guarda su nombre. Aquí la ventana ES la
    //  pantalla, así que sale de `width`/`height` sin preguntarle a nadie.
    //
    //  Sale del mismo `centroDock()` y del mismo ancho que ancla el muelle: si
    //  discreparan, los trozos aterrizarían a un palmo de donde nace el dock y
    //  se vería el salto.
    //
    //  Y a RAS del canto —a medio grosor—, que es como iban por el borde: no
    //  centrados en lo hondo que sea el dock.
    readonly property real ras: K4.Tema.altoPlegado / 2

    readonly property point centroDock: {
        const p = escena.plugin
        const largo = p.dockVertical ? escena.height : escena.width
        const c = p.centroDock(largo, p.anchoDock)
        if (p.ladoDock === "arriba")
            return Qt.point(c, escena.ras)
        if (p.ladoDock === "abajo")
            return Qt.point(c, escena.height - escena.ras)
        if (p.ladoDock === "izquierda")
            return Qt.point(escena.ras, c)
        return Qt.point(escena.width - escena.ras, c)
    }

    //  Y las dos mitades del dock, separadas por su eje largo igual que se
    //  separaron arriba. El trozo de la izquierda va al extremo que le pilla
    //  más cerca —el de menos coordenada— y por eso los dos caminos no se
    //  cruzan por mucho que vayan los dos por el mismo costado.
    readonly property point destinoIzq: escena.plugin.dockVertical
        ? Qt.point(centroDock.x, centroDock.y - escena.plugin.largoTrozo / 2)
        : Qt.point(centroDock.x - escena.plugin.largoTrozo / 2, centroDock.y)

    readonly property point destinoDer: escena.plugin.dockVertical
        ? Qt.point(centroDock.x, centroDock.y + escena.plugin.largoTrozo / 2)
        : Qt.point(centroDock.x + escena.plugin.largoTrozo / 2, centroDock.y)

    // ── los dos trozos ──────────────────────────────────────────
    Gota {
        id: izquierda
        lado: -1
        largoTrozo: escena.plugin.largoTrozo
        salida: escena.plugin.salidaIzq
        destino: escena.destinoIzq
        t: escena.t
    }

    Gota {
        id: derecha
        lado: 1
        largoTrozo: escena.plugin.largoTrozo
        salida: escena.plugin.salidaDer
        destino: escena.destinoDer
        t: escena.t
    }

    // ── el cuello: lo que hace que se separen y se junten como agua ──
    //
    //  Cuando dos gotas se despegan no se cortan en seco: estiran un puente que
    //  adelgaza hasta romperse. Eso es lo que dibuja esto — un lazo entre los
    //  cantos que se miran, con los lados CÓNCAVOS (dos Béziers tirando hacia
    //  dentro), que es lo que da la cintura de reloj de arena.
    //
    //  Se probó antes con el filtro de metaballs de verdad —desenfocar y cortar
    //  el alfa por un umbral— y funciona en una prueba suelta, pero dentro de
    //  esta ventana la cadena de capas no llegaba a pintar. Dibujarlo a mano es
    //  determinista, no cuesta una capa por fotograma, y además deja los trozos
    //  con su silueta NÍTIDA de barra: el desenfoque se comía las esquinas
    //  invertidas, que son justo lo que los hace parecer un trozo de la barra.
    //  Medio grosor DEL MOMENTO: la pieza se afina al correr, así que un valor
    //  fijo dejaría el puente descolgado.
    readonly property real medio: izquierda.grosor / 2

    //  Y lo hondo que llega el lomo de la pieza justo donde el puente se le
    //  mete. El puente nace con ese fondo, no con el grosor entero: si no,
    //  asoma por debajo de la pieza y se ve como un puente pegado.
    readonly property real fondo: izquierda.fondoA(escena.solape)

    //  Solo tiene sentido con los dos tumbados y a la misma altura: al partirse
    //  arriba y al reencontrarse abajo. Bajando por los laterales están en
    //  bordes opuestos y no hay nada que unir.
    readonly property bool juntables: izquierda.tumbado && derecha.tumbado
        && Math.abs(izquierda.ahora.y - derecha.ahora.y) < 2

    //  El hueco REAL entre los cantos que se miran.
    readonly property real hueco: (derecha.ahora.x - escena.plugin.largoTrozo / 2)
        - (izquierda.ahora.x + escena.plugin.largoTrozo / 2)

    //  Pero el puente se dibuja METIÉNDOSE en los dos trozos, y bastante.
    //
    //  El canto que mira al otro no es una línea recta: es el ala (16) y luego
    //  el arco de la esquina de abajo (17), así que la silueta se retira 33 px
    //  entre el borde de la pantalla y el filo interior. Con un solape corto,
    //  el puente asomaba por debajo de esa curva y dejaba un escalón — la
    //  separación que se veía. Metiéndose más de esos 33, el puente nace ya
    //  dentro de la masa.
    //
    //  Y encaja fino por una propiedad del propio trazado: el arco de abajo
    //  acaba TANGENTE al borde inferior, así que un puente cuya base es esa
    //  misma línea empalma sin ángulo.
    readonly property real solape: 36
    readonly property real cantoIzq: izquierda.ahora.x
        + escena.plugin.largoTrozo / 2 - escena.solape
    readonly property real cantoDer: derecha.ahora.x
        - escena.plugin.largoTrozo / 2 + escena.solape

    //  Hasta dónde aguanta el puente antes de romperse.
    //
    //  Eran 88 y aguantaba de más: con los trozos ya claramente en marcha
    //  seguía habiendo un hilo negro cruzando el medio, que abajo —donde
    //  acababa de estar el dock— parecía un resto suyo. Con 46 el reparto se
    //  consuma en los primeros ~270 ms y el resto del viaje va limpio: primero
    //  se divide, después se mueve, y no se ven las dos cosas a la vez.
    readonly property real alcance: 46

    //  El grosor de la cintura: entero cuando se tocan, cero al romperse. El
    //  exponente hace que adelgace deprisa al final, que es como cede el agua
    //  —aguanta, aguanta y de golpe se parte— y no de forma lineal.
    readonly property real cintura: {
        if (!escena.juntables || escena.hueco >= escena.alcance)
            return 0
        const k = Math.max(0, 1 - Math.max(0, escena.hueco) / escena.alcance)
        return escena.fondo * Math.pow(k, 2.0)
    }

    Shape {
        //  Vive exactamente mientras vivan los trozos, ni más ni menos.
        //
        //  Atado a `viajando` se apagaba en cuanto terminaba el viaje, y ahí se
        //  destapaba un feo: dos trozos pegados NO forman una barra. Cada uno
        //  lleva su ala y su esquina redondeada también en el canto que mira al
        //  otro, así que al juntarse dejaban muescas arriba y abajo — dos
        //  jorobas en vez de una barra, justo el rato que se quedan tapando el
        //  relevo. Con el puente puesto, esas muescas quedan rellenas.
        //
        //  Y atado solo al hueco se quedaba pintado para siempre, que fue el
        //  tocho negro de antes. La condición buena es la de los trozos.
        //
        //  Se corta en 3 px de cintura, no en 0: por debajo de eso ya no es un
        //  puente, es una hebra colgando entre dos trozos que hace rato que se
        //  separaron. Cortar antes es lo que hace que PAREZCA que se rompe.
        visible: izquierda.mostrando
            && escena.cintura > 3 && escena.hueco > -escena.solape

        //  Con tamaño, y SIN capa propia.
        //
        //  El trazado va en coordenadas absolutas de la ventana, así que este
        //  item no necesitaba medir nada... hasta que le puse `layer.enabled`
        //  para suavizar: una capa de 0×0 en el origen es lo que dejaba un
        //  pegote negro suelto arriba a la izquierda cada vez que el puente se
        //  encendía. Ocupando la ventana entera el problema desaparece, y el
        //  MSAA sobra: aquí no hay esquinas invertidas, solo dos curvas que el
        //  propio Shape ya suaviza.
        anchors.fill: parent
        antialiasing: true

        ShapePath {
            id: puente
            fillColor: K4.Tema.fondo
            strokeWidth: 0
            strokeColor: "transparent"

            readonly property real y0: izquierda.ahora.y
            readonly property bool arriba: y0 < escena.height / 2

            //  El canto pegado a la pantalla, y hacia dónde crece el puente.
            readonly property real ras: arriba ? y0 - escena.medio
                                               : y0 + escena.medio
            readonly property real signo: arriba ? 1 : -1

            //  Los dos extremos llegan justo al fondo del lomo de la pieza, y
            //  el centro a la cintura —que se va a cero al romperse—. El x2 del
            //  control sale de la cuadrática: pasa por (inicio + 2·C + fin)/4.
            readonly property real extremo: ras + signo * escena.fondo
            readonly property real mando: ras
                + signo * (2 * escena.cintura - escena.fondo)

            startX: escena.cantoIzq
            startY: puente.ras

            PathLine { x: escena.cantoDer; y: puente.ras }
            PathLine { x: escena.cantoDer; y: puente.extremo }
            PathQuad {
                x: escena.cantoIzq
                y: puente.extremo
                controlX: (escena.cantoIzq + escena.cantoDer) / 2
                controlY: puente.mando
            }
            PathLine { x: escena.cantoIzq; y: puente.ras }
        }
    }

    // ── el reparto del tiempo ────────────────────────────────────
    NumberAnimation {
        id: viaje
        target: escena
        property: "t"

        //  Dos segundos largos y una curva con las puntas suaves.
        //
        //  La curva no es estética: es lo que hace VISIBLE la fusión. El cuello
        //  solo existe mientras los trozos están a menos de ~25 px, y con una
        //  curva plana esa distancia se cruza en dos fotogramas. Con InOutCubic
        //  los primeros 300 ms cubren unos 38 px de recorrido, así que separarse
        //  —y volver a juntarse— dura lo suficiente para verlo.
        duration: 2100
        easing.type: Easing.InOutCubic

        onFinished: {
            //  Primero se avisa —y con eso empieza a crecer el dock, o vuelve
            //  la barra— y los trozos se quedan un rato MÁS, tapando ese
            //  arranque.
            //
            //  Sin esto el relevo era un salto: los trozos desaparecían y lo
            //  que los sustituye empezaba a crecer desde cero a la vista. Como
            //  el dock nace justo del tamaño de los dos trozos juntos, si ellos
            //  siguen dibujados encima el cambio de manos no se ve: cuando se
            //  quitan, debajo ya hay masa.
            escena.plugin.viajeTerminado()
            relevo.restart()
        }
    }

    Timer {
        id: relevo
        interval: 640
        onTriggered: {
            izquierda.parar()
            derecha.parar()
        }
    }

    Connections {
        target: escena.plugin

        //  Solo con SU efecto puesto. Los modos son los mismos para los dos, y
        //  sin esto la escena del viaje arrancaba su animación de dos segundos
        //  por debajo de la gota —invisible, porque la ventana no existe, pero
        //  llamando a `viajeTerminado` cuando le tocaba a ella— y el dock se
        //  ponía dos veces, la segunda un segundo tarde.
        enabled: escena.plugin.efectoActivo === "viaje"

        //  Los trozos salen cuando el plugin dice, no cuando cambia el modo:
        //  en la recogida esperan a que el dock esté casi encima de ellos.
        function onTrozosFueraChanged() {
            if (!escena.plugin.trozosFuera
                || escena.plugin.modo !== "recogiendo")
                return
            relevo.stop()
            escena.t = 1
            izquierda.arrancar()
            derecha.arrancar()
        }

        //  Tres momentos, no dos: bajar, ponerse abajo mientras el dock se
        //  recoge, y subir. El de en medio no mueve nada —solo saca los trozos
        //  y los deja quietos en el suelo— pero es lo que hace que el dock se
        //  desinfle SOBRE ellos en vez de dejar un hueco a la vista.
        function onModoChanged() {
            const m = escena.plugin.modo

            if (m === "bajando") {
                //  Si se vuelve a disparar antes de que venza el relevo, los
                //  trozos ya están en pantalla y no hay que quitarlos.
                relevo.stop()
                escena.t = 0
                izquierda.arrancar()
                derecha.arrancar()
                viaje.to = 1
                viaje.restart()

            //  Ojo: en "creciendo" NO se quitan los trozos.
            //
            //  Se probó a quitarlos ahí, dando por hecho que la barra ya estaba
            //  puesta con su tamaño de empalme. No lo está: `ponerAncho` fija la
            //  property del plugin al instante, pero el ancho de la island lo
            //  anima el HOST igualmente, así que crece desde cero. Quitándolos,
            //  quedaba un hueco de nada entre que se van y la barra llega — el
            //  parpadeo. Los tapa el relevo, como abajo.

            } else if (m === "subiendo") {
                //  Los trozos ya están puestos desde la recogida: aquí solo se
                //  les da salida.
                viaje.to = 0
                viaje.restart()
            }
        }
    }
}
