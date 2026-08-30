//  Modo dual: arriba una barra, abajo un dock, y el cambio de una a otro.
//
//  Hay dos maneras de contarlo y las dos están aquí:
//
//   · el VIAJE — la barra se pone negra y se encoge hasta desaparecer, y de sus
//     dos extremos salen dos gotas que corren cada una por su borde de pantalla
//     hasta juntarse abajo, donde se estiran y montan el dock (Escena.qml);
//   · la GOTA — la barra se queda quieta y de su canto de abajo se descuelga una
//     gota que cae, se estrella contra el borde y se extiende hasta ser el dock
//     (Caida.qml).
//
//  Y de fondo, si la barra se va o se queda: «las dos a la vez» deja la de
//  arriba puesta y suma el dock abajo, que es lo que la gota cuenta mejor.
//
//  Que la barra de arriba desaparezca se consigue COGIENDO la island con
//  prioridad alta y pidiéndola de tamaño cero: no hay que tocar el host para
//  nada, es la misma facultad que usa el editor de vídeo para pasar de tira a
//  pantalla grande.
//
//      quickshell ipc -p <shell.qml> call k4.dual toggle

import QtQuick
import K4 as K4

K4.Plugin {
    id: self

    name: "dual"
    title: K4.Idioma.t("Modo dual")

    //  "barra" · "encogiendo" · "bajando" · "dock" ·
//  "recogiendo" · "subiendo" · "creciendo"
    //
    //  La salida es la entrada al revés, y por eso hay un modo de más. Al bajar
    //  el orden es: viajar, juntarse, y ENTONCES crecer el dock. Al subir tiene
    //  que ser al espejo: encogerse el dock primero, y solo después salir de
    //  viaje. Haciendo las dos cosas a la vez —que es como estaba— el dock se
    //  desinflaba mientras los trozos ya se iban, y por el medio se veía un
    //  hueco negro que no es nada.
    property string modo: "barra"

    readonly property bool viajando: modo === "bajando" || modo === "subiendo"

    //  La pieza que hace el relevo —los dos trozos del viaje, o la gota— está
    //  en pantalla también mientras el dock se recoge encima de ella, aunque no
    //  se mueva — pero NO desde el principio.
    //
    //  Sacándolos al empezar la recogida se pintaban sobre el dock todavía
    //  entero (van en una capa por encima), y como son negros tapaban la mitad
    //  de abajo de los iconos: parecía que salía una gota encima del dock antes
    //  de que pasara nada. Esperando a que el dock esté casi recogido, aparecen
    //  cuando ya miden lo mismo que él y no se ve el relevo.
    //  La gota espera MÁS que los trozos: acaba con el tamaño exacto de la
    //  semilla del dock, así que si sale con el dock todavía a un 18 % este le
    //  asoma por los dos lados y luego se le mete debajo. Los trozos son más
    //  anchos que la semilla y no tienen ese problema.
    readonly property bool piezasFuera: viajando
        || (modo === "recogiendo"
            && muelle.despliegue < (esGota ? 0.06 : 0.18))

    //  Y cuál de las dos escenas la pinta. La otra no existe: son ventanas
    //  propias a pantalla completa, y una que se quede puesta «por si acaso» ya
    //  se llevó por delante el ratón del dock una vez (ver Escena.qml).
    readonly property bool trozosFuera: piezasFuera && !esGota
    readonly property bool gotaFuera: piezasFuera && esGota

    //  ── el ancho de la barra mientras la tenemos cogida ──────────
    //
    //  Se anima AQUÍ y no se deja al host a propósito. Soltando la island sin
    //  más, la barra reaparecía con la animación del host —440 ms con rebote— y
    //  desde CERO, que no se parece en nada a cómo se pone el dock abajo. Con
    //  la misma curva que el dock (760 ms, sin rebote) y saliendo del tamaño de
    //  los trozos, arriba y abajo hacen por fin lo mismo.
    //
    //  16 es el radio del ala: `K4.Isla.rect` mide la island CON alas y
    //  `islandWidth` va sin ellas.
    readonly property int ala: 16
    property real anchoBarra: 0
    //  Para poner el ancho de golpe cuando hay que empalmar sin que se note.
    property bool suave: false

    islandWidth: Math.max(0, Math.round(anchoBarra))

    //  Más corta que la del dock, y a propósito.
    //
    //  El dock se recoge de 470 a 130 y la barra solo de 208 a 130: con la
    //  misma duración, arriba se quedaba casi tres cuartos de segundo sin
    //  aparente pasar nada antes de partirse, mientras que abajo la división se
    //  ve a los 500 ms —en cuanto los trozos asoman sobre el dock ya recogido—.
    //  Recorrido más corto, tiempo más corto.
    Behavior on anchoBarra {
        enabled: self.suave
        NumberAnimation { duration: 440; easing.type: Easing.InOutCubic }
    }

    //  Lo que medía la barra al empezar, y lo que miden los dos trozos juntos.
    property real anchoLleno: 0
    readonly property real anchoSemilla: largoTrozo * 2 - ala * 2

    //  Lo ANCHO QUE ES EL DOCK a lo largo de su borde, que no es lo ancho que
    //  era la barra: sale del número de aplicaciones, no del rect de la island.
    //
    //  Hace falta fuera del muelle porque el dock se coloca por ese ancho —«al
    //  0 %» quiere decir «su borde izquierdo contra el canto»— y quien tiene
    //  que aterrizar en el mismo sitio es el viaje. Con el ancho de la barra en
    //  su lugar, centrado daba igual —los dos son `largo / 2`— pero corrido a
    //  un extremo los trozos caían donde el dock NO estaba, y el relevo pegaba
    //  el salto que se veía.
    readonly property real anchoDock: muelle.anchoLleno
    readonly property bool fuera: modo !== "barra"

    //  «Ya está puesto abajo»: el dock ha llegado Y ha terminado de crecer.
    //  Es el instante en que el dock se queda su sitio, y por tanto el único
    //  momento en que tiene sentido soltar el de arriba.
    readonly property bool asentado: modo === "dock" && muelle.despliegue > 0.98

    //  Que el host NO le guarde el sitio a la barra: solo cuando el dock ya se
    //  ha quedado el suyo abajo. Así el escritorio se recoloca una vez, al
    //  final, y no al empezar el reparto.
    //
    //  Se intentó antes con una franja propia que reservase esos 34 px durante
    //  el viaje, y salió peor: un `exclusiveZone` no solo aparta ventanas,
    //  también aparta las CAPAS que vienen detrás, así que la franja empujaba
    //  a la barra hacia abajo y se la veía descolgarse antes de partirse.
    //  Los píxeles que el host debe seguir guardándole a la barra.
    //
    //  Se suelta justo cuando el dock empieza a crecer, y el dock arranca
    //  reservando exactamente esos mismos 34: el relevo sale a cero y desde ahí
    //  el escritorio ACOMPAÑA al crecimiento en vez de pegar un salto al final.
    //  Al revés igual: no se recupera hasta que el dock ya se ha recogido.
    property int reservaBarra: (modo === "dock" || modo === "recogiendo")
        ? 0 : K4.Tema.altoPlegado

    readonly property int altoMuelle: 76

    //  Lo que mide cada trozo que viaja: LA MITAD DE LA BARRA que se acaba de
    //  partir, congelada al arrancar junto con el origen.
    //
    //  Estaba en 96 fijos, y eso no era partir la barra en dos: con la píldora
    //  en 122, dos trozos de 96 saliendo de sus extremos ocupaban 218 px
    //  juntos, casi el doble de lo que había. Se veía como que abajo llegaba
    //  algo más gordo de lo que se fue.
    //
    //  Lo comparten la escena —para saber dónde se juntan— y el dock, que nace
    //  exactamente de ese ancho: los dos trozos pegados SON la barra otra vez,
    //  y de ahí se estira.
    property int largoTrozo: 61

    //  Se coge la island por encima de todo para que no la pinte nadie más, y
    //  se pide de tamaño cero: la barra se encoge sola con la animación que ya
    //  tiene el host y desaparece.
    //  Solo se coge la island para las DOS ANIMACIONES en las que la barra
    //  tiene que encogerse o crecer, medio segundo cada una. El resto del
    //  tiempo la barra se aparta con `barraApartada`, que es por pantalla y no
    //  bloquea a nadie: con `active` puesto todo el rato y prioridad 90, la
    //  island del otro monitor se quedaba muerta —ni se desplegaba ni
    //  respondía— porque el host solo admite un plugin activo global.
    //
    //  Con la gota, CUÁNDO no lo dice el modo: la barra sostiene la gota
    //  mientras se hincha, así que sigue entera y a su tamaño durante el primer
    //  tercio de la caída y solo se recoge al romperse el cuello. Lo apunta la
    //  escena llamando a `desprendida()`.
    property bool cogiendoIsla: false

    readonly property bool mandaIsla: !ambasActiva
        && (esGota ? (cogiendoIsla || modo === "creciendo")
                   : (modo === "encogiendo" || modo === "creciendo"))

    priority: 90
    active: mandaIsla

    //  ¿Se ha ido ya la barra de arriba?
    //
    //  Se apunta a mano y no se deduce del modo, por lo mismo: con la gota la
    //  barra sigue puesta buena parte del viaje, y con las dos a la vez no se va
    //  nunca. Quien la manda irse es quien lo apunta.
    property bool barraFuera: false

    //  La pantalla que se lleva la barra, y lo que hay que seguir guardándole.
    property var barraApartada: (barraFuera && !mandaIsla)
        ? ({ pantalla: pantalla, reserva: reservaBarra }) : null
    //  Mientras se encoge o crece, la barra conserva su GROSOR y solo cambia
    //  de ancho: es lo que hace que se vea recogerse sobre los trozos en vez de
    //  desinflarse hacia arriba. Se va a cero cuando los trozos ya la tapan.
    islandHeight: mandaIsla ? K4.Tema.altoPlegado : 0
    view: null

    //  De dónde salen las gotas. Se CONGELA al arrancar: en cuanto se coge la
    //  island, su rect empieza a encogerse hacia cero, y si las gotas leyeran
    //  el rect en vivo saldrían de un punto que se les escapa.
    property real origenIzqX: 0
    property real origenDerX: 0
    property real origenY: 0

    //  El centro de la barra: de donde se descuelga la gota. Sale de los dos
    //  origenes y no de una property más para que no puedan discrepar.
    readonly property real origenX: (origenIzqX + origenDerX) / 2

    //  Y de ahí, los dos puntos de salida en coordenadas de pantalla. Los pide
    //  la escena tal cual: el trozo ya no sabe por qué borde va, solo de dónde
    //  sale y a dónde tiene que llegar.
    readonly property point salidaIzq: barraVertical
        ? Qt.point(origenY, origenIzqX) : Qt.point(origenIzqX, origenY)
    readonly property point salidaDer: barraVertical
        ? Qt.point(origenY, origenDerX) : Qt.point(origenDerX, origenY)

    //  Y en qué pantalla pasa todo. Con dos monitores esto no es un detalle:
    //  `K4.Isla.rect` da la island de la pantalla PRINCIPAL, y si la barra que
    //  se va está en la otra, las gotas salían de un punto que ni siquiera cae
    //  dentro de la ventana —las coordenadas son locales a cada monitor—. No
    //  se veía mal: no se veía.
    property string pantalla: ""

    function congelarOrigen() {
        //  Defensivo a propósito: si la barra corre una API vieja que no
        //  publica `pantalla`, esto valía `undefined`, la asignación a una
        //  property de texto reventaba, y como la llamada va ANTES de mover el
        //  modo, el modo no cambiaba y el comando entero no hacía nada. Sin un
        //  error a la vista: simplemente no pasaba nada al pulsar.
        pantalla = K4.Isla.pantalla || ""
        const r = K4.Isla.rectEn(pantalla)

        //  Los dos trozos juntos miden MENOS que la barra —un 62 %—, y salen
        //  centrados en ella. Eso es lo que deja ver la barra encogiéndose
        //  sobre ellos antes de partirse, igual que abajo se ve el dock
        //  recogiéndose sobre ellos antes de salir. Midiendo lo mismo que la
        //  barra no había nada que encoger y el paso se daba de golpe.
        //  Por el eje LARGO de la barra, que en un lateral es el alto. Con
        //  `r.ancho` a secas, una barra vertical daba un trozo del ancho de la
        //  píldora —lo estrecho— y los dos puntos de salida separados a lo
        //  ancho de algo que no se extiende a lo ancho.
        const largoBarra = barraVertical ? r.alto : r.ancho
        anchoLleno = largoBarra - ala * 2
        //  Con un suelo: por debajo de unos 56 px el trozo deja de parecerse a
        //  un cacho de barra por mucho que las esquinas se acoten.
        //  Anchos de sobra para que se lean APLANADOS: con la píldora desnuda
        //  un 36 % se quedaba en 60 px y un trozo de 60×34 con esquinas
        //  pequeñas es casi un cuadrado. Con el suelo de 70 la proporción se
        //  mantiene 2:1 y las esquinas salen redondas.
        //
        //  Cada trozo es la MITAD DE LA BARRA YA ENCOGIDA, y por eso sale de
        //  una fracción de la barra y no de una medida propia.
        //
        //  Tuve un suelo de 104 px «para que se leyeran aplanados», y con la
        //  píldora estrecha eso hacía que los dos sumaran MÁS que la barra: la
        //  contracción de arriba era en realidad un ensanchamiento, y al
        //  partirse y al reencontrarse quedaban desproporcionados. El suelo de
        //  ahora es solo el mínimo para que la silueta se trace.
        largoTrozo = Math.max(56, Math.round(largoBarra * 0.36))
        //  `origenIzqX`/`origenDerX` corren por el eje largo y `origenY` por el
        //  corto, sea cual sea el borde: así los dos trozos se separan SIEMPRE
        //  a lo largo de la barra, que es por donde se parte.
        const centro = barraVertical ? (r.y + r.alto / 2) : (r.x + r.ancho / 2)
        origenIzqX = centro - largoTrozo / 2
        origenDerX = centro + largoTrozo / 2
        origenY = barraVertical ? (r.x + r.ancho / 2) : (r.y + r.alto / 2)
    }

    readonly property var preferidas: [
        "kitty", "firefox", "org.kde.dolphin", "code", "discord",
        "org.telegram.desktop", "vlc", "steam"
    ]

    //  Los ids que hay puestos, EN ORDEN. Es lo único que se guarda: las
    //  aplicaciones se resuelven cada vez contra las instaladas, así que
    //  desinstalar una la quita del dock sola en vez de dejar un hueco muerto.
    property var idsDock: []

    //  Hasta que no se ha leído lo guardado, no se guarda NADA.
    //
    //  La lectura es asíncrona: durante ese rato `idsDock` está vacío, y
    //  cualquier cosa que guarde en ese hueco escribe el vacío —o la lista de
    //  arranque— encima del dock que tenías. No es hipotético: se me llevó por
    //  delante un dock recargando el plugin mientras probaba.
    property bool cargado: false

    K4.Guardado {
        id: guardado
        plugin: "dual"
        onCargado: function (d) {
            const l = (d && d.apps) || []
            self.idsDock = l.length > 0 ? l : self.preferidas.slice()

            //  `animar` es de cuando el único ajuste era encender o apagar el
            //  viaje. Apagado entonces es "seco" ahora, y se lee ANTES que
            //  `efecto` para que un guardado nuevo mande sobre el viejo: se
            //  migra sola en cuanto se toque cualquiera de las dos filas.
            if (d && d.animar === false)
                self.efecto = "seco"
            //  Y comprobado contra la lista: un fichero a mano con cualquier
            //  otra cosa dejaba un efecto que no pinta ninguna escena, o sea un
            //  atajo que se queda a medias sin decir por qué.
            if (d && self.efectos.indexOf(d.efecto) >= 0)
                self.efecto = d.efecto
            if (d && d.ambas !== undefined)
                self.ambas = !!d.ambas
            if (d && self.reservas.indexOf(d.reservaDock) >= 0)
                self.reservaDock = d.reservaDock
            //  Acotada al leer: el fichero se puede editar a mano y un dock
            //  al 300 % se iría de la pantalla sin decir por qué.
            if (d && ["arriba", "abajo", "izquierda", "derecha"]
                    .indexOf(d.ladoDock) >= 0)
                self.ladoDockPedido = d.ladoDock
            if (d && d.alineacionDock !== undefined) {
                const a = Math.floor(Number(d.alineacionDock))
                if (isFinite(a))
                    self.alineacionDock = Math.max(0, Math.min(100, a))
            }
            self.cargado = true
        }
    }

    function guardarDock() {
        if (!cargado)
            return
        guardado.guardar({ apps: idsDock, efecto: efecto, ambas: ambas,
                           reservaDock: reservaDock,
                           ladoDock: ladoDockPedido,
                           alineacionDock: alineacionDock })
    }

    //  ── el efecto del cambio ─────────────────────────────────────
    //
    //  Lo que se anima es lo que CUENTA lo que está pasando: sin nada, la barra
    //  desaparece de arriba y hay un dock abajo, y quien no lo haya visto nunca
    //  no sabe que son la misma cosa. Pero son segundos, y quien ya lo sabe lo
    //  hace veinte veces al día. De ahí que haya donde elegir:
    //
    //   · "viaje" — la barra se parte en dos y las mitades bajan por los cantos
    //     hasta juntarse (Escena.qml). Dos segundos largos, y es el que mejor
    //     cuenta que arriba y abajo son la misma cosa.
    //   · "gota" — la barra se queda y deja caer una gota que al llegar abajo se
    //     estrella y se extiende hasta ser el dock (Caida.qml). Un segundo, y es
    //     el único que se entiende también con la barra puesta, porque no cuenta
    //     un traslado sino un desprendimiento.
    //   · "seco" — no se acelera la animación: se salta entera. Los modos de en
    //     medio no llegan a existir, así que no se crea ninguna escena, la barra
    //     se aparta de golpe y el dock ya está puesto.
    readonly property var efectos: ["viaje", "gota", "seco"]
    property string efecto: "viaje"

    //  Y si la barra se va o se queda.
    //
    //  Quedándose no hay relevo que contar —arriba y abajo están a la vez— así
    //  que el viaje deja de ser «la barra bajando» para ser «la barra soltando
    //  dos gotas», que es literalmente lo que dibuja. La gota se lee igual de
    //  bien de las dos maneras, y por eso nació así: la pidieron con la barra
    //  quieta.
    property bool ambas: false

    //  ── qué hace el DOCK con el sitio del escritorio ─────────────
    //
    //  Las mismas cuatro que la barra, y por su cuenta a propósito: son dos
    //  bordes distintos y quien no quiere perder sitio arriba no tiene por qué
    //  no quererlo abajo, ni al revés. Un dock que se esconde y asoma al bajar
    //  el ratón es, además, lo que hace media pantalla del mundo.
    //
    //  Comprobada contra la lista al cargar, como el efecto: un fichero a mano
    //  con cualquier otra cosa dejaría un dock que no obedece a nadie.
    readonly property var reservas: ["reserva", "completa", "encima", "escondida"]
    property string reservaDock: "reserva"

    //  Y «completa» no es un cuarto estado sino una REGLA, igual que arriba:
    //  se resuelve a uno de los otros según si algo llena esta pantalla.
    readonly property string modoDock: reservaDock === "completa"
        ? (K4.Escritorios.lleno(pantalla) ? "escondida" : "reserva")
        : reservaDock
    readonly property bool dockReserva: modoDock === "reserva"
    readonly property bool dockSeEsconde: modoDock === "escondida"

    //  Los dos, CONGELADOS mientras dura el cambio y hasta volver arriba.
    //
    //  Se leen en `bajar` y valen para la ida y la vuelta. Leyéndolos en vivo,
    //  cambiarlos con el dock puesto dejaba la barra apartada por un efecto y
    //  devuelta por otro: la gota se iba a buscarla donde el viaje la había
    //  dejado, y no había nadie.
    property string efectoPedido: "viaje"
    property bool ambasActiva: false

    //  ── qué efecto se puede contar en cada pareja de bordes ──────
    //
    //  El VIAJE vale para todas. Lo que cuenta es «el trozo se despega y se va
    //  bordeando la pantalla hasta el otro», y eso no tiene eje: el camino se
    //  calcula del punto de salida al de destino por el perímetro, y la pieza
    //  gira al doblar cada esquina porque el ángulo sale de cuántas lleva
    //  dobladas. Con la barra arriba y el dock abajo da exactamente lo de
    //  siempre.
    //
    //  La GOTA no. Es una caída —cuello que adelgaza, cintura que se rompe,
    //  aterrizaje contra el canto— y una caída tiene UN sentido: hacia abajo.
    //  Así que solo se cuenta cuando la barra está arriba y el dock abajo, que
    //  es la única pareja en la que caer significa algo. En cualquier otra se
    //  cuenta con el viaje, que sí sabe ir a los cuatro bordes. Y no en seco:
    //  quedarse sin nada era peor que contar lo mismo de otra manera.
    //
    //  Estuvo pedida solo por «que ninguno de los dos vaya de canto», y eso
    //  dejaba pasar la barra ABAJO con el dock arriba: los dos horizontales,
    //  las cuentas válidas… y la gota no caía. Grabado a 60 fps: el trozo se
    //  quedaba pegado al canto de abajo —`y = 1063` en los cuarenta fotogramas
    //  que duraba—, se deslizaba de lado hasta la x del dock y desaparecía, y
    //  el dock salía arriba de la nada. Una caída hacia arriba no es media
    //  caída: es ninguna.
    //
    //  Se intentó girar la escena de la gota entera. Funciona con los bordes
    //  ENFRENTADOS y se rompe con los adyacentes: el trozo sale ya de canto de
    //  una barra que es horizontal, y el salto está al principio, que es donde
    //  más canta. Una gota que cae de lado no es una gota.
    readonly property bool gotaCabe: ladoBarra === "arriba" && ladoDock === "abajo"
    readonly property string efectoActivo: (efectoPedido === "gota" && !gotaCabe)
        ? "viaje" : efectoPedido
    readonly property bool esGota: efectoActivo === "gota"

    //  ── el reparto del tiempo de la gota ─────────────────────────
    //
    //  Va aquí y no en la escena porque la barra tiene que casar con ella: se
    //  encoge cuando el cuello se rompe, y al subir tiene que estar puesta antes
    //  de que el cuello la alcance. Dos sitios con los mismos números es un
    //  sitio donde olvidarse de uno.
    //  ── dónde se pone el dock a lo largo de su borde ─────────────
    //
    //  El dock estaba clavado al centro de la pantalla —tres anclas en el
    //  muelle, el destino de los dos trozos del viaje y el suelo de la gota,
    //  todos `ancho / 2`— mientras que la barra lleva su alineación desde
    //  siempre. O sea que se podía correr la barra y el dock se quedaba.
    //
    //  Ahora tiene la suya, y es INDEPENDIENTE de la de la barra: son dos
    //  sitios distintos de la pantalla y no tienen por qué compartir gusto.
    //  Cincuenta de fábrica, que es donde estaba.
    //
    //  Una sola fuente para los seis sitios: si el destino de la gota y el
    //  ancla del muelle discreparan, la gota aterrizaría a un palmo de donde
    //  nace el dock y se vería el salto.
    //  ── en qué borde vive el dock ────────────────────────────────
    //
    //  «abajo» de fábrica, que es donde ha vivido siempre.
    //
    //  Y NUNCA en el mismo borde que la barra, que se taparían: si coinciden,
    //  el dock cede y se va al de enfrente. Cede el dock y no la barra porque
    //  la barra es la casa —lo dice la sección Island— y porque eso es lo que
    //  el modo dual ha hecho siempre: la barra arriba, el dock abajo.
    property string ladoDockPedido: "abajo"

    readonly property string ladoBarra: {
        const v = K4.Isla.posicion
        return (v === "abajo" || v === "izquierda" || v === "derecha")
            ? v : "arriba"
    }

    readonly property bool barraVertical: ladoBarra === "izquierda"
                                         || ladoBarra === "derecha"

    readonly property var opuestos: ({ arriba: "abajo", abajo: "arriba",
                                       izquierda: "derecha",
                                       derecha: "izquierda" })

    readonly property string ladoDock: ladoDockPedido === ladoBarra
        ? opuestos[ladoBarra] : ladoDockPedido

    readonly property bool dockVertical: ladoDock === "izquierda"
                                         || ladoDock === "derecha"

    property int alineacionDock: 50
    readonly property real fraccionDock: Math.max(0, Math.min(100, alineacionDock)) / 100

    //  Dónde empieza algo de largo `w` en un borde de largo `largo`, colocado
    //  por esa fracción. La misma cuenta que usa la island, y vale para los dos
    //  ejes: en un lateral el «largo» del borde es el alto de la pantalla.
    function xDock(largo, w) {
        return Math.round(Math.max(0, largo - w) * fraccionDock)
    }
    function centroDock(largo, w) {
        return xDock(largo, w) + w / 2
    }

    readonly property int gotaDura: 1000
    readonly property real gotaCorte: 0.34      // se rompe el cuello
    readonly property real gotaSuelo: 0.86      // toca el borde de abajo

    K4.Ajustes {
        plugin: "dual"
        grupo: K4.Idioma.t("Modo dual")
        opciones: [{
            id: "efecto",
            tipo: "eleccion",
            nombre: K4.Idioma.t("Efecto del cambio"),
            //  De una pieza y no partida con un `+`: el extractor de textos
            //  ve DOS literales y en marcha `t()` recibe la suma, que no casa
            //  con ninguno de los dos. La cadena se queda larga y se traduce.
            desc: K4.Idioma.t("Bajando por los cantos, dejando caer una gota, o de golpe"),
            glifo: 0xF058C,   // md-water
            alternativas: [
                { codigo: "viaje", nombre: K4.Idioma.t("Viaje") },
                { codigo: "gota", nombre: K4.Idioma.t("Gota") },
                { codigo: "seco", nombre: K4.Idioma.t("Seco") }
            ]
        }, {
            id: "ambas",
            //  Esto modifica QUÉ ocurre al abrir el dock; no es el botón
            //  que lo abre. La redacción anterior parecía una orden y la
            //  gente la activaba esperando que el dock apareciese al instante.
            nombre: K4.Idioma.t("Mantener la barra al abrir el dock"),
            desc: K4.Idioma.t("Abre y cierra el dock con SUPER+SHIFT+D"),
            glifo: 0xF0BCB   // md-view_split_horizontal
        }, {
            id: "reservaDock",
            tipo: "eleccion",
            //  El nombre dice DOCK y la descripción dice dónde está el otro.
            //  Sin eso, esta fila y la de la barra se llaman casi igual, están
            //  en pantallas distintas de la misma lista, y el usuario cambió
            //  esta esperando que se escondiera la barra. Con razón.
            nombre: K4.Idioma.t("Cómo ocupa el sitio el dock"),
            desc: K4.Idioma.t("Solo el dock; el de la barra está en Island"),
            glifo: 0xF003E,   // md-arrange_bring_to_front
            alternativas: [
                { codigo: "reserva",   nombre: K4.Idioma.t("Reservar sitio") },
                { codigo: "completa",  nombre: K4.Idioma.t("Fuera a pantalla completa") },
                { codigo: "encima",    nombre: K4.Idioma.t("Encima") },
                { codigo: "escondida", nombre: K4.Idioma.t("Escondida") }
            ]
        }, {
            id: "ladoDock",
            tipo: "eleccion",
            nombre: K4.Idioma.t("Dónde vive el dock"),
            desc: K4.Idioma.t("Nunca en el mismo borde que la barra: si coinciden, el dock se va al de enfrente"),
            glifo: 0xF10A9,
            alternativas: [
                { codigo: "abajo", nombre: K4.Idioma.t("Abajo") },
                { codigo: "arriba", nombre: K4.Idioma.t("Arriba") },
                { codigo: "izquierda", nombre: K4.Idioma.t("Izquierda") },
                { codigo: "derecha", nombre: K4.Idioma.t("Derecha") }
            ]
        }, {
            id: "alineacionDock",
            tipo: "numero",
            nombre: K4.Idioma.t("Alineación del dock"),
            desc: K4.Idioma.t("En qué punto del borde de abajo se coloca; también se arrastra en el croquis de la Island"),
            glifo: 0xF11C3,
            min: 0, max: 100, paso: 5, unidad: "%"
        }]
        valores: ({ efecto: self.efecto, ambas: self.ambas,
                    reservaDock: self.reservaDock,
                    ladoDock: self.ladoDockPedido,
                    alineacionDock: self.alineacionDock })
        onCambiado: function (id, valor) {
            if (id === "efecto")
                self.efecto = String(valor)
            else if (id === "ambas")
                self.ambas = !!valor
            else if (id === "reservaDock")
                self.reservaDock = String(valor)
            else if (id === "ladoDock")
                self.ladoDockPedido = String(valor)
            else if (id === "alineacionDock")
                self.alineacionDock = Math.max(0, Math.min(100,
                    Math.floor(Number(valor)) || 0))
            else
                return
            self.guardarDock()
        }
    }

    //  ── lo que está abierto ──────────────────────────────────────
    //
    //  Las aplicaciones ABIERTAS salen en el dock aunque no estén fijadas, y al
    //  cerrarlas se van solas. Es lo que uno espera de un dock: lo fijado está
    //  siempre y lo demás es un reflejo de lo que tienes entre manos.
    //
    //  De dónde sale: del mismo sondeo que ya usa el rebote. `hyprctl` da la
    //  CLASE de cada ventana, que en la práctica es el id del .desktop —
    //  `firefox`, `org.kde.dolphin`, `org.telegram.desktop`—, así que se casan
    //  por ahí y, si no, por el nombre.
    //  id de aplicación -> [{ direccion, titulo }] de sus ventanas.
    property var ventanasPorId: ({})
    readonly property var idsAbiertos: Object.keys(ventanasPorId)

    function ventanasDe(id) { return ventanasPorId[id] || [] }

    //  A qué aplicación pertenece una clase de ventana.
    function _appDeClase(c) {
        for (let i = 0; i < K4.Apps.lista.length; ++i) {
            const a = K4.Apps.lista[i]
            const id = String(a.id || "").toLowerCase()
            const nom = String(a.name || "").toLowerCase()
            if (c === id || c === nom || (c.length > 2 && id.indexOf(c) >= 0))
                return String(a.id || "")
        }
        return ""
    }

    //  Llevar a una ventana que ya existe, en vez de abrir otra.
    //
    //  OJO con la sintaxis: la configuración de Hyprland de esta máquina es
    //  Lua, y los dispatch clásicos —`hyprctl dispatch focuswindow address:…`—
    //  fallan EN SILENCIO: no dan error y no hacen nada. Van contra `hl.dsp`.
    //  Y SIN llevarse el ratón detrás.
    //
    //  Hyprland, de fábrica, teletransporta el puntero al centro de la ventana
    //  que enfocas. Con el teclado eso tiene sentido —te lleva donde vas a
    //  mirar—, pero aquí el ratón ya está donde tú lo has puesto: acabas de
    //  pulsar un icono del dock con él. Que te lo muevan a mitad de pantalla es
    //  perder el sitio sin haber pedido nada. Medido: de (300,900) saltaba a
    //  (960,557), el centro justo de la ventana.
    //
    //  Se apaga el salto, se enfoca y se devuelve el ajuste a como estaba. Y por
    //  `hl.config` y no por `hyprctl keyword`, que con el parser Lua de esta
    //  máquina no aplica nada y encima contesta «ok» — comprobado: el `keyword`
    //  se ejecutaba, `getoption` seguía diciendo `false` y el puntero saltaba
    //  igual. Es la misma trampa que ya documenta el módulo del tema.
    //
    //  El valor al que se vuelve se lee UNA vez al arrancar y no antes de cada
    //  clic: leyéndolo cada vez, dos clics seguidos hacen que el segundo lea el
    //  `true` que puso el primero y lo deje encendido para siempre.
    property string warpsDeCasa: ""

    K4.Process {
        command: ["sh", "-c",
            "hyprctl getoption cursor:no_warps | head -1 | awk '{print $2}'"]
        running: true
        onSalida: function (texto) {
            const v = String(texto).trim()
            self.warpsDeCasa = (v === "true" || v === "false") ? v : "false"
        }
    }

    function enfocar(direccion) {
        if (!direccion)
            return
        const ir = 'hyprctl dispatch \'hl.dsp.focus({ window = "address:'
            + direccion + '" })\' >/dev/null'
        //  Si ya lo tienes apagado, no hay nada que apagar: se enfoca y ya.
        if (warpsDeCasa === "true") {
            K4.Sistema.lanzar(["sh", "-c", ir])
            return
        }
        K4.Sistema.lanzar(["sh", "-c",
            "hyprctl eval 'hl.config({ cursor = { no_warps = true } })' >/dev/null; "
            + ir + "; "
            + "hyprctl eval 'hl.config({ cursor = { no_warps = "
            + warpsDeCasa + " } })' >/dev/null"])
    }

    function estaFijada(id) { return idsDock.indexOf(id) >= 0 }

    //  Primero las fijadas, en su orden; detrás las abiertas que no lo estén.
    readonly property var apps: {
        const fuera = []
        for (let i = 0; i < idsDock.length; ++i) {
            const a = K4.Apps.porId(idsDock[i])
            if (a)
                fuera.push(a)
        }
        for (let i = 0; i < idsAbiertos.length; ++i) {
            if (estaFijada(idsAbiertos[i]))
                continue
            const a = K4.Apps.porId(idsAbiertos[i])
            if (a)
                fuera.push(a)
        }
        return fuera
    }

    //  Cuántas hay fijadas: la frontera entre un grupo y otro, para pintar la
    //  divisoria justo ahí.
    readonly property int fijadas: {
        let n = 0
        for (let i = 0; i < idsDock.length; ++i)
            if (K4.Apps.porId(idsDock[i]))
                n += 1
        return n
    }

    //  Se vigila solo con el dock puesto: sondear cuando no se ve no le sirve a
    //  nadie y son dos procesos por segundo.
    Timer {
        id: vigia
        interval: 1500
        repeat: true
        running: self.modo === "dock"
        triggeredOnStart: true
        onTriggered: if (!clientes.running) clientes.running = true
    }

    K4.Process {
        id: clientes
        command: ["hyprctl", "clients", "-j"]
        onSalida: function (texto) {
            let l = []
            try {
                l = JSON.parse(texto)
            } catch (e) {
                return
            }
            //  Contenedor NUEVO: mutar el objeto no repinta nada en QML.
            const mapa = {}
            for (let i = 0; i < l.length; ++i) {
                const c = String(l[i].class || "").toLowerCase()
                if (c.length === 0)
                    continue
                const id = self._appDeClase(c)
                if (!id)
                    continue
                if (!mapa[id])
                    mapa[id] = []
                mapa[id].push({
                    direccion: String(l[i].address || ""),
                    titulo: String(l[i].title || c)
                })
            }
            self.ventanasPorId = mapa
        }
    }

    function idDe(app) {
        return app ? String(app.id || app.name || "") : ""
    }

    function quitarDelDock(id) {
        //  Contenedor NUEVO: mutar el array no repinta nada en QML.
        idsDock = idsDock.filter(function (x) { return x !== id })
        guardarDock()
    }

    //  Meter una aplicación en el dock, en la posición donde se ha soltado.
    //  Si ya estaba, se MUEVE en vez de duplicarse.
    function ponerEnDock(id, donde) {
        if (!id)
            return
        const l = idsDock.filter(function (x) { return x !== id })
        const n = Math.max(0, Math.min(l.length, donde))
        l.splice(n, 0, id)
        idsDock = l
        guardarDock()
    }

    //  Mover un icono de sitio. `desde` y `hasta` son posiciones de LO QUE SE
    //  VE, que no es lo mismo que posiciones de lo guardado.
    //
    //  La lista guardada y la fila del dock no casan índice a índice: una
    //  fijada cuyo .desktop ya no existe sigue apuntada pero no se pinta, y las
    //  que están abiertas sin fijar se pintan al final sin estar en la lista.
    //  Moviendo con los índices de la fila «del 0 al 2» movía a otro sitio —una
    //  posición corta, con una sola fijada fantasma de por medio—. Así que se
    //  reordena la lista de las que SE VEN y luego se devuelve a sus mismos
    //  huecos, dejando a las fantasma donde estaban.
    function moverEnDock(desde, hasta) {
        const visibles = []
        const huecos = []
        for (let i = 0; i < idsDock.length; ++i)
            if (K4.Apps.porId(idsDock[i])) {
                visibles.push(idsDock[i])
                huecos.push(i)
            }

        //  Fuera de la parte fijada no hay nada que reordenar: lo de después
        //  son las abiertas, que no están en la lista.
        if (desde < 0 || desde >= visibles.length)
            return
        const h = Math.max(0, Math.min(visibles.length - 1, hasta))
        if (h === desde)
            return

        visibles.splice(h, 0, visibles.splice(desde, 1)[0])
        const l = idsDock.slice()
        for (let i = 0; i < huecos.length; ++i)
            l[huecos[i]] = visibles[i]
        idsDock = l
        guardarDock()
    }

    //  El cajón NO abre otro módulo: crece del propio dock (ver Muelle.qml).
    //  El centro de aplicaciones de la barra es el de los MÓDULOS, y aquí lo
    //  que hace falta son las aplicaciones del escritorio.

    //  ── el rebote al abrir ───────────────────────────────────────
    //
    //  El icono que acabas de pulsar bota hasta que la aplicación ABRE VENTANA,
    //  como el dock de macOS. No es un adorno: entre pulsar y ver algo pueden
    //  pasar varios segundos, y sin señal uno vuelve a pulsar.
    //
    //  Cuándo parar no lo sabe la API —`services/Ventanas` es del host y un
    //  plugin de fuera no llega ahí— así que se cuenta a mano: se apunta
    //  cuántas ventanas hay al lanzar y se sondea hasta que hay una más.
    property string botando: ""
    property int ventanasAlLanzar: -1

    //  Y un tope. Si la aplicación no abre —o abre en otro escritorio y el
    //  recuento no cambia— el icono no se queda botando para siempre.
    Timer {
        id: findeRebote
        interval: 12000
        onTriggered: self.pararRebote()
    }

    function pararRebote() {
        botando = ""
        ventanasAlLanzar = -1
        findeRebote.stop()
        sondeo.stop()
        conteo.running = false
    }

    Timer {
        id: sondeo
        interval: 350
        repeat: true
        onTriggered: if (!conteo.running) conteo.running = true
    }

    K4.Process {
        id: conteo
        command: ["hyprctl", "clients", "-j"]
        onSalida: function (texto) {
            let n = 0
            try {
                n = JSON.parse(texto).length
            } catch (e) {
                return
            }
            if (self.ventanasAlLanzar < 0) {
                self.ventanasAlLanzar = n
                return
            }
            if (n > self.ventanasAlLanzar)
                self.pararRebote()
        }
    }

    function abrir(app) {
        if (!app)
            return

        //  Se apunta el recuento ANTES de lanzar, y de ahí en adelante se
        //  vigila. El primer sondeo fija la referencia; los siguientes buscan
        //  la ventana nueva.
        botando = String(app.id || app.name || "")
        ventanasAlLanzar = -1
        conteo.running = true
        sondeo.restart()
        findeRebote.restart()
        //  Como el lanzador: `execute()` heredaría el directorio de trabajo de
        //  la barra y las terminales abrirían en la carpeta de configuración.
        const dir = app.workingDirectory && app.workingDirectory.length > 0
            ? app.workingDirectory : K4.Sistema.entorno("HOME")
        if (!app.command || app.command.length === 0) {
            app.execute()
            return
        }
        K4.Sistema.lanzar(["sh", "-c",
            "cd " + JSON.stringify(dir) + " && exec \"$@\"", "sh"]
            .concat(app.command))
    }

    //  Poner el ancho SIN animar, para empalmar sin que se note.
    function ponerAncho(v) {
        suave = false
        anchoBarra = v
        suave = true
    }

    function bajar() {
        if (modo !== "barra")
            return
        //  Lo que ya estuviera abierto al pulsar no cuenta como una petición:
        //  ver `pedidoPendiente`.
        pedidoPendiente = false

        //  Los dos ajustes, congelados para la ida y la vuelta.
        efectoPedido = efectos.indexOf(efecto) >= 0 ? efecto : "viaje"
        ambasActiva = ambas

        congelarOrigen()
        //  Se coge la barra exactamente como estaba: con el viaje para encogerla
        //  sobre el tamaño de los dos trozos, con la gota para que no pegue un
        //  salto cuando se la coja a media caída.
        ponerAncho(anchoLleno)

        //  Y la pantalla se relee AHORA, no en `congelarOrigen`.
        //
        //  `K4.Isla.pantalla` es la pantalla del módulo activo, y el host la
        //  fija al activarse uno: preguntándola antes de coger la island venía
        //  vacía si nadie se había activado desde que arrancó la barra —recién
        //  recargado el plugin, por ejemplo—. Con la cadena vacía, `apartada`
        //  no casaba con ninguna pantalla y la barra no se iba.
        pantalla = K4.Isla.pantalla || pantalla

        //  Sin efecto: ni encogerse ni gotas ni empalme. La barra se aparta y el
        //  dock ya está abajo.
        if (efectoActivo === "seco") {
            barraFuera = !ambasActiva
            modo = "dock"
            return
        }

        //  La gota cuelga de la barra ENTERA, así que aquí no se toca: la island
        //  se coge cuando el cuello se rompe (ver `desprendida`). Y con la barra
        //  puesta tampoco hay nada que encoger — las dos gotas del viaje salen
        //  de sus extremos y ella se queda donde está.
        if (esGota || ambasActiva) {
            modo = "bajando"
            return
        }

        modo = "encogiendo"
        anchoBarra = anchoSemilla
        encogida.restart()
    }

    //  La gota se ha desprendido: la barra ya no la sostiene.
    //
    //  Con la barra puesta no hay nada que recoger y solo queda acusar el peso
    //  que se va. Sin ella, es AQUÍ donde se coge la island y se encoge, y no al
    //  arrancar: antes del corte la barra está entera porque es de donde cuelga.
    function desprendida() {
        if (modo !== "bajando" || !esGota)
            return
        if (ambasActiva) {
            K4.Isla.efecto("dual", "tiron", 0.5)
            return
        }
        cogiendoIsla = true

        //  El ancho a cero DE GOLPE, y que lo anime el host.
        //
        //  Animándolo aquí se animaba dos veces: mi Behavior de 440 ms movía
        //  `anchoBarra`, y el host perseguía ese valor con OTRA de 440 ms
        //  encima. La barra tardaba casi el segundo entero de la caída en
        //  recogerse, y al soltarla —que es dejarla a cero sin más— todavía
        //  medía ochenta píxeles y pegaba el salto a la vista. Se veía como «la
        //  island se queda ahí un rato y luego desaparece», que es exactamente
        //  lo que era.
        //
        //  Con una sola, y encima OutBack, el grueso del recogido está hecho en
        //  un cuarto de segundo: la barra se retira de golpe al romperse el
        //  cuello, que es lo que hace una superficie que suelta una gota.
        ponerAncho(0)
        retirada.restart()
    }

    Timer {
        id: retirada
        //  Cuando al encogido del host ya no le queda nada que enseñar.
        //
        //  Pronto, y a propósito: soltarla es lo que le quita el GROSOR.
        //
        //  El ancho lo recoge el host en 440 ms y el grosor en otros 400, pero
        //  el del grosor no empieza hasta que se suelta. Esperando a que el
        //  ancho terminara, las dos animaciones iban en fila y lo último que
        //  quedaba era un muñón de 30×34 hundiéndose solo en el canto medio
        //  segundo después de que la gota se hubiera ido. Soltándola a los 140,
        //  el grosor se recoge A LA VEZ que el ancho: la barra se mete en el
        //  borde de la pantalla en diagonal y a los 330 ms del corte no queda
        //  nada, con la gota todavía a media caída.
        interval: 140
        onTriggered: if (self.modo !== "barra") {
            self.cogiendoIsla = false
            self.barraFuera = true
        }
    }

    Timer {
        id: encogida
        //  Casa con la contracción de arriba, no con la del dock: así el
        //  reparto empieza en el mismo momento que abajo, sobre el medio
        //  segundo, y las dos direcciones se sienten igual de vivas.
        interval: 500
        onTriggered: if (self.modo === "encogiendo") {
            //  A cero de golpe: los trozos ya están dibujados justo encima y
            //  miden lo mismo, así que el corte no se ve.
            self.ponerAncho(0)
            self.barraFuera = true
            self.modo = "bajando"
        }
    }

    //  La barra coge su ancho de empalme ANTES de que lleguen los trozos.
    //
    //  El host anima el ancho de la island con su propia curva, así que
    //  poniéndoselo en el momento del encuentro crecía desde cero: durante un
    //  cuarto de segundo no asomaba por detrás de los trozos y lo que se veía
    //  era la pieza montada con el puente, quieta, y solo después salía la
    //  barra. Dándole la salida antes de tiempo —con el alto todavía a cero,
    //  así que no se ve— al juntarse ya está a su tamaño y crece sin pausa.
    //  Con la gota no hace falta y por eso no se usa: allí lo que llega arriba
    //  no es media barra sino un charco que YA tiene el tamaño y la silueta de
    //  la barra —se estrella contra el canto de arriba y se extiende hasta
    //  serlo—, así que la island puede aparecer por debajo en el último
    //  instante y crecer tapada. Se le da el ancho en `viajeTerminado`.
    Timer {
        id: ventaja
        interval: 1700
        onTriggered: if (self.modo === "subiendo")
            self.ponerAncho(self.anchoSemilla)
    }

    Timer {
        id: crecida
        //  Lo justo para que el ancho y el grosor de empalme lleguen a
        //  aplicarse; el crecimiento de verdad lo hace el host al soltar.
        interval: 90
        onTriggered: if (self.modo === "creciendo") {
            self.modo = "barra"
            self.cogiendoIsla = false
            self.barraFuera = false
        }
    }

    function subir() {
        if (modo !== "dock")
            return
        if (efectoActivo === "seco") {
            ponerAncho(anchoLleno)
            barraFuera = false
            modo = "barra"
            return
        }

        //  Primero se recoge el dock sobre la pieza que va a subir; el viaje
        //  empieza cuando ha terminado.
        ponerAncho(0)
        modo = "recogiendo"
        recogida.restart()
    }

    Timer {
        id: recogida
        //  Lo que tarda el dock en encogerse, y un pelín más para que no se
        //  solape con el arranque del viaje. La gota lo recoge antes porque su
        //  despliegue también es más corto: 560 ms contra 760.
        interval: self.esGota ? 640 : 820
        onTriggered: if (self.modo === "recogiendo") {
            self.modo = "subiendo"
            if (!self.esGota)
                ventaja.restart()
        }
    }

    //  ¿Hay alguien pidiendo la island que no seamos nosotros?
    //
    //  La píldora no cuenta: es el fondo de armario y está siempre. Los avisos
    //  tampoco —un toast que llega solo no tiene por qué deshacerte el dock—.
    //  Lo que sí cuenta es un módulo que se abre porque has pulsado su atajo.
    readonly property bool islaPedida: {
        const q = K4.Isla.ocupadaPor
        return q.length > 0 && q !== "idle" && q !== "dual" && q !== "toast"
    }

    //  Y entonces la barra VUELVE, con su viaje entero.
    //
    //  El host ya no hace la excepción de sacarla a tamaño completo por su
    //  cuenta: mientras `barraApartada` esté puesta, la island está a cero. El
    //  módulo que has abierto ya está activo y espera; sale cuando los trozos
    //  han subido y la barra se ha vuelto a montar, que es lo que se ve.
    //  Solo cuenta lo que llega DESPUÉS de irse la barra.
    //
    //  Si tenías el lanzador abierto y pulsabas el atajo del dock, la barra
    //  bajaba entera y volvía a subir de inmediato: al llegar abajo se
    //  encontraba con que la island estaba ocupada desde antes y se daba media
    //  vuelta. Nunca podías bajar con algo abierto. Lo que hay que atender es
    //  el atajo que pulsas con el dock ya puesto, y ese SÍ es un cambio.
    property bool pedidoPendiente: false

    onIslaPedidaChanged: {
        if (!islaPedida)
            return
        //  Con la barra puesta no se ha llevado nadie nada: el módulo que pides
        //  sale donde siempre y el dock se queda abajo, que para eso están las
        //  dos a la vez.
        if (ambasActiva)
            return
        pedidoPendiente = true
        reclamada()
    }

    function reclamada() {
        if (!pedidoPendiente || modo !== "dock")
            return
        pedidoPendiente = false
        subir()
    }

    function alternar() {
        if (modo === "barra")
            bajar()
        else if (modo === "dock")
            subir()
    }

    function viajeTerminado() {
        if (modo === "bajando") {
            modo = "dock"
            //  Por si el atajo se pulsó MIENTRAS bajaba: entonces `subir` se
            //  negó —no estaba en el dock— y nadie iba a volver a preguntar.
            reclamada()
        } else if (modo === "subiendo") {
            //  Los trozos han llegado arriba y se han juntado. Se deja la barra
            //  EMPALMADA con su tamaño y se suelta enseguida: el crecimiento lo
            //  hace el host, que es el único que puede hacerlo CON CONTENIDO
            //  dentro.
            //
            //  Antes lo animaba yo durante 760 ms y salía mal por fuerza: la
            //  vista de este plugin es nula, así que lo que crecía era una barra
            //  VACÍA, y solo al soltarla aparecía el reloj con su propio
            //  desvanecido. Eso era el parpadeo, y el "encoge y vuelve a crecer"
            //  era el reajuste al ancho que pide la píldora de verdad.
            //  El ancho ya lo trae puesto desde `ventaja`; aquí solo se le
            //  devuelve el grosor y se suelta.
            //
            //  Con la gota el ancho se pone AQUÍ, en el mismo instante en que se
            //  coge la island: el charco de arriba ya mide exactamente eso, así
            //  que la barra nace debajo con su silueta y crece tapada por él
            //  mientras dura el relevo.
            if (esGota)
                ponerAncho(anchoSemilla)
            modo = "creciendo"
            crecida.restart()
        }
    }

    //  Las superficies. Van en el PLUGIN y no en `view` porque una vista solo
    //  existe mientras se tiene la island, y aquí la island está a cero
    //  justamente para que no se vea — cuando llega a estarlo.
    //
    //  Las dos escenas existen siempre como objetos y ninguna crea su ventana
    //  hasta que le toca: cada una mira su `…Fuera`, que ya lleva dentro de qué
    //  efecto es.
    Escena { plugin: self }
    Caida { id: caida; plugin: self }

    //  La franja que RESERVA el sitio del dock, y nada más.
    //
    //  El muelle ocupa la pantalla entera —lo necesita para recibir el clic de
    //  fuera del cajón—, y una superficie pegada a los cuatro bordes no puede
    //  quitarle sitio a nadie: sin un borde libre no hay borde del que quitar y
    //  el compositor la ignora. Así que el hueco lo pide esta, que no pinta ni
    //  recoge un solo clic y solo existe mientras el dock está puesto.
    K4.Ventana {
        nombre: "k4-dual-hueco"
        pantalla: self.pantalla
        visible: muelle.mostrando
        encima: false
        //  Suelta el borde de ENFRENTE del que ocupa el dock: sin un borde
        //  libre no hay borde del que quitar. Y el eje que no atan las anclas
        //  lo da lo hondo que sea el dock.
        pegadaArriba: self.ladoDock !== "abajo"
        pegadaAbajo: self.ladoDock !== "arriba"
        pegadaIzquierda: self.ladoDock !== "derecha"
        pegadaDerecha: self.ladoDock !== "izquierda"
        implicitHeight: Math.round(muelle.altoDock)
        implicitWidth: Math.round(muelle.altoDock)
        //  Y solo si el dock reserva. En «encima» y en «escondida» esta franja
        //  sigue existiendo —no cuesta nada, no pinta y no recoge un clic— pero
        //  no pide sitio: el escritorio llega hasta el borde.
        reserva: (muelle.mostrando && self.dockReserva)
            ? Math.round(muelle.altoDock) : 0

        //  Sin zona activa se tragaría los clics del dock, que está justo
        //  encima de ella.
        zonaActiva: nadaHueco

        Item { id: nadaHueco; width: 0; height: 0 }
    }

    Muelle {
        id: muelle
        plugin: self

        //  Que se retire cuando no haga falta. Lo decide el ajuste; cuándo
        //  vuelve, el propio muelle.
        seEsconde: self.dockSeEsconde

        //  Se va cuando ha terminado de RECOGERSE, no cuando empieza la
        //  subida. Atado solo al modo, al pulsar para subir el dock se quedaba
        //  plantado en su sitio —negro y vacío— durante los dos segundos del
        //  viaje, porque su tamaño de reposo no es cero sino el de los dos
        //  trozos juntos. Ahora se encoge hasta ser exactamente esos dos trozos
        //  y entonces se quita, justo cuando ellos ya están dibujados encima.
        //  Cuándo existe su superficie lo decide ella: ver Muelle.qml.
        despliegue: self.modo === "dock" ? 1 : 0
        //  Que se despliegue DESPACIO y sin rebote.
        //
        //  Estaba en 420 ms con OutBack: crecía de golpe y el rebote del final
        //  remataba la sensación de salto. Lo que se está enseñando es masa
        //  extendiéndose, y eso no rebota — arranca suave, coge cuerpo y para
        //  suave, que es lo que hace InOutCubic.
        //
        //  Salvo con la gota, que llega ESTRELLÁNDOSE: ahí lo que se extiende ya
        //  trae toda su velocidad del golpe, así que sale disparado y frena
        //  —OutCubic— y en menos tiempo, que el impacto ya ha pasado. Con la
        //  curva del viaje, el dock se lo tomaba con calma justo después de un
        //  choque y parecían dos animaciones de películas distintas.
        Behavior on despliegue {
            enabled: self.efectoActivo !== "seco"
            NumberAnimation {
                duration: self.esGota ? 560 : 760
                easing.type: self.esGota ? Easing.OutCubic
                                         : Easing.InOutCubic
            }
        }
    }

    //  El atajo global. El nombre es lo único que se declara aquí: la tecla la
    //  ata el compositor a `k4:dual`, que es como funcionan todos los de la
    //  barra —ver `hypr/k4.conf`—. Así no hay que arrancar un proceso para
    //  alternar: la barra recibe la señal directamente.
    K4.Atajo {
        name: "dual"
        description: "Modo dual: la barra baja de gotas y se hace dock"
        onPressed: self.alternar()
    }

    K4.Ipc {
        target: "k4.dual"

        //  Para poder mirarle las tripas desde la terminal: el modo, la
        //  pantalla y de dónde salen las gotas. Sin esto, depurar una
        //  animación de 820 ms es perseguirla con capturas.
        function estado(): string {
            return JSON.stringify({
                modo: self.modo, viajando: self.viajando,
                efecto: self.efectoActivo, ambas: self.ambasActiva,
                gota: Math.round(caida.t * 100) / 100,
                cogiendoIsla: self.cogiendoIsla,
                barraFuera: self.barraFuera,
                pantalla: self.pantalla,
                islaPantalla: K4.Isla.pantalla,
                izq: Math.round(self.origenIzqX),
                der: Math.round(self.origenDerX),
                y: Math.round(self.origenY),
                dockDentro: muelle.dentro,
                dockRaton: Math.round(muelle.ratonX),
                dockMuestra: muelle.mostrando,
                //  El escondite, entero: si el dock se queda puesto cuando no
                //  debería, aquí se ve CUÁL de las condiciones lo retiene sin
                //  tener que perseguirlo con capturas.
                dockSeEsconde: muelle.seEsconde,
                dockRetirado: muelle.retirado,
                dockHazteVer: muelle.hazteVer,
                dockDespliegue: Math.round(muelle.despliegue * 1000) / 1000,
                dockArrastre: muelle.arrastreDesde,
                ocupante: K4.Isla.ocupadaPor,
                islaPedida: self.islaPedida,
                selectorDe: muelle.selectorDe,
                menuDe: muelle.menuDe
            })
        }

        function toggle(): void { self.alternar() }
        function bajar(): void { self.bajar() }
        function subir(): void { self.subir() }
    }
}
