# Digivice como plugin

Vive en `services/Digivice.qml` (estado y reglas atadas),
`services/DigiviceReglas.js` (las reglas puras) y `plugins/Digivice/`.
Es una **adaptación original**: no carga el emulador de dispositivos que
sirvió para entender el género, ni copia su código, sus gráficos ni sus
datos.

## De dónde salen los datos

Las especies vienen de [digi-api.com](https://digi-api.com) — datos
CC-BY-SA 3.0, sobre todo de Wikimon — y están congeladas en
`plugins/Digivice/datos/`:

- `digimon.json` (366 KB): las 1488 fichas con etapa, atributo, tipo,
  zonas, técnicas y el grafo de evolución. Se carga al arrancar.
- `especiales.json` (6 KB): las evoluciones Armor, X y Warp. Se carga al
  arrancar: lo mira la pantalla de evolución, que es de las que más se abren.
- `digimon-desc.json` (488 KB): las descripciones. Se carga **solo** al
  abrir la enciclopedia, que es medio megabyte que no tiene por qué pagar
  quien solo viene a dar de comer.

### El arte

Dos fuentes y una cascada. Primero el **sprite del aparato**, sacado de
[Wikimon](https://wikimon.net) con su API de MediaWiki: está dibujado a ese
tamaño, así que se lee perfecto pequeño. Se prefiere el de color y se cae al
monocromo de los aparatos clásicos. **1113 de 1488 tienen sprite, 855 a
color**; el resto usa la ilustración de digi-api, que siempre está.

**Por qué unos salen en color y otros en blanco y negro.** No es un filtro
mal puesto: de una misma especie Wikimon guarda el sprite de cada aparato que
ha existido, y **solo 14 de los 54 aparatos dibujan en color**. Los del
Digital Monster del 97, los D-3, los Pendulum clásicos y los D-Terminal son
LCD de un bit, así que 258 especies **no tienen sprite en color en ningún
sitio**: 104 de ellas tienen exactamente uno y punto.

El color de cada aparato se **mide**, no se adivina por el nombre —lo hace
`tools/digivice_sprites.py`—, y esa es la lección: `dark color` suena a color
y lo es (59 % de píxeles con cromatismo), `dark` suena parecido y es
monocromo (0 %). La primera versión de esto se hizo a ojo con una lista de
seis nombres de los cincuenta y cuatro que hay, y se coló monocromo en 19
especies que sí tenían color —`dark color`, `dv color`, `d3 color` y `ws`—,
además de marcar como color 143 sprites de `dmx` que no lo son. El generador
no se había guardado, así que no había manera de revisarlo; ahora vive en
`tools/` con sus dos entradas (`datos/sprites-fuentes.json`, todos los
candidatos, y `datos/sprites-aparatos.json`, el color medido).

Y el reescalado depende de **si la imagen se agranda o se reduce**, no de si
es sprite o ilustración. Agrandando hay que dejarla a cuadros; reduciendo hay
que filtrar. Faltaba la segunda mitad, y por eso los sprites en color de los
aparatos —arte de 64×64 subido a 3×, o sea 192×192— salían desdentados al
dibujarse a 48: se saltaba tres de cada cuatro píxeles.

**Los sprites de Wikimon miran a la IZQUIERDA.** Comprobado sobre los de la
caché: Agumon, Airdramon, Gabumon, Numemon, Kabuterimon, Monochromon,
MetalGarurumon… todos los que tienen perfil. En el código ponía lo contrario y
por eso en combate los dos bichos **se daban la espalda**, y en la pelota el
tuyo corría de espaldas a ella. De ahí el signo menos en el `xScale` de
`Criatura.qml` y `Pelota.qml`: `mirandoDerecha` quiere decir «hacia la
derecha», y para eso hay que espejar.

Reducir la ilustración NO es una alternativa: a 48 px Gomamon se convierte en
papilla. El pixel art hay que dibujarlo, no derivarlo.

El índice (`datos/sprites.json`, 53 KB) guarda la ruta ya calculada del MD5
del nombre **real** del fichero en Wikimon. Reconstruirlo desde el nombre de
digi-api fallaba en 7 de cada 20: los que llevan espacios, guiones o
paréntesis se llaman distinto allí.

Las **imágenes no se empaquetan**: son de Bandai. Se piden a la API la
primera vez que hacen falta y se quedan en
`~/.local/state/k4/plugins/digivice/img/`. Mientras no están, se dibuja la
silueta con la inicial. Por eso este plugin no está en `registro.json`:
cambiar a arte propio es cambiar `rutaImagen` en el servicio, no
reescribir el juego.

De la ilustración de reserva no se guarda ni la URL: son derivables del
nombre —se comprobaron las 1488— y eso son 82 KB de índice que no se cargan.

## Qué funciona ahora

- Cuidado con el reloj real: hambre, ánimo, descuidos y enfermedad.
- **Suciedad**: cada comida acaba en el suelo al cuarto de hora largo, hasta
  cuatro montones. Dejarlos sin recoger cuenta como descuido, y con el suelo
  lleno se cobra el doble de rápido.
- **Peso**: comer engorda, entrenar adelgaza, y por debajo del mínimo de su
  etapa no baja. Sobrarle peso le quita velocidad —no vida ni ataque: es
  lastre, no debilidad— y empeora la rama de evolución.
- **Sobrealimentar**: dar de comer con el estómago lleno engorda el doble y
  a la tercera cuenta como descuido.
- **La deuda de los medidores no se acumula estando a cero.** No se puede
  tener más hambre que vacío. Sin esta regla pasaba lo peor que le puede pasar
  a un botón: tras unas horas sin atenderlo había 148 minutos guardados —casi
  cinco corazones— y **dar de comer no hacía nada visible**. El corazón subía,
  el siguiente tick se lo llevaba, la comida se gastaba y el peso subía igual.
  La regla vive en `DigiviceReglas.js` justamente por esto: estaba dentro del
  QML del servicio, fuera del alcance de las pruebas, y por eso nadie la cazó.
- **El cuidado va por AGENDA, no por goteo.** Cada día tiene sus horas de
  hambre y de mimo, y cambian de un día para otro: 13-17 comidas, 9-12 mimos,
  5-8 cacas, con **25 minutos de separación mínima** entre pedir comer y pedir
  mimo. Es el modelo del emulador de aparatos —`hunger_events_left`,
  `poop_events_per_day`, `sleep_minutes_per_day`, y rangos por todas partes—
  y sustituyó al goteo porque del goteo salieron **tres defectos con la misma
  raíz**:
  1. La deuda crecía sin tope con el medidor a cero, así que tras unas horas
     de abandono **dar de comer no hacía nada visible**.
  2. Los dos medidores se realineaban y pedían a la vez **un tercio** de las
     veces, justo lo contrario de lo que promete el diseño.
  3. Pedía de comer a las 9:00, a las 10:00 y a las 11:00, **en punto**. Se le
     podía poner el reloj en hora.
  Una agenda no tiene deuda que crecer, coloca los sucesos separados por
  construcción y no repite dos días iguales. **Se genera de una semilla
  estable**, así que no hay nada que guardar y preguntar «cuántos sucesos
  hubo entre estas dos horas» da lo mismo estando delante que recuperando las
  ocho horas que estuviste fuera. De paso desaparecen tres acumuladores del
  guardado.
- La semilla sale del bicho, así que **su ritmo es suyo**: dos criados a la
  vez no piden de comer a la misma hora.
- Se vacía de media en **3 h 16** (hambre) y **4 h 48** (ánimo); sin tocarlo enferma a las **6 h 20** y solo regresa
  de etapa a las **9 h 20**. Los números de antes —30 y 40 minutos por
  corazón— lo hacían regresar a las **3 h 20**: te ibas a comer y volvías con
  la crianza de horas deshecha. Regresar es lo más caro que hace este juego y
  no puede dispararse por una reunión, así que el fondo del pozo queda por
  encima de una jornada de trabajo Y por encima del tope de 8 h de progreso
  con la barra cerrada.
- Sueño de 22:00 a 08:00; despertarlo cuenta como descuido.
- Progreso con la barra cerrada, con tope de ocho horas.
- **Una partida empieza con un HUEVO, no con un bicho.** Antes te daba un
  Baby I ya nacido y te saltabas lo primero que hace cualquiera de estos
  cacharros: esperar a que rompa. La incubación ya existía para los huevos que
  capturas y no había razón para que la tuya fuese distinta.
- **El huevo tiene su propia hoja de sprites** (`assets/huevo.png`, 6 poses de
  48×48 generadas con la herramienta de imágenes), y **la pose sale del
  progreso**, no de un temporizador: entero mientras va lejos, con una primera
  grieta al 65 %, rajado al 92 % y partido al abrirse. Además se menea cada
  vez más deprisa según se acerca —de casi dos segundos entre meneos a menos
  de medio—, así que mirarlo te dice cuánto le falta sin leer un número.
  Es lo primero que ve alguien que abre el plugin y no podía ser un icono
  quieto.
- **El fotograma salta, no se interpola.** Llevaba un `Behavior` en el
  desplazamiento de la hoja y hacía lo contrario de suavizar: como lo animado
  era el offset, la imagen se arrastraba de lado y se veía el huevo cruzar la
  pantalla pasando por los fotogramas vecinos. Lo que sí se anima es la
  **inclinación del huevo entero** —eso mueve el objeto, no la ventana por la
  que se mira la hoja— porque el ladeo del arte es muy sutil y solo con él no
  se leía el meneo.
- **Rompe andando**, con las mismas señales y **la misma zancada** que mueven
  la carretera —contaba pulsaciones, así que abrir una aplicación avanzaba 5
  de camino y solo 1 de huevo: dos monedas para el mismo gesto—. Y funciona
  SIN criatura, que es el caso que importa: si dependiera de tener una, el
  primer huevo no rompería jamás.
- **Tarda 120 de zancada**, que medido son ~4 h de uso normal y ~2 de uso
  intensivo. Estaba en 24 —50 min y 23 min— y era nada. Un huevo tiene que ser
  de los de dejarlo y volver.
- Escalera Baby I → Baby II → Child → Adult → Perfect → Ultimate.
- Evolución por el grafo de la API filtrado al peldaño siguiente; la rama
  la elige lo bien que hayas criado.
- **Evolucionar cuesta tres cosas a la vez**: tiempo en la etapa, combates
  ganados y experiencia. Antes bastaba con esperar, y esperar no es jugar.
  La XP sale de pelear —escalada por la etapa del rival, el triple si es
  jefe— y de entrenar, así que el que cría de verdad sube antes que el que
  deja el aparato encendido.
- **Los tres requisitos se ven**, cada uno con su cifra y su marca, en una
  pantalla propia. Un aparato que dice «todavía no» sin decir qué falta
  convierte la crianza en superstición.
- **Jogress**: dos bichos de la guardería se fusionan en un tercero que no
  sale de ninguna de las dos líneas. **Se pierden los dos**, y el hijo hereda
  la media de su entrenamiento. 620 especies con pareja y 3498 parejas,
  sacadas del campo `condition` de la API. Una pareja da un solo hijo,
  decidido al construir el índice: si dependiera de a quién llevas encima,
  fusionar sería una tirada de dados con dos caras.
- Regresión en vez de muerte al fondo del descuido.
- **La exploración es una CARRETERA, y la distancia es un cuentakilómetros.**
  Permanente, no se gasta. Usar el ordenador te lleva por el camino y los
  jefes están cada vez más lejos: la primera zona mide 250 y la novena 3689.
  Es lo que hace `area_distance`/`boss_distance` del emulador, que yo había
  dejado en un contador invisible.
- **Cada gesto, una zancada distinta**: cambiar de ventana 1, cambiar de
  escritorio 2, abrir una aplicación 5. Antes todo valía igual y la cifra no
  significaba nada. Sigue sin leerse NADA: solo QUE hubo un cambio y CUÁNTAS
  ventanas hay — ni títulos, ni pids, ni nombres de aplicación.
- **Los eventos van colocados en el camino**, no sorteados en un momento
  cualquiera: en el kilómetro 40, en el 120, en el 350. Es la misma idea que
  la agenda del cuidado pero en distancia, y trae la misma ventaja —preguntar
  «qué hay entre estas dos» da lo mismo de golpe que a trocitos, así que
  recuperar lo que pasó mientras no mirabas es exacto—.
- **Qué te encuentras**: bicho salvaje (36 %), hallazgo de comida o bits,
  **rastro** —el minijuego de los tres rastros, que era la caza—, datos de una
  especie, o nada. Los pesos dependen de **la profundidad**: el principio es
  apacible y el final está lleno de bichos (29 % de combates en el primer
  cuarto, 44 % en el último). El jefe va forzado al final, no sorteado.
- **La caza dejó de ser un icono del menú**: es uno de los eventos del camino.
  El minijuego no se tiró —está hecho, probado y es una decisión con una
  estadística detrás—, solo cambió de dónde sale.
- **Con algo interactivo esperando, la carretera se para.** No se apilan cinco
  combates mientras trabajas: el camino te espera donde lo dejaste.
- **Las zonas se pueden rehacer.** Vencer al jefe conquista la zona —la
  estrella es para siempre— pero el camino se vuelve a andar cuando quieras
  desde el mapa, y la carretera de la vuelta nueva **no es la misma**: los
  hitos caen en otros sitios. Sin esto, conquistar las nueve zonas te dejaba
  sin sitio donde andar y sin manera de volver a por la comida, las especies
  o el Digimental de ninguna. El jefe se planta otra vez al final de cada
  vuelta.
- **Al final del camino con el jefe vivo, el jefe vuelve a salir.** Sin esto,
  perder contra él dejaba la distancia al máximo, sin hitos por delante y sin
  manera de retarlo otra vez: la zona moría para siempre.
- Un goteo lento por reloj (8 min) para quien pasa el día en una sola ventana.
  Es el SUELO, no el motor: estaba en 90 s y eso daba 560 de distancia al día
  sin tocar nada, así que hasta en uso normal solo el 35 % del avance venía de
  usar el ordenador — un temporizador anulando la idea entera. A 8 minutos
  aporta 105 al día y el uso activo manda: **74 %** en uso normal, 88 % en uso
  intensivo.
- **El ritmo, medido**: en uso normal la primera zona se hace en medio día y
  la novena en 9; usándolo a todas horas, en 4,3. Quien apenas lo usa también
  avanza, pero tarda 35 días en la novena — el goteo garantiza que la
  carretera nunca se para del todo.
- **Paisaje** en las tres pantallas: dos capas en parallax con el color de la
  zona. En el mapa avanza un tranco por paso; en casa y en combate está
  quieto.
- Nueve zonas —los "fields" de la API— con encuentros a tu altura.
- **Un jefe por zona**, distinto en cada una y un peldaño por encima de ti.
  Aparece tras cuatro victorias allí —está al final del camino, no en una
  tirada de suerte— y ganarlo conquista la zona y da esfuerzo.
- **El Área Oscura está cerrada** hasta que caigan cuatro jefes.
- **La retícula del LCD va DEBAJO del contenido.** Estaba encima de todo, y
  con un paso de 4 px sobre letras de 9 y 10 cortaba cada trazo: una línea
  horizontal caía justo a la altura de la equis y frases enteras se leían a
  duras penas. Debajo sigue haciendo su trabajo —textura el cristal y el
  paisaje, que es donde se ve— y encima queda solo un susurro al 8 %, que no
  toca el texto pero mantiene el aire de cristal. De paso el pixel art gana:
  una rejilla encima de un sprite pelea con sus propios píxeles.
- **Nada de texto por debajo de 11 px.** Los tamaños subieron un punto —eran
  93 sitios— y con ellos las filas de las listas, porque la tilde de «Ración»
  se salía de una fila calculada para la letra anterior.
- **La island ES el aparato**: se abre estrecha y alta (300×373), colgando
  de la barra. El alto NO es un número puesto a mano: sale de lo que mide el
  aparato —margen, pantalla, leyenda, botones y correa— porque a ojo sobraban
  80 px de cuerpo vacío entre la pantalla y los botones. No hay panel con un aparato dentro: el fondo de la island
  hace de carcasa y encima van el bisel, la pantalla LCD con su retícula de
  puntos y tres botones físicos.
- **El primer icono es «Casa»**, y su pantalla es el bicho. Sin él, el aparato
  abría con el cursor sobre «Bolsa» pero enseñando la criatura: como `pulsarB`
  mira la ESCENA y no el cursor, **B no hacía absolutamente nada** y A te
  alejaba de la Bolsa — solo se llegaba dando la vuelta entera al menú. El
  arranque tiene que estar en sincronía.
- **Se navega como el aparato de verdad**: A recorre los iconos del borde de
  la pantalla, B **entra** en el que parpadea, y dentro es cuando A pasa
  fichas; C sube un nivel. La distinción entre *mirar el menú* y *estar
  dentro* no es cosmética: sin ella el aparato se quedaba **atrapado**, porque
  las pantallas de lista se abren al señalarlas y A pasaba a recorrer la lista
  en cuanto el menú tocaba una. Llegabas al cuarto icono y los once siguientes
  eran inalcanzables. El icono señalado **parpadea mientras miras y se queda
  fijo al entrar**, que es lo que dice cuál de las dos cosas va a hacer A. No hay pestañas ni cabecera
  de escritorio, y todo —criatura, estado, mapa, vistos, combate y
  entrenamiento— pasa dentro de la pantalla, de una cosa cada vez.
- **El bicho vivo**: pasea de un lado a otro de la pantalla a saltos de
  píxel, se da la vuelta al llegar, respira, se tumba a dormir con sus «z z»
  y parpadea cuando está enfermo.
- **Y se entera de lo que pasa en tu escritorio.** Hasta ahora el plugin lo
  *contaba* —los pasos, la carretera, la pelota cruzando tus ventanas—; esto
  es que además reaccione. **Baila cuando suena tu música**, anda nervioso con
  el escritorio lleno de ventanas y se queda tranquilo cuando llevas un rato
  concentrado en una sola. Todo con el ritmo del paseo y del respiro: ni un
  sprite nuevo.
- **Cada uno baila lo suyo, y bailar cansa.** El salto y el ritmo salen de su
  carácter —el juguetón se vuelve loco, el tímido apenas se mueve— y alterna
  tandas de baile con tramos tomando aire, también a su ritmo: el tozudo no
  piensa parar y el tímido descansa el doble de lo que baila. Que todos
  bailaran igual y sin fin era lo que delataba que no había nadie dentro.
- **El renglón nunca contradice lo que ves.** Lo que hace AHORA manda sobre lo
  que es en general: mientras baila cuenta cómo baila, y la nota de su
  carácter espera a que no esté haciendo nada especial. Un bicho dando botes
  con tu música mientras el aparato dice «se esconde y observa» es el aparato
  desmintiéndose delante de tus ojos.
- **`K4.Medios` se lee sin permiso** —la API solo lo pide para controlar la
  música— y aquí no se mira el título, ni el artista, ni la aplicación: solo
  si suena algo. La promesa de no leer nada de tu escritorio sigue intacta.
- **Cada bicho tiene su CARÁCTER**, sacado de la misma semilla que su agenda y
  su carretera: valiente, cauto, tozudo, glotón, juguetón o tímido. No es
  decorativo:
  - **El tuyo** decide cuántas veces al día pide comer o mimo y qué le sienta
    mejor —al glotón la comida le alegra, al juguetón el mimo le llena el
    doble—, y se enseña en la pantalla de Estado, porque una regla que no se
    ve no se puede jugar en contra.
  - **El del rival** sale de su ESPECIE, así que el mismo bicho pelea siempre
    parecido y se puede aprender a leerlo, pero dos rivales de la misma etapa
    ya no juegan igual el triángulo. Medido: el equilibrio a igualdad de etapa
    se mantiene (42-55 % de victorias).
  Es la respuesta barata a «que el juego sea único»: determinista, gratis,
  sin red y probable, que es como está hecho todo lo demás.
- **El combate se pelea solo y tú intervienes.** El triángulo sigue siendo el
  mismo —atacar gana a cargar, cubrirse gana a atacar, cargar gana a
  cubrirse, y ataque contra ataque es colisión: se llevan lo suyo los dos—,
  pero ya no espera a que pulses: cada 1200 ms hay un intercambio y tu bicho
  elige por su cuenta con el mismo criterio con el que elige el rival. Los
  tres botones son **intervenciones** —**A** arma técnica, **B** cubrir,
  **C** cargar—: lo que pulses manda en el intercambio siguiente y luego se
  consume. Cargar no hace daño: acumula y multiplica tu siguiente golpe, así
  que es una apuesta —si te pillan cargando, duele el doble—.
  El porqué: pulsar A diecinueve veces seguidas no era una decisión, era una
  cuota. Así un combate son ~24 s que puedes MIRAR, con hasta diecinueve
  sitios donde meter mano si ves venir algo. Ninguna intervención es
  obligatoria y no perderse ninguna no es lo óptimo: tu bicho no juega mal.
- **Cada bicho pega con lo suyo.** Todos los golpes eran el mismo punto de
  color con una estela: daba igual que pegara un dragón, una planta o una
  máquina, lo que tiraba por la borda lo único que distingue a 1488 especies
  aparte del sprite. Ahora la **forma** del golpe sale del arquetipo —doce
  dibujos: bola, rayo, roca, luz, sombra, pluma, aguja, hoja, gota, garra,
  filo y chispa— y el **halo** del atributo, de modo que «una hoja con halo
  morado» se lee como planta virus. Son dos ejes y van en dos tablas: mezclar
  el atributo en la forma habría perdido uno de los dos.
  La tabla del dibujo es **aparte de `ARQUETIPOS`** a propósito: esa fija los
  multiplicadores de vida, ataque, defensa y velocidad, y ampliarla para
  colorear golpes habría sido colar un cambio de balance por la puerta de
  atrás. Y el respaldo tiene dibujo propio —la chispa— en vez de compartir la
  bola del dragón: con la bola compartida, el 35 % de las peleas enseñaba lo
  mismo por dos motivos opuestos.
- **El patrón dice si es normal, técnica o cargado**, sin leer el cartel: la
  simple es un golpe, la **ráfaga** son tres escalonados en el tiempo y la
  **columna** una fila apretada que cruza como un haz. Cargado no es otro
  dibujo: es el mismo, más grande y con el halo encendido, para que se siga
  reconociendo de quién viene. El cartel lo dice con las mismas palabras
  («Golpe normal», «Petit Fire ráfaga ×3», «×2 Petit Fire»).
- **Cubrirse y cargar también se ven.** Atacar tenía el golpe cruzando la
  pantalla y las otras dos acciones eran un icono de 16 px sobre la cabeza:
  con la pelea automática, dos de cada tres intercambios no tenían nada que
  mirar, y son justo las dos que hay que aprender a leer para intervenir
  bien. Cubrirse **planta un escudo** por el lado por el que viene el golpe;
  cargar hace **caer motas de energía** hacia un punto delante del bicho. El
  destello va delante y no en su centro: puesto en el centro se veía como una
  moneda pegada en la barriga del sprite.
- **Cuándo entra el aliado, dicho con palabras.** La pregunta fue literal:
  «¿cuándo puedes invocar a un compañero y, si es automático, en qué
  momento?». No es automático: entra **cuando lo llamas**, una vez por
  combate, y cuesta energía. La chapa era una cara y «3⚡», y ahora dice en
  qué estado está —`L · 3⚡`, `sin ⚡`, `ya vino`—. Y se ve **siempre**,
  también con la guardería vacía: estaba condicionada a tener aliado, así que
  quien empieza no veía la chapa nunca y no había manera de enterarse de que
  la llamada existe. El aliado además **pega con su propia firma**, que es
  medio premio de la guardería.
- **Dos fallos vivos que salieron de ahí.** Sin guardería, la llamada
  ejecutaba `elegir("atacar")` —una función que dejó de existir al pasar el
  combate a automático—: gastaba la energía y reventaba sin pegar, o sea que
  estaba rota entera para quien empieza. Y al rival se le dibujaba siempre un
  golpe simple aunque estuviera tirando una ráfaga de tres, porque la forma
  se ponía a mano en vez de leerla del resultado.
- **Se sabe cuál barra es la tuya y qué está haciendo tu carga.** Eran dos
  barras iguales sin nombre —«veo la energía del enemigo pero no la mía»— y
  la carga eran tres rayitas centradas que no eran de nadie, con el
  multiplicador saliendo un instante en el cartel de abajo. Ahora bajo tu
  barra pone **TÚ** con tus puntos de vida y bajo la suya los de él, y la
  carga vive en **tu lado**: rayitas que laten, el **×1.5 / ×2 / ×2.5**
  puesto mientras dure, y un **aura alrededor de tu bicho** que crece y late
  más rápido con cada carga y se apaga cuando sueltas el golpe. Sin eso,
  cargar era un turno en el que no pasaba nada visible, que es lo contrario
  de una apuesta.
- **Y se VE quién pega a quién.** Era la queja de raíz: dos sprites quietos y
  una línea de texto no son un combate, son un marcador. Ahora hay pantalla
  **VS** al abrir —los dos retratos entrando por sus lados, nombres, etapa y
  la estrella si es jefe—, el gesto de cada uno aparece **sobre su cabeza**,
  el golpe **cruza la pantalla** con su estela, el impacto es un fogonazo con
  anillo que empuja al que lo recibe, y encima sale el daño subiendo o un
  **¡Esquiva!** si no ha entrado. El gesto va arriba y no en el centro
  precisamente porque el centro es por donde vuela el golpe: juntos se
  tapaban y no se leía ninguno de los dos.
- **Con qué pegas también se elige.** Cada técnica lleva forma según su
  orden: **simple** (fiable), **ráfaga** (tres golpes que se cuelan por media
  defensa) y **columna** (el doble de daño). **A** pide atacar y, si tienes
  más de una técnica abierta, rota además cuál lleva armada: pulsar A es
  «pega, y con esta». Estuvo partido en dos —con dos técnicas, A solo
  cambiaba de arma y no pedía el ataque nunca—, de modo que cuantas más
  técnicas ganabas, menos podías mandar. Sin nada armado pega con la simple.
- **La columna es lenta**, y esa es su pega de verdad: si el rival ataca a la
  vez, no llega a salir y te comes su golpe entero. Sin eso hacía 38 de daño
  contra los 20 de la simple y era la respuesta correcta siempre. Ahora las
  tres son respuestas a preguntas distintas: la simple nunca es un error, la
  ráfaga es para los duros, y la columna es una apuesta a que el otro no
  ataca este intercambio.
- **La esquiva vuelve al combate.** Se había quedado sin usar al pasar a
  decisiones, así que entrenar velocidad no hacía nada dentro de la pelea. La
  columna la dobla; la ráfaga la tira tres veces, una por golpe, y por eso
  falla a trozos en vez de del todo.
- **Estados alterados**: veneno (quema el 5 % de vida por intercambio),
  parálisis (te roba uno) y debilidad (−35 % de ataque). Cuál deja cada bicho
  lo decide su **arquetipo**, que se puede mirar en la enciclopedia: una
  planta envenena, una máquina paraliza, un ángel debilita, un dragón no deja
  ninguno. El 58 % de las fichas no deja estado, a propósito: si lo dejaran
  todas, dejaría de ser una amenaza y sería el clima. Se ven bajo la barra de
  vida de cada uno.
- **Cinco comidas, y cada una es un trato distinto**: ración (llena poco,
  nunca se acaba), ración grande (llena el doble, engorda el triple), carne
  (da **vigor**: ataque de más durante los próximos combates), fruta omni (no
  llena, **cura** enfermedad y veneno) y **en mal estado** (llena igual… y te
  envenena). Se eligen en su pantalla, porque un sistema de cuidado con un
  solo verbo no tiene decisiones dentro.
- **La ración es infinita a propósito**: que un fallo de la caza pueda dejar a
  un bicho sin nada que llevarse a la boca sería un bug con forma de hambruna.
- **El veneno de la comida dura fuera del combate**: mientras lo lleva, el
  ánimo cae al doble y **entra envenenado a las peleas**. Se quita con la
  medicina o con una fruta omni. Un estado que se borrase al abrir el combate
  no sería un castigo, sería un adorno de la pantalla de casa.
- **Cazar**: tres rastros y eliges uno. Detrás hay siempre uno bueno —lo que
  dé esa zona— uno del montón y uno que sienta mal, así que el riesgo es
  legible: un tercio si eliges a ciegas. Cuesta **12 de rastro**, que se
  acumula andando, o sea que comer bien queda atado a haber estado usando el
  ordenador. Con la **velocidad** entrenada se descarta un rastro malo antes
  de elegir; nunca dos, porque entonces dejaría de haber decisión.
- **Cada zona da lo suyo**: en la jungla y el Área Oscura hay fruta, en el
  Rugido del Dragón carne, y el Imperio de Metal da lo justo. Ninguna tabla
  ofrece raciones normales: encontrar algo que ya tienes infinito es volver
  con las manos vacías sin que nadie te lo diga.
- **Bits**: la moneda. Sale de pelear, escalada por la etapa del rival —×5 del
  jefe— y de cobrar objetivos. Premia lo mismo que la experiencia: subir de
  nivel de juego, no repetir mil veces el combate más fácil.
- **Diecinueve objetivos** en cuatro familias —crianza, colección, combate y
  **exploración**— con su progreso a la vista y su recompensa. Los cuatro de
  exploración se añadieron al cerrar la carretera: era el sistema más grande
  del juego y no tenía ni una meta colgando, así que se andaba porque sí. **Se cobran a mano**: un premio que
  entra solo mientras miras otra pantalla no se siente como un premio, se
  siente como un número que cambió.
- **Mercado**: comida, vitaminas, cinta de correr y el **Anticuerpo X**, que
  a 400 bits es la única compra que hay que proponerse. Vender da la mitad —ni
  más, que sería una máquina de bits, ni cero, que haría inútil el excedente—
  y la ración no se vende, porque es infinita.
- **Bolsa**: comida y objetos en la misma lista, porque el jugador no piensa
  «comida» y «objeto», piensa «qué llevo encima».
- **Los jefes sueltan Digimentales**, uno distinto por zona. Es lo que
  convierte al jefe en algo más que una barra de vida.
- **Las tres evoluciones especiales, por fin jugables.** Estaban en los datos
  desde el principio sin manera de usarlas:
  - **Armor** — con el Digimental que soltó un jefe. 48 especies, 136
    evoluciones, once Digimentales y todos abren alguna.
  - **X** — con el Anticuerpo. 117 parejas, emparejadas por nombre y no por
    condiciones, que es mucho más fiable.
  - **Warp** — sin objeto: **cero descuidos** y el doble de todo lo que pide
    una evolución normal. Salta **una etapa exacta**.
- **Las cinco vías en una sola lista**, con A se pasan: normal, Warp, Armor, X
  y Jogress, cada una con su color, en qué te conviertes y **lo que cuesta**.
  Enterarse de que un Armor gasta el Digimental que te costó un jefe después
  de pulsar no es enterarse.
- **Duelo por código**: tu equipo —el que llevas encima más los dos primeros
  de la guardería— se empaqueta en un código de 29 caracteres que se pasa
  copiando y pegando. Pegas el de otra persona y peleáis **tres asaltos, uno
  contra uno**, a ganar dos. Sin servidor y sin cable, que es lo que hacían
  los aparatos por infrarrojos.
- **Los asaltos se juegan a mano**, con la misma pantalla de combate de
  siempre. Resolverlos de golpe y enseñar un marcador habría tirado por la
  borda todo lo que costó que pelear fuese una decisión.
- **En un duelo no cuenta el cuidado ni el aliado**: ni hambre, ni
  enfermedad, ni zona, ni vigor. Si contaran, ganaría quien hubiera abierto la
  barra más recientemente. Lo único que decide es **a quién has criado y
  cómo** — medido: contra un equipo entrenado a tope se gana menos de la mitad
  que contra uno crudo.
- **Ni experiencia, ni datos, ni jefes**: un asalto de duelo no se cobra como
  un combate del mundo, y los bits solo se pagan **la primera vez que ganas a
  ese equipo**. Sin las dos cosas, pegar el código de un amigo en bucle sería
  la mejor manera de jugar a todo lo demás.
- **El código se lee de un campo de texto**, no de la API de portapapeles de
  k4: esa pide permiso a propósito —lleva contraseñas y tokens— y gastarlo en
  un juego sería desproporcionado. Un `TextInput` acepta Ctrl+V sin permiso
  ninguno, y el tuyo sale en un campo seleccionable para poder copiarlo.
- **Alfabeto Crockford base32**: sin las letras que se confunden al copiar a
  mano, y con equivalencias al leer —una «O» por un cero sigue valiendo—.
  Lleva una suma de comprobación que **caza el 100 % de los cambios de una
  letra**: un código mal copiado dice que está mal en vez de darte otro equipo
  sin avisar.
- **El aliado**: la llamada ya no multiplica tu golpe —eso era una cifra—,
  sino que saca de la guardería **al mejor que hayas criado**, que pega una
  vez y se va. Mismo botón, misma energía, y por fin criar a un segundo bicho
  sirve para algo dentro del combate. Se pulsa su chapa en la esquina, porque
  vivir solo en la tecla `L` dejaba media mecánica escondida detrás de un
  teclado que el compositor ni cede si no pinchas la superficie. Sin
  guardería, la llamada vieja sigue ahí.
- **El rastro se gasta OLFATEANDO.** Al absorber la caza dentro de la
  carretera le quité su único precio y se quedó en un contador que solo subía
  y no hacía nada — dinero muerto guardado en la partida. Ahora se gasta en lo
  que lleva su nombre: 25 de rastro descartan una huella mala más antes de
  elegir. Nunca hasta dejar una sola opción, que sería regalar la respuesta.
- **Los rastros son CUATRO, no tres**, y es por aritmética: con tres y la
  pista gratis de la velocidad ya solo quedaban dos sin marcar, así que
  olfatear no cabía y pagar por él solo funcionaba con la velocidad baja —
  justo al revés de lo que tiene sentido. Con cuatro, la pista deja tres,
  olfatear deja dos, y sigue habiendo que elegir.
- **De un combate se puede HUIR**, pagando 2 de energía. Tapa un hueco real:
  hasta ahora no se podía salir de una pelea, así que toparse con un jefe que
  te supera te obligaba a perder — y perder cuesta ánimo, hambre y una derrota
  en el expediente. Huir no deja ni victoria ni derrota: no ha pasado nada. Y
  como la energía es también lo que mueve al aliado, escapar hoy es no poder
  llamar mañana. De un duelo por código no se huye: sería ganarlo sin jugarlo.
- **Energía y llamada**: `L` gasta tres de energía por un ataque con carga
  máxima. La energía sube sola con el tiempo —al doble mientras duerme— y
  ganar un combate recarga uno.
- **Nueve fondos**, uno por zona, generados con la herramienta de imágenes y
  ya en el verde del LCD.
- Estadísticas derivadas de la ficha real: etapa, atributo, arquetipo del
  `type` y cuántas técnicas conoce. Un dragón pega y una máquina aguanta.
- Técnicas con su nombre real en cada golpe, rotando entre las que conoce.
- Ventaja de terreno: pelear en tu propio campo favorece, y el enemigo
  siempre juega en casa.
- Entrenamiento con minijuego de puntería: tres tiros a un blanco que se
  estrecha y se acelera.
- **Colección**: al evolucionar o abrir otro huevo, el anterior se queda en
  la guardería (hasta cinco) en vez de desaparecer. Se cambia de bicho desde
  el aparato, y los de la guardería no pasan hambre ni se ensucian.
- **Captura por datos**: ganar un combate deja, una de cada tres veces, los
  datos de esa especie; del jefe de zona, siempre. Nunca te llevas al bicho:
  te llevas el **huevo de su línea** y lo crías tú desde Baby I.
- **Incubación andando**: el huevo puesto rompe a los 24 pasos, y los pasos
  son los tuyos —cambiar de ventana incuba—.
- **Dos niveles en la enciclopedia**: *visto* (peleaste contra él) y
  ★ *criado* (lo sacaste adelante). Lo primero se rellena solo; lo segundo
  cuesta.
- Enciclopedia de lo descubierto: 1131 de las 1488 especies son
  alcanzables por la escalera (el resto son Armor, Hybrid y sin etapa).
- **Cuatro estadísticas entrenables por separado** —PV, ATQ, DEF y VEL—, cada
  una con su minijuego: aguante, puntería, bloqueo y **la pelota FUERA del
  aparato** (el bicho sale de la carcasa, cruza el escritorio por encima de
  tus ventanas, recoge la pelota donde la sueltes y vuelve).
- **Dificultad elegible**: suave ×1, normal ×2, duro ×3 — y en duro, fallar
  del todo cuesta el doble de ánimo.
- **Las técnicas se ganan entrenando el ATAQUE**: una cada seis puntos, hasta
  las cuatro de su ficha. Un recién nacido solo sabe pegar de una manera.
- **Un renglón discreto bajo el bicho** que cuenta lo que está pasando: que le
  sobra peso y por eso va lento, que el camino está parado esperándote, que
  tienes objetivos sin cobrar, o simplemente la nota de su carácter. Existe
  porque el juego tiene muchas reglas que solo se notan si alguien te las
  dice, y **una regla invisible es indistinguible de un fallo**.
  Tres cosas lo mantienen disimulado y no en un tutorial: solo aparece si hay
  algo que decir —con todo en orden no está—, **cuenta el porqué y no da la
  orden** («le sobra peso: eso le quita velocidad», no «entrena velocidad»), y
  se apaga solo al arreglar la cosa, sin nada que marcar como leído. Va
  rotando cada 7 s entre lo que aplique, lo más urgente primero.
- **El pie de la pantalla es una columna**: medidores y renglón apilados. Los
  tenía anclados al fondo por separado y se pisaban —los cuadraditos salían
  encima del texto—. Una columna no puede solaparse consigo misma y además se
  encoge sola cuando no hay consejo.
- **Reacciones**: cada acción que ocurre de verdad hace saltar al bicho con
  su símbolo, **y el símbolo sube también por encima de la pantalla que
  tengas puesta**. Lo segundo hacía falta porque lo primero se rendía si no
  estabas mirando al bicho: desde la fase 4 se come desde la BOLSA, así que
  dar de comer —la acción más repetida del juego— había dejado de tener
  animación sin que nadie lo notara. Lo mismo le pasaba a la caza, que ocurre
  con la pantalla de rastros delante.
- **Ninguna acción es muda.** Se auditó la lista entera contra las señales del
  servicio y había cinco que no sonaban ni se veían: usar un objeto, comprar,
  vender, cobrar un objetivo y cambiar de bicho en la guardería. Poner un
  huevo a incubar y cambiar la dificultad tampoco. Todas tienen ya su sonido y
  su símbolo, y hay un sonido nuevo —`moneda`— para lo que mueve bits.
- **Sonido**: catorce pitidos de onda cuadrada para los botones, el cuidado,
  la evolución, el combate y el entrenamiento. Se apagan en Ajustes.
- Indicador en la píldora solo cuando el bicho reclama algo, y **se pincha**
  para volver al juego: si lo que reclama es un combate abre el mapa, si es
  hambre o una evolución abre el bicho. Funciona con la island desplegada
  (reloj o reproductor); en reposo la píldora solo se mira, que es como k4
  trata todos los indicadores.

## Decisiones que no son obvias

**El grafo de la API es enciclopédico, no de juego.** Las evoluciones de
Agumon incluyen a Agnimon (un spirit de Frontier) y a Agumon (Black)
X-Antibody. Todo candidato se filtra al peldaño siguiente y se descartan
los que no tienen futuro: sin eso, una mala tirada deja al jugador en un
callejón sin techo y sin poder saberlo.

**Un Digimon puede figurar en varios niveles.** Guardar uno solo falsea la
escalera, así que el índice guarda la lista y el juego pregunta por
pertenencia.

**El hambre corre con la barra cerrada, la muerte no.** Al fondo del
descuido hay enfermedad y regresión, que duelen y se remontan. Matarlo a
espaldas del jugador sería cobrarle por cerrar el portátil.

**La island se abre con la forma del aparato, y por eso no pinto cuerpo.**
La silueta que dibuja el host no es un rectángulo redondeado: abajo tiene
radio 32 y arriba unas «alas» invertidas que se funden con el borde de la
barra. Cualquier cuerpo propio se saldría por ahí, así que el fondo de la
island ES la carcasa y encima solo van bisel, pantalla y botones.

**El combate ya no se resuelve solo.** Antes el servicio decidía la pelea
entera y la vista reproducía un resultado escrito: se veía bien y no era un
juego. Ahora cada choque lo decide mitad el bicho y mitad tú. La regla vive
en `intercambio()`, una sola, y la usan los dos caminos —el jugado y el del
IPC, que empuja un 0,5 fijo— para que no puedan divergir.

**La pelota sale de la barra.** Se apoya en `K4.Ventana` —una capa
transparente a pantalla completa— y en `K4.Isla.rect` para que el bicho
salga justo de la island. Ojo con `rect`: da `{x, y, ancho, alto}`, con esos
nombres; usando `width`/`height` de QML sale `undefined` y la escena entera
se coloca en NaN.

**Las técnicas rotaban todas desde el primer día.** Un Baby I recién nacido
usaba su técnica definitiva, así que entrenar solo subía un número. Ahora se
desbloquean con el esfuerzo y entrenar cambia cómo pega.

**Capturar da datos, no mascotas.** Llevarte al rival tal cual —con su etapa
y sus stats— habría sido más inmediato y se habría cargado la crianza:
acabarías con un equipo de Adults que no has criado y evolucionar dejaría de
importar. El aparato guardaba datos, no bichos, y eso es justo lo que hace
falta aquí.

**El huevo de una línea sale de un hash, no del alfabeto.** El grafo de la
API es una red y no un árbol: bajando por `prior` a lo bruto, TODAS las
especies acababan en el mismo nudo, y bajando peldaño a peldaño por orden
alfabético «Algomon (Baby I)» salía de huevo para siete de cada ocho. Con un
hash de la especie capturada cada una tiene su huevo y siempre el mismo: 105
huevos distintos para los 360 Adult. Y si la bajada se atasca —hay peldaños
sin predecesor: Angewomon se quedaba en un Child— cae a un Baby I de verdad,
porque un huevo que no es Baby I no es un huevo.

**Evolucionar dejaba de existir al anterior.** Criabas un Jyarimon durante
horas y al subir de etapa no quedaba rastro de que hubiera existido: entrenar
y evolucionar no dejaban poso, y sin poso no hay colección. Ahora lo que
dejas atrás queda marcado como criado, y el que llevabas al abrir otro huevo
se va a la guardería en vez de a la basura. Si está llena no se abre el
huevo: perder una crianza de horas por pulsar un botón sería imperdonable.

**Los de la guardería no pasan hambre.** Castigar por coleccionar es la forma
más rápida de que nadie coleccione.

**Despertarlo lo despierta.** `durmiendo` solo miraba el reloj, así que
molestarlo cobraba el descuido y el bicho seguía roncando: el aparato decía
«lo has despertado» y enseñaba las zzz a la vez. Y de paso apareció algo más
viejo: ese enlace dependía de la hora, que NO es una propiedad reactiva, así
que no se reevaluaba solo —al cruzar las 22:00 el bicho no se dormía hasta
que cambiara cualquier otra cosa—. Ahora cuelga del tick.

**Una acción que no se puede hacer LO DICE.** El botón de confirmar parecía
roto: pulsarlo sobre algo imposible —dar de comer con el estómago lleno,
curar a un bicho sano, limpiar un suelo limpio— no producía nada en pantalla.
Y el caso peor era alimentar dormido, que sí hacía algo: sumaba un descuido
sin decir ni pío. Un castigo invisible es peor que un botón muerto. Ahora el
servicio emite `aviso(texto)` y el aparato lo enseña dos segundos.

**Entrenar es decidir en qué quiere ser bueno.** Antes había una «fuerza»
única que subía sola: un número, no una decisión. Ahora son cuatro
estadísticas con su propio minijuego, y el minijuego encaja con lo que
entrena —aguantar para la vida, apuntar para el ataque, bloquear para la
defensa, correr para la velocidad—. Es lo que hace Digital Tamers con sus
salas por estadística.

**El tope de entreno existe para que evolucionar siga importando.** Está
calibrado con una regla explícita, y hay una prueba que la vigila: *un bicho
entrenado a tope vale más o menos lo que uno de la etapa siguiente sin
entrenar*. Con los primeros números un Child a tope hacía 178 PV y 34 ATQ
contra los 118 y 15 de un Adult recién nacido —lo aplastaba—, y subir de
etapa dejaba de ser la recompensa que organiza el juego.

**Las partidas viejas se migran.** Guardaban una sola `fuerza`, que se
reparte a partes iguales entre las cuatro: quien ya jugaba no pierde nada.

**Lo que señalas es lo que ves.** El menú y la pantalla iban por su cuenta:
entrabas en el mapa, recorrías hasta «Comer» y seguías mirando el mapa con
su «¡Pelear!» encima. Ahora recorrer el menú cambia la pantalla —los iconos
que MIRAN tienen la suya, los que ACTÚAN enseñan al bicho, que es sobre
quien actúan— y B queda solo para actuar, no para navegar. Dentro de una
lista A pasa fichas y se sale con C, que es lo único que cabe en tres
botones.

**El original no te pide NADA en combate.** Sus cuatro fases —`obj_turn_attack`,
`obj_turn_prep_def`, `obj_turn_defense`, `obj_turn_collision`— van todas por
`Alarm` y `Step`: ni una tecla. Es fiel y es un vídeo. Pero aporrear un botón
tampoco valía, porque aporrear es esfuerzo y no decisión, y aburre por lo
mismo que aburre mirar. Así que esas cuatro fases pasan a ser tres cosas que
ELIGES, una por choque. La gracia del original estaba en la preparación
—criar, entrenar, evolucionar— y el combate era el marcador; aquí es además
una lectura del rival.

**Una sola regla para los dos caminos.** `resolverCombate` —el del IPC y las
pruebas— encadena LOS MISMOS choques eligiendo al azar. Antes tenía su propio
bucle de esquivas: dos reglas para lo mismo, que es lo que acaba divergiendo
en cuanto se toca el triángulo.

**La energía le da a la pelea un segundo verbo.** Aporrear es constancia;
llamar es elegir el momento, y lo que gastas no sale de tus dedos sino de
haber dejado descansar al bicho. El empujón de la llamada son 0,35 —unos
cuatro aporreos juntos—: suficiente para dar la vuelta a un choque perdido,
insuficiente para ganar un combate entero, porque hay ocho de energía y cada
llamada cuesta tres.

**Y le da sentido a dormir.** La energía sube al doble mientras duerme, así
que el sueño deja de ser solo «no molestes» y pasa a ser el sitio donde se
recupera lo que gastas peleando. Es lo único del cuidado que avanza de noche.

**Los números del choque están medidos, no puestos a ojo.** El rival arrastra
0,2 por segundo y cada pulsación aporta 0,09: contra un igual bastan dos
pulsaciones por segundo para no perder terreno y unas cinco para atravesarlo.
El primer intento fue 0,3 contra 0,055 —más de cinco por segundo solo para
empatar— y con eso el jugador no podía cambiar el resultado ni queriendo,
que es justo el clicker del que se venía huyendo.

**Los pasos los cuenta el servicio; el combate te espera.** Con el reloj
en la vista, la island se cierra al sacar el ratón y `pasos` se quedaba en
1 tras dos minutos de exploración. Pero resolver el combate solo devuelve
derrotas que nadie vio. Así que se explora siempre y el encuentro queda
esperando en el mapa —y avisando en la píldora— hasta que lo empiezas tú.

**Y un encuentro avisa, pero no te saca de donde estás.** Al principio hacía
`escena = "mapa"` a secas. El problema no es interrumpir —un aparato de estos
interrumpe—: es QUIÉN dispara la interrupción. El encuentro lo trae la
carretera, y la carretera avanza con lo que haces en el **escritorio**, no
con lo que pulsas en el aparato. Así que podías estar dándole de comer a tu
bicho y aparecer en el mapa a media pulsación sin haber tocado nada aquí.
Pasó tal cual: «estaba en la zona de Casa y me salió el combate contra JEFE».
Ahora sale un cartel —«¡%1 te corta el paso!», o «¡EL JEFE TE CORTA EL PASO!»—
y el **icono del mapa se queda en ámbar con un punto rojo latiendo** hasta
que vas. El cartel dura dos segundos y el punto no: quien no llegue a leerlo
tiene que poder enterarse igual. No se pierde nada por esperar, porque el
encuentro bloquea el camino hasta que lo resuelvas. De la caza sí te saca:
esa pantalla se apodera de los tres botones, y un aviso debajo de un sitio
del que no puedes salir no avisa de nada.

**El paisaje solo se mueve al dar un paso.** Es la regla que dejó escrita la
Mazmorra en su `Fondo.qml` y aquí vale doble: en una pantalla de 250 píxeles
un fondo que nunca para no deja mirar nada más. Y así el movimiento significa
algo —cada tranco es un paso que has dado tú— en vez de ser decoración.

**El jefe de cada zona es el especialista, no el más grande.** La primera
puntuación premiaba tener muchas técnicas Y estar en muchos campos, y con eso
Greymon —que está en media base de datos— salía de jefe en seis zonas de
nueve. Nueve zonas con el mismo jefe es una zona. Restando por número de
campos gana el que suena a esa zona: Bakemon en Pesadilla, Ballistamon en el
Imperio de Metal, Devimon en el Área Oscura. Las nueve salen distintas, y hay
una prueba que lo vigila.

**Perder contra el jefe no borra el camino andado.** Sigue esperando en la
zona. Mandar al jugador a empezar de cero castigaría el intento, que es justo
lo que se quiere premiar.

**La suciedad va por comidas, no por reloj.** Si no ha comido no ensucia:
así el suelo sucio es consecuencia de cómo lo cuidas y no del tiempo que
pasa, que es lo que la ata al juego en vez de al calendario.

**Alimentar de más ya no es una acción vacía.** Antes, con los corazones
llenos, `alimentar()` devolvía `false` y no pasaba nada: dar de comer no
tenía coste y cuidar se reducía a pulsar un botón cuando había hambre. Eso
era el clicker que quedaba.

**El peso arranca de nuevo en cada evolución.** Un cuerpo nuevo tiene su
propia báscula; arrastrarlo dejaría a un Ultimate pesando lo de un Child.
Las partidas anteriores a la báscula se migran al mínimo de su etapa al
cargarlas, porque un peso de 0 no es «está flaco», es «no había peso».

**Las estadísticas salen de la ficha, no de un hash.** Antes se fabricaban
solo con el id, o sea que dos Adult se diferenciaban por un número invisible:
el jugador no podía leer por qué uno era mejor. Ahora salen de etapa,
atributo, tipo y técnicas, y eso se mira en la enciclopedia y se entiende.
Los 144 `type` distintos se agrupan por palabra clave, en orden, porque una
tabla exhaustiva de "Bewitching Beast" y "Small Dragon" sería absurda.

**El combate se calienta a partir del turno 16.** Dos bichos muy defensivos
—un Mineral contra un Slime, ambos Data— pegaban en el suelo de 1 y no se
mataban en cuarenta turnos: 10 de cada 300 se quedaban colgados. Escalar el
daño los resuelve y, de paso, vuelve dramático un combate largo.

**El repaso de lo que pasó fuera va a trozos de 15 minutos.** Preguntando
una sola vez si el bicho duerme, con la hora a la que VUELVES, una noche
entera contaba como ocho horas de hambre: volver por la mañana te lo
encontraba enfermo por haber dormido.

## El sonido

Lo genera `tools/digivice_sonidos.py`: ondas cuadradas sintetizadas, no
grabaciones. Un juguete de LCD no tiene altavoz para más que eso, así que la
fidelidad y no usar nada de nadie apuntan al mismo sitio. Son 14 ficheros,
118 KB en total, en `plugins/Digivice/sonidos/`.

**WAV sin comprimir a propósito**: `K4.Sonido` carga los WAV con
`SoundEffect`, que los tiene en memoria y los dispara sin latencia. Todo lo
demás pasa por `MediaPlayer`, que abre el fichero al reproducir y llega
tarde — en el golpe de un combate eso se nota. Ningún otro módulo de k4 usa
WAV (todos van por `delSistema()`, que devuelve `.oga`), así que esta es la
primera vez que se pisa esa ruta.

Solo suena lo que de verdad ha pasado: `alimentar()` devuelve `false` si el
bicho está lleno o dormido, y celebrar una acción que no ocurrió enseña al
jugador a no fiarse del sonido.

## IPC

```sh
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice toggle
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice nueva
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice estado
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice comer
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice mimar
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice entrenar
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice curar
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice evolucionar
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice ver mapa
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice zona "Dark Area"
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice pelear
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice sonidos
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice pitar golpe
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice huevos
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice incubar 0
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice eclosionar
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice guarderia
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice sacar 0
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice fusiones
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice fusionar 0
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice tecnicas
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice aliado
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice despensa
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice comerDe carne
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice cazar
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice rastro 1
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice objetivos
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice cobrar ganar10
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice bolsa
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice comprar antidoto
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice vender carne
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice usar vitamina pv
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice vias
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice armor 0
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice equis
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice warp
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice codigo
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice leer "<código>"
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.digivice duelo "<código>"
```

`leer` descifra un código sin pelear, para comprobar que lo que te han pasado
es lo que crees antes de gastar tres asaltos en averiguarlo; `duelo` resuelve
los tres sin manos.

`vias` dice qué maneras de evolucionar tienes abiertas AHORA: sin eso no hay
forma de saber desde fuera si un Digimental sirve de algo con el bicho que
llevas encima.

`cazar` monta la cacería y enseña los rastros; `rastro n` sigue uno. Va en dos
pasos y no en uno porque elegir ES la mecánica: resolverlo de golpe sería
probar otra cosa. Cuando se niega, dice por qué —dormido, enfermo o sin
rastro—: desde la terminal un «no se puede» a secas obliga a adivinar.

`tecnicas` dice qué formas tienes abiertas —es lo que decide si el selector
del combate aparece— y `aliado` dice quién saldría de la guardería y qué
haría. `pelear` ahora cuenta también con qué formas se peleó, cuántos estados
prendieron y si el aliado llegó a salir: con formas y estados, «derrota en 10
turnos» ya no cuenta el combate.

`sonidos` dice cuántos han cargado —un WAV que no se encuentra no da error,
simplemente no suena— y `pitar` dispara uno a mano, para separar «el fichero
no está» de «el altavoz está en silencio».

`pelear` resuelve el encuentro que esté esperando y devuelve cómo fue
(`derrota contra Wanyamon en 10 turnos · 0/9 PV`). La vista lo enseña con
animación; esto es para jugar sin ratón y para poder probarlo desde la
terminal.

En la vista, el teclado hace lo mismo que los botones: `A` (o ←) recorre el
menú —y **llama** en combate—, `B` (o espacio) elige y empuja, `C` (o
retroceso) vuelve.

## Cómo se cierra

Con el icono del **aspa** del menú —el último—, con **ESC**, o volviendo a
abrirlo. El aspa es
la que siempre funciona: con `tecladoOpcional` el compositor solo da el
teclado si pinchas la superficie, así que abierto por IPC o por atajo el ESC
no llega. Y el fondo de la vista **se traga el clic** en vez de abrir el
centro de control, que es lo que hace el host por defecto.

## Pruebas

Las reglas puras se ejercitan sin arrancar la barra:

```sh
node tools/digivice_test.js
node tools/digivice_balance.js
python3 tools/digivice_glifos.py
```

`digivice_balance.js` no comprueba que las reglas sean correctas —de eso va lo
anterior— sino que **el juego se pueda jugar**: cuánto se tarda en llegar
arriba, cuántos combates hacen falta, si la economía cierra y si el castigo
por descuidar al bicho es proporcionado. Lee las constantes del servicio en
vez de copiarlas, para que no se separen. Existe porque «está equilibrado» sin
números es una opinión.

Comprueba lo que puede romper la partida y no se ve mirando: que toda rama
alcanzable llegue a Ultimate sin callejones, que ninguna zona se quede sin
habitantes en alguna etapa, que el combate a igual etapa esté repartido, que
un dragón pegue más que una máquina y que criar mal se note.

Del combate comprueba que **ninguna forma de ataque domine** —el día que una
sea siempre la correcta, elegir con qué pegar deja de ser una decisión—, que
la ráfaga gane a la simple contra un rival duro y la pierda contra uno blando,
que una columna pillada en colisión no salga, que la parálisis robe
exactamente un intercambio, y que un golpe fallado no deje estado.

`digivice_glifos.py` dice **qué dibuja** cada icono, por su nombre real en la
fuente. Existe por un fallo que ningún validador podía cazar: los códigos que
había elegido a ojo existían todos —así que nada daba error— pero dibujaban
otra cosa. La ración era un cerdo, la carne una cámara de vídeo, la comida en
mal estado un coche y el rastro **el logo de Rollup.js**; y de paso salió que
el menú entero llevaba iconos equivocados desde antes: «Comer» era un
picture-in-picture y «Huevos», un pingüino.

Del meta-juego comprueba que **vender nunca dé más que comprar** —con eso el
mercado sería un bucle infinito de bits—, que ningún objetivo pida más de lo
que existe en el juego, que ningún premio sea un objeto inventado, que **cada
Digimental abra alguna evolución** (uno que se soltara sin servir para nada
sería basura ocupando sitio) y que **todo Warp salte una etapa exacta**.

Del duelo comprueba lo que no se ve: que la ida y vuelta del código sea
**exacta** sobre 597 equipos, que **cualquier** cambio de una letra se cace
antes de pelear —al principio se colaba uno—, que el entrenamiento venga
recortado al tope de su etapa (un código editado a mano no puede traer un
Child con todo a 63) y que con equipos desiguales manden los asaltos del más
corto, para que traer más bichos no sea ganar.

De la comida comprueba que las cinco sean tratos **distintos** —el día que dos
hagan lo mismo, elegir deja de ser una decisión—, que solo la ración sea
infinita, y que **ningún rastro dé algo que ya tienes infinito**.

De la evolución comprueba además que cada etapa pida más que la anterior,
que faltando una sola cosa no se deje subir, y que el Jogress sea
**simétrico** —A+B y B+A tienen que dar el mismo— y no apunte nunca a una
especie que no está en el índice.

## Siguiente bloque

El plan por fases vive en Edinot (`Proyectos/k4/Digivice/Digivice — plan de
ejecución`). Hechas: **1** (entreno por estadística), **2** (evolución
completa: XP, requisitos a la vista y Jogress), **3** (combate: formas de
ataque, estados y aliado), **4** (comida y caza), **5** (meta-juego: bits,
objetivos, mercado, drops y las tres evoluciones especiales) y **6** (duelo
por código).

Con esto el plan por fases queda **cerrado entero**. Lo que queda son ideas,
no deudas: más zonas, más minijuegos de entrenamiento, y arte propio para
poder empaquetar los sprites en vez de pedirlos a Wikimon.

## Que cada pantalla sea un sitio

Después del plan vino un trabajo distinto, que no añade mecánica: hacer que
lo que ya había **se vea**. El mapa, la caza y el combate se hicieron
primero; luego quedaban cuatro que seguían siendo listas de texto —«cuatro
listas planas»— y se rehicieron con el mismo criterio.

La regla común: **una pantalla es un sitio, con un fondo, alguien dentro, y
una reacción a lo que haces**. Y ninguna de las cuatro cambió una sola regla
del juego.

- **Enciclopedia — el bicho en su hábitat.** El índice trae el campo `f` de
  cada especie («Nature Spirits», «Dragon's Roar»…), y de esos campos ya
  teníamos nueve fondos dibujados para el mapa. Ahora cada ficha se ve sobre
  el paisaje de su zona, con el nombre puesto, y el bicho **pasea** por él en
  vez de posar. La ficha entra deslizándose al pasar página. Antes quince
  especies distintas se veían exactamente igual: un recuadro negro y cuatro
  líneas.
- **Mercado — un puesto con mostrador.** Los seis artículos en un estante
  con lo que llevas de cada uno, el señalado grande sobre el mostrador
  meciéndose, y **tu bicho ha venido contigo** —no un tendero inventado: el
  que compra es él—. Al comprar, el artículo **cae del mostrador**, el bicho
  **salta con él encima**, el contador de bits **se sacude** y sale el «−10»
  de lo que acabas de pagar. Lo que no te puedes permitir se apaga y el
  bicho se desanima ANTES de que insistas.
- **Objetivos — barras y sello.** «3/10» no es progreso, es una fracción:
  con quince objetivos obliga a dividir quince veces. Ahora cada renglón
  lleva **su barra del color de su familia**, arriba hay una barra del total
  cobrado, los que están listos **laten**, y cobrar **estampa un sello** en
  el objetivo y **manda los bits volando** al contador, que acusa el golpe.
- **Guardería — una sala, no una ficha.** El premio de la guardería es tener
  **varios**, y enseñando uno cada vez doce criados se veían igual que uno.
  Ahora están todos: los demás al fondo, repartidos y respirando a
  destiempo; el señalado **un paso al frente** con halo y ficha; y al
  sacarlo **cruza la sala** mientras el que llevabas **entra por el lado** a
  ocupar su hueco, que es literalmente lo que hace el cambio.

Tres trampas que dejó este trabajo, por si vuelven:

- **El LCD es mucho más alto de lo que parecía** (`bisel.height - 30`, ~215
  px). Las cuatro pantallas usaban el tercio de arriba y dejaban el resto en
  negro; la enciclopedia llegaba a cortar la descripción en «…» al final del
  primer renglón teniendo sitio de sobra debajo.
- **Colocar por pseudoaleatorio no reparte.** Los seis de la guardería
  salieron amontonados a la derecha, unos encima de otros, y con calvas en
  el resto de la sala. Repartir por índice llena siempre.
- **Una lista que se reordena al actuar deja el cursor apuntando a otro.**
  El sello de «cobrado» caía sobre el renglón señalado, y al cobrar los
  cobrados se van al fondo: marcaba como cumplido el de debajo. Va por id.
