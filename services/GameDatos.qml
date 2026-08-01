pragma Singleton

//  Los catálogos de la mazmorra: rasgos, especies, clases, tienda y metas.
//
//  Separados del cerebro (Game.qml) porque son DATOS: setecientas líneas de
//  literales que no deciden nada. Game los reexporta con alias, así que para
//  el resto del código nada ha cambiado de sitio.
//
//  Van tras un ternario con juegoActivo: con la mazmorra apagada no se
//  construye ni un objeto — «apagada no ocupa sitio» también al instanciar.

import QtQuick
import Quickshell
import "../core"

Singleton {
    // ── rasgos de los enemigos ────────────────────────────────────
    //
    //  Pasada cierta oleada los monstruos dejan de ser sacos de vida y traen
    //  algo propio. Se resuelven por efecto, igual que las habilidades de los
    //  héroes, para que añadir uno nuevo sea una línea en esta tabla.
    //
    //  El orden importa: los primeros son molestos y los últimos cambian cómo
    //  hay que jugar. `ruptura` en particular existe porque el escudo era la
    //  respuesta a todo.
    readonly property var rasgos: !Settings.juegoActivo ? [] : [
        { id: "coraza",  nombre: Idioma.t("Coraza"),  desde: 12, color: "#8e8e93",
          desc: Idioma.t("aguanta mejor los golpes") },
        { id: "furia",   nombre: Idioma.t("Furia"),   desde: 25, color: "#ff453a",
          desc: Idioma.t("pega más fuerte cuanta menos vida le queda") },
        { id: "ponzona", nombre: Idioma.t("Ponzoña"), desde: 40, color: "#32d74b",
          desc: Idioma.t("envenena a quien golpea") },
        { id: "drenaje", nombre: Idioma.t("Drenaje"), desde: 55, color: "#bf5af2",
          desc: Idioma.t("se cura con el daño que hace") },
        { id: "ruptura", nombre: Idioma.t("Ruptura"), desde: 70, color: "#ffd60a",
          desc: Idioma.t("sus golpes ignoran los escudos") },
        { id: "eco",     nombre: Idioma.t("Eco"),     desde: 92, color: "#0a84ff",
          desc: Idioma.t("salpica al resto del grupo") }
    ]

    // Cuánto encaja un enemigo de cada tipo de daño según su carne. Un bicho
    // acorazado se come el acero pero no la magia, y al revés: es lo que hace
    // que llevar daño mixto importe.
    readonly property var defensaDe: !Settings.juegoActivo ? ({}) : ({
        fisica:      { fis: 0.68, mag: 1.18 },
        magica:      { fis: 1.18, mag: 0.68 },
        equilibrada: { fis: 1.0,  mag: 1.0 }
    })

    // ── habilidades de los enemigos ───────────────────────────────
    //
    //  Los rasgos son pasivos: actúan solos y todo el rato. Esto es lo otro,
    //  lo que se ve venir: golpes gordos con su propia recarga, igual que los
    //  de los héroes. Sin ellos una oleada es un goteo constante de daño y no
    //  hay nada que aguantar ni de lo que recuperarse.
    //
    //  `potencia` se mide en golpes normales suyos, así escala sola con la
    //  oleada y no hay que retocarla nunca.
    readonly property var habilidadesEnemigo: !Settings.juegoActivo ? [] : [
        { id: "embestida", nombre: Idioma.t("Embestida"), desde: 20, recarga: 9,
          efecto: "granGolpe", potencia: 3.2, forma: "onda" },
        { id: "escupitajo", nombre: Idioma.t("Escupitajo"), desde: 34, recarga: 12,
          efecto: "salpicar", potencia: 1.1, forma: "nube" },
        { id: "aullido", nombre: Idioma.t("Aullido"), desde: 48, recarga: 15,
          efecto: "enfurecer", potencia: 0.3, forma: "aura" },
        { id: "zarpazo", nombre: Idioma.t("Zarpazo atroz"), desde: 62, recarga: 11,
          efecto: "drenar", potencia: 2.4, forma: "cadena" },
        { id: "muda", nombre: Idioma.t("Muda"), desde: 76, recarga: 18,
          efecto: "sanar", potencia: 0.18, forma: "motas" }
    ]

    // ── especies ──────────────────────────────────────────────────
    //
    //  Los monstruos eran sprites anónimos con la misma vida y el mismo daño:
    //  cambiaba el dibujo y nada más. Cada uno tiene ahora nombre, un rasgo
    //  que le pega por naturaleza y su propia mezcla de aguante y pegada, así
    //  que una oleada de limos no se juega como una de murciélagos.
    //
    //  `vida` y `daño` son multiplicadores sobre lo que toca en esa oleada, y
    //  se compensan entre sí: lo que aguanta pega poco y al revés.
    readonly property var especies: !Settings.juegoActivo ? [] : [
        { nombre: Idioma.t("Limo"),              afinidad: "coraza",  vida: 1.35, daño: 0.75, defensa: "fisica", ataque: "fisico" },
        { nombre: Idioma.t("Limo helado"),       afinidad: "coraza",  vida: 1.30, daño: 0.80, defensa: "fisica", ataque: "fisico" },
        { nombre: Idioma.t("Cangrejo rojo"),     afinidad: "coraza",  vida: 1.25, daño: 0.90, defensa: "fisica", ataque: "fisico" },
        { nombre: Idioma.t("Mariposa espectral"), afinidad: "ruptura", vida: 0.70, daño: 1.25, defensa: "magica", ataque: "magico" },
        { nombre: Idioma.t("Osamenta"),          afinidad: "furia",   vida: 0.85, daño: 1.20, defensa: "magica", ataque: "magico" },
        { nombre: Idioma.t("Limo tóxico"),       afinidad: "ponzona", vida: 1.30, daño: 0.85, defensa: "fisica", ataque: "magico" },
        { nombre: Idioma.t("Araña"),             afinidad: "ponzona", vida: 0.85, daño: 1.15, defensa: "equilibrada", ataque: "fisico" },
        { nombre: Idioma.t("Espectro"),          afinidad: "ruptura", vida: 0.75, daño: 1.30, defensa: "magica", ataque: "magico" },
        { nombre: Idioma.t("Rata"),              afinidad: "furia",   vida: 0.70, daño: 1.10, defensa: "equilibrada", ataque: "fisico" },
        { nombre: Idioma.t("Murciélago"),        afinidad: "drenaje", vida: 0.65, daño: 1.30, defensa: "equilibrada", ataque: "fisico" },
        { nombre: Idioma.t("Jabalí"),            afinidad: "furia",   vida: 1.20, daño: 1.15, defensa: "equilibrada", ataque: "fisico" },
        { nombre: Idioma.t("Goblin"),            afinidad: "furia",   vida: 0.95, daño: 1.10, defensa: "equilibrada", ataque: "fisico" },
        { nombre: Idioma.t("Diablillo"),         afinidad: "eco",     vida: 0.90, daño: 1.25, defensa: "magica", ataque: "magico" },
        { nombre: Idioma.t("Seta andante"),      afinidad: "ponzona", vida: 1.25, daño: 0.85, defensa: "magica", ataque: "magico" },
        { nombre: Idioma.t("Cochinilla"),        afinidad: "coraza",  vida: 1.40, daño: 0.70, defensa: "fisica", ataque: "fisico" },
        { nombre: Idioma.t("Limo dorado"),       afinidad: "drenaje", vida: 1.15, daño: 0.95, defensa: "fisica", ataque: "fisico" },
        { nombre: Idioma.t("Oruga espinosa"),    afinidad: "ponzona", vida: 1.10, daño: 1.00, defensa: "equilibrada", ataque: "fisico" },
        { nombre: Idioma.t("Zombi"),             afinidad: "drenaje", vida: 1.20, daño: 0.95, defensa: "equilibrada", ataque: "fisico" },
        { nombre: Idioma.t("Cubo gelatinoso"),   afinidad: "coraza",  vida: 1.45, daño: 0.75, defensa: "fisica", ataque: "fisico" },
        { nombre: Idioma.t("Escorpión"),         afinidad: "ponzona", vida: 0.90, daño: 1.20, defensa: "equilibrada", ataque: "fisico" }
    ]

    // A los jefes se les nombra por bioma y altura, que es lo único que se
    // sabe con certeza del sprite que toca.
    readonly property var titulosJefe: !Settings.juegoActivo ? [] : [
        "Guardián", "Tirano", "Devorador", "Heraldo", "Coloso",
        "Verdugo", "Abominación", "Soberano"
    ]

    readonly property var deBioma: ["del bosque", "de la cueva", "del infierno", "del vacío"]

    // ── clases ────────────────────────────────────────────────────
    readonly property var clases: !Settings.juegoActivo ? [] : [
        {
            id: "tanque", nombre: Idioma.t("Guardián"), sprite: "h00",
            vida: 300, daño: 4, armadura: 6, magia: 0.0, resistencia: 2, papel: Idioma.t("Aguanta los golpes"),
            ataque: "Mandoble", glifo: 0xF0498,
            visual: { forma: "tajo", color: "#e5e5ea" }, reto: null,
            porNivel: { vida: 0.11, daño: 0.06, armadura: 0.6, resistencia: 0.42 },
            habilidades: [
                { nivel: 1, id: "provocar", nombre: Idioma.t("Provocar"),
                  desc: Idioma.t("Atrae los golpes y reduce el daño"), recarga: 18, glifo: 0xF0498,
                  efecto: "provocar", potencia: 6 },
                { nivel: 5, id: "muro", nombre: Idioma.t("Muro de escudos"),
                  desc: Idioma.t("Escudo para todo el grupo"), recarga: 26, glifo: 0xF0A38,
                  efecto: "escudoGrupo", potencia: 0.22 },
                { nivel: 12, id: "represalia", nombre: Idioma.t("Represalia"),
                  desc: Idioma.t("Devuelve parte del daño recibido"), recarga: 22, glifo: 0xF04E5,
                  efecto: "reflejo", potencia: 8 },
                { nivel: 20, id: "bastion", nombre: Idioma.t("Bastión"),
                  desc: Idioma.t("Inmune unos segundos"), recarga: 40, glifo: 0xF0498,
                  efecto: "invulnerable", potencia: 5 }
            ]
        },
        {
            id: "mago", nombre: Idioma.t("Hechicero"), sprite: "h02",
            vida: 130, daño: 12, armadura: 0, magia: 1.0, resistencia: 5, papel: Idioma.t("Daño en área"),
            ataque: "Dardo arcano", glifo: 0xF0E20,
            visual: { forma: "proyectil", color: "#bf5af2" }, reto: null,
            porNivel: { vida: 0.06, daño: 0.13, armadura: 0.1, resistencia: 0.42 },
            habilidades: [
                { nivel: 1, id: "llamarada", nombre: Idioma.t("Llamarada"),
                  desc: Idioma.t("Golpea a toda la oleada"), recarga: 14, glifo: 0xF0E20,
                  efecto: "area", potencia: 6 },
                { nivel: 6, id: "cadena", nombre: Idioma.t("Cadena arcana"),
                  desc: Idioma.t("Rebota creciendo en cada salto"), recarga: 18, glifo: 0xF0593,
                  efecto: "cadena", potencia: 3 },
                { nivel: 14, id: "meteoro", nombre: Idioma.t("Meteoro"),
                  desc: Idioma.t("Un golpe enorme al más sano"), recarga: 30, glifo: 0xF0F1B,
                  efecto: "golpeUnico", potencia: 16 },
                { nivel: 22, id: "quietud", nombre: Idioma.t("Quietud"),
                  desc: Idioma.t("La oleada deja de atacar"), recarga: 45, glifo: 0xF04AB,
                  efecto: "aturdir", potencia: 5 }
            ]
        },
        {
            id: "clerigo", nombre: Idioma.t("Clériga"), sprite: "h04",
            vida: 190, daño: 5, armadura: 3, magia: 0.6, resistencia: 3, papel: Idioma.t("Cura al grupo"),
            ataque: "Fulgor", glifo: 0xF05E1,
            visual: { forma: "destello", color: "#ffd60a" }, reto: null,
            porNivel: { vida: 0.09, daño: 0.07, armadura: 0.35, resistencia: 0.455 },
            habilidades: [
                { nivel: 1, id: "bendicion", nombre: Idioma.t("Bendición"),
                  desc: Idioma.t("Cura a todo el grupo"), recarga: 22, glifo: 0xF05E1,
                  efecto: "curaGrupo", potencia: 0.35 },
                { nivel: 7, id: "egida", nombre: Idioma.t("Égida"),
                  desc: Idioma.t("Escudo al más malherido"), recarga: 20, glifo: 0xF0A38,
                  efecto: "escudoUno", potencia: 0.45 },
                { nivel: 15, id: "renovar", nombre: Idioma.t("Renovación"),
                  desc: Idioma.t("Cura poco a poco"), recarga: 28, glifo: 0xF058C,
                  efecto: "regenerar", potencia: 10 },
                { nivel: 24, id: "volver", nombre: Idioma.t("Volver a la vida"),
                  desc: Idioma.t("Levanta a un caído"), recarga: 90, glifo: 0xF05E1,
                  efecto: "revivir", potencia: 0.5 }
            ]
        },
        {
            id: "arquera", nombre: Idioma.t("Arquera"), sprite: "h01",
            vida: 150, daño: 15, armadura: 1, magia: 0.0, resistencia: 1, papel: Idioma.t("Golpes certeros"),
            ataque: "Saeta", glifo: 0xF0289,
            visual: { forma: "flecha", color: "#30d158" }, reto: { tipo: "oleada", meta: 25 },
            porNivel: { vida: 0.07, daño: 0.14, armadura: 0.15, resistencia: 0.105 },
            habilidades: [
                { nivel: 1, id: "lluvia", nombre: Idioma.t("Lluvia de flechas"),
                  desc: Idioma.t("Cae sobre toda la oleada"), recarga: 16, glifo: 0xF0289,
                  efecto: "area", potencia: 4 },
                { nivel: 6, id: "perforar", nombre: Idioma.t("Perforante"),
                  desc: Idioma.t("Un disparo que atraviesa"), recarga: 20, glifo: 0xF04E5,
                  efecto: "golpeUnico", potencia: 10 },
                { nivel: 14, id: "veneno", nombre: Idioma.t("Punta envenenada"),
                  desc: Idioma.t("Desangra a la oleada"), recarga: 26, glifo: 0xF0BC2,
                  efecto: "veneno", potencia: 12 },
                { nivel: 22, id: "aljaba", nombre: Idioma.t("Aljaba infinita"),
                  desc: Idioma.t("Ráfaga encadenada"), recarga: 34, glifo: 0xF0289,
                  efecto: "cadena", potencia: 5 }
            ]
        },
        {
            id: "picaro", nombre: Idioma.t("Pícaro"), sprite: "h03",
            vida: 140, daño: 17, armadura: 0, magia: 0.0, resistencia: 1, papel: Idioma.t("Remata heridos"),
            ataque: "Puñalada", glifo: 0xF04E5,
            visual: { forma: "tajo", color: "#ff453a" }, reto: { tipo: "muertes", meta: 1500 },
            porNivel: { vida: 0.06, daño: 0.15, armadura: 0.1, resistencia: 0.07 },
            habilidades: [
                { nivel: 1, id: "emboscada", nombre: Idioma.t("Emboscada"),
                  desc: Idioma.t("Golpe brutal al más débil"), recarga: 15, glifo: 0xF04E5,
                  efecto: "remate", potencia: 12 },
                { nivel: 6, id: "sangrar", nombre: Idioma.t("Hemorragia"),
                  desc: Idioma.t("Deja a la oleada sangrando"), recarga: 22, glifo: 0xF0BC2,
                  efecto: "veneno", potencia: 16 },
                { nivel: 14, id: "sombras", nombre: Idioma.t("Danza de sombras"),
                  desc: Idioma.t("Se vuelve intocable y pega"), recarga: 30, glifo: 0xF0E20,
                  efecto: "invulnerable", potencia: 4 },
                { nivel: 22, id: "degollar", nombre: Idioma.t("Degollar"),
                  desc: Idioma.t("Remate demoledor"), recarga: 40, glifo: 0xF04E5,
                  efecto: "remate", potencia: 30 }
            ]
        },
        {
            id: "barbaro", nombre: Idioma.t("Bárbaro"), sprite: "h05",
            vida: 260, daño: 11, armadura: 3, magia: 0.0, resistencia: 1, papel: Idioma.t("Cuanto más herido, más pega"),
            ataque: "Hachazo", glifo: 0xF0F1B,
            visual: { forma: "tajo", color: "#ff9f0a" }, reto: { tipo: "jefes", meta: 30 },
            porNivel: { vida: 0.10, daño: 0.11, armadura: 0.4, resistencia: 0.28 },
            habilidades: [
                { nivel: 1, id: "furia", nombre: Idioma.t("Furia"),
                  desc: Idioma.t("Se enfurece y golpea el área"), recarga: 18, glifo: 0xF0F1B,
                  efecto: "area", potencia: 5 },
                { nivel: 6, id: "berserk", nombre: Idioma.t("Berserk"),
                  desc: Idioma.t("Devuelve el daño que recibe"), recarga: 24, glifo: 0xF04E5,
                  efecto: "reflejo", potencia: 10 },
                { nivel: 14, id: "terremoto", nombre: Idioma.t("Terremoto"),
                  desc: Idioma.t("Sacude a toda la oleada"), recarga: 30, glifo: 0xF0F1B,
                  efecto: "area", potencia: 11 },
                { nivel: 22, id: "ultimo", nombre: Idioma.t("Último aliento"),
                  desc: Idioma.t("Aguanta a un golpe de morir"), recarga: 60, glifo: 0xF0498,
                  efecto: "invulnerable", potencia: 6 }
            ]
        },
        {
            id: "druida", nombre: Idioma.t("Druida"), sprite: "h06",
            vida: 200, daño: 9, armadura: 2, magia: 0.7, resistencia: 2, papel: Idioma.t("Regenera sin parar"),
            ataque: "Zarza", glifo: 0xF058C,
            visual: { forma: "proyectil", color: "#32d74b" }, reto: { tipo: "cofres", meta: 60 },
            porNivel: { vida: 0.10, daño: 0.08, armadura: 0.3, resistencia: 0.455 },
            habilidades: [
                { nivel: 1, id: "brotar", nombre: Idioma.t("Brotes"),
                  desc: Idioma.t("Regeneración para el grupo"), recarga: 20, glifo: 0xF058C,
                  efecto: "regenerar", potencia: 12 },
                { nivel: 6, id: "espinas", nombre: Idioma.t("Espinas"),
                  desc: Idioma.t("El grupo devuelve daño"), recarga: 26, glifo: 0xF04E5,
                  efecto: "reflejo", potencia: 10 },
                { nivel: 14, id: "savia", nombre: Idioma.t("Savia"),
                  desc: Idioma.t("Cura fuerte a todos"), recarga: 30, glifo: 0xF05E1,
                  efecto: "curaGrupo", potencia: 0.5 },
                { nivel: 22, id: "bosque", nombre: Idioma.t("Ira del bosque"),
                  desc: Idioma.t("Arrasa la oleada"), recarga: 38, glifo: 0xF0F1B,
                  efecto: "area", potencia: 9 }
            ]
        },
        {
            id: "paladin", nombre: Idioma.t("Paladín"), sprite: "h08",
            vida: 280, daño: 10, armadura: 7, magia: 0.4, resistencia: 5, papel: Idioma.t("Muro con castigo"),
            ataque: "Maza sagrada", glifo: 0xF0A38,
            visual: { forma: "destello", color: "#0a84ff" }, reto: { tipo: "nivel", meta: 60 },
            porNivel: { vida: 0.11, daño: 0.09, armadura: 0.65, resistencia: 0.595 },
            habilidades: [
                { nivel: 1, id: "escudoFe", nombre: Idioma.t("Escudo de fe"),
                  desc: Idioma.t("Escudo a todo el grupo"), recarga: 22, glifo: 0xF0A38,
                  efecto: "escudoGrupo", potencia: 0.28 },
                { nivel: 6, id: "castigo", nombre: Idioma.t("Castigo"),
                  desc: Idioma.t("Golpe sagrado al más sano"), recarga: 24, glifo: 0xF05E1,
                  efecto: "golpeUnico", potencia: 9 },
                { nivel: 14, id: "consagrar", nombre: Idioma.t("Consagrar"),
                  desc: Idioma.t("Cura y protege a la vez"), recarga: 32, glifo: 0xF05E1,
                  efecto: "curaGrupo", potencia: 0.3 },
                { nivel: 22, id: "juicio", nombre: Idioma.t("Juicio"),
                  desc: Idioma.t("Detiene y castiga a la oleada"), recarga: 48, glifo: 0xF04AB,
                  efecto: "aturdir", potencia: 4 }
            ]
        },

        // ── los doce que faltaban ─────────────────────────────────
        //  Había veinte sprites de héroe en assets y solo ocho clases: doce
        //  personajes dibujados y sin usar. Cada uno estrena papel propio, que
        //  es lo único que justifica una clase nueva; repetir «pega fuerte» con
        //  otro dibujo no aporta nada.
        {
            id: "monje", nombre: Idioma.t("Monje"), sprite: "h07",
            vida: 175, daño: 13, armadura: 3, magia: 0.25, resistencia: 2, papel: Idioma.t("Encadena golpes"),
            ataque: "Palma de hierro", glifo: 0xF0498,
            visual: { forma: "tajo", color: "#ff9f0a" },
            reto: { tipo: "nivel", meta: 25 },
            porNivel: { vida: 0.075, daño: 0.135, armadura: 0.25, resistencia: 0.262 },
            habilidades: [
                { nivel: 1, id: "rafaga", nombre: Idioma.t("Ráfaga"),
                  desc: Idioma.t("Golpes que saltan de uno a otro"), recarga: 14, glifo: 0xF0498,
                  efecto: "cadena", potencia: 2.2 },
                { nivel: 7, id: "palmaAturde", nombre: Idioma.t("Palma quebrantahuesos"),
                  desc: Idioma.t("Deja quieta a la oleada"), recarga: 30, glifo: 0xF04AB,
                  efecto: "aturdir", potencia: 3 },
                { nivel: 15, id: "meditar", nombre: Idioma.t("Meditación"),
                  desc: Idioma.t("Se recompone poco a poco"), recarga: 26, glifo: 0xF05E1,
                  efecto: "regenerar", potencia: 8 },
                { nivel: 24, id: "centella", nombre: Idioma.t("Puño centella"),
                  desc: Idioma.t("Todo el peso en un golpe"), recarga: 20, glifo: 0xF0498,
                  efecto: "golpeUnico", potencia: 11 }
            ]
        },
        {
            id: "nigromante", nombre: Idioma.t("Nigromante"), sprite: "h09",
            vida: 145, daño: 12, armadura: 0, magia: 0.9, resistencia: 4, papel: Idioma.t("Roba vida y pudre"),
            ataque: "Toque marchito", glifo: 0xF0E20,
            visual: { forma: "proyectil", color: "#8e4ec6" },
            reto: { tipo: "muertes", meta: 3000 },
            porNivel: { vida: 0.065, daño: 0.13, armadura: 0.1, resistencia: 0.385 },
            habilidades: [
                { nivel: 1, id: "sorbo", nombre: Idioma.t("Sorbo de vida"),
                  desc: Idioma.t("Golpea y se cura con ello"), recarga: 16, glifo: 0xF0E20,
                  efecto: "robarVida", potencia: 5 },
                { nivel: 8, id: "peste", nombre: Idioma.t("Peste"),
                  desc: Idioma.t("Pudre a toda la oleada"), recarga: 24, glifo: 0xF058C,
                  efecto: "veneno", potencia: 7 },
                { nivel: 16, id: "alzar", nombre: Idioma.t("Alzar a los caídos"),
                  desc: Idioma.t("Devuelve a un compañero"), recarga: 70, glifo: 0xF05E1,
                  efecto: "revivir", potencia: 0.35 },
                { nivel: 26, id: "cosecha", nombre: Idioma.t("Cosecha"),
                  desc: Idioma.t("Siega a los que peor están"), recarga: 26, glifo: 0xF04E5,
                  efecto: "remate", potencia: 9 }
            ]
        },
        {
            id: "herrero", nombre: Idioma.t("Herrero rúnico"), sprite: "h10",
            vida: 265, daño: 9, armadura: 8, magia: 0.15, resistencia: 4, papel: Idioma.t("Blinda al grupo"),
            ataque: "Martillo rúnico", glifo: 0xF0F1B,
            visual: { forma: "tajo", color: "#ffd60a" },
            reto: { tipo: "cofres", meta: 120 },
            porNivel: { vida: 0.105, daño: 0.08, armadura: 0.7, resistencia: 0.542 },
            habilidades: [
                { nivel: 1, id: "yunque", nombre: Idioma.t("Yunque"),
                  desc: Idioma.t("Blinda a todo el grupo"), recarga: 20, glifo: 0xF0F1B,
                  efecto: "escudoGrupo", potencia: 0.24 },
                { nivel: 6, id: "temple", nombre: Idioma.t("Temple"),
                  desc: Idioma.t("Un escudo grueso a quien más falta le hace"), recarga: 17, glifo: 0xF0F1B,
                  efecto: "escudoUno", potencia: 0.5 },
                { nivel: 14, id: "chispas", nombre: Idioma.t("Lluvia de chispas"),
                  desc: Idioma.t("Castiga a toda la oleada"), recarga: 22, glifo: 0xF0241,
                  efecto: "area", potencia: 3.4 },
                { nivel: 23, id: "runa", nombre: Idioma.t("Runa de espinas"),
                  desc: Idioma.t("Devuelve lo que le peguen"), recarga: 34, glifo: 0xF0BC2,
                  efecto: "reflejo", potencia: 8 }
            ]
        },
        {
            id: "espadachin", nombre: Idioma.t("Espadachín"), sprite: "h11",
            vida: 195, daño: 16, armadura: 3, magia: 0.0, resistencia: 1, papel: Idioma.t("Duelo y desangre"),
            ataque: "Estocada", glifo: 0xF0498,
            visual: { forma: "tajo", color: "#5ac8fa" },
            reto: { tipo: "oleada", meta: 40 },
            porNivel: { vida: 0.08, daño: 0.14, armadura: 0.3, resistencia: 0.21 },
            habilidades: [
                { nivel: 1, id: "sajar", nombre: Idioma.t("Sajar"),
                  desc: Idioma.t("Deja al de delante desangrándose"), recarga: 13, glifo: 0xF0498,
                  efecto: "sangrar", potencia: 6 },
                { nivel: 9, id: "finta", nombre: Idioma.t("Finta"),
                  desc: Idioma.t("Esquiva todo un momento"), recarga: 40, glifo: 0xF0289,
                  efecto: "invulnerable", potencia: 3 },
                { nivel: 17, id: "estocadaReal", nombre: Idioma.t("Estocada real"),
                  desc: Idioma.t("Un golpe limpio y enorme"), recarga: 19, glifo: 0xF0498,
                  efecto: "golpeUnico", potencia: 13 },
                { nivel: 27, id: "danza", nombre: Idioma.t("Danza de aceros"),
                  desc: Idioma.t("Barre a toda la oleada"), recarga: 27, glifo: 0xF0F1B,
                  efecto: "area", potencia: 4.2 }
            ]
        },
        {
            id: "montaraz", nombre: Idioma.t("Montaraz"), sprite: "h12",
            vida: 160, daño: 15, armadura: 2, magia: 0.0, resistencia: 1, papel: Idioma.t("Tiro sostenido"),
            ataque: "Saeta larga", glifo: 0xF0289,
            visual: { forma: "flecha", color: "#a8d84a" },
            reto: { tipo: "muertes", meta: 5000 },
            porNivel: { vida: 0.07, daño: 0.145, armadura: 0.2, resistencia: 0.14 },
            habilidades: [
                { nivel: 1, id: "andanada", nombre: Idioma.t("Andanada"),
                  desc: Idioma.t("Una lluvia sobre toda la oleada"), recarga: 16, glifo: 0xF0289,
                  efecto: "area", potencia: 3.2 },
                { nivel: 8, id: "trampa", nombre: Idioma.t("Trampa de lazo"),
                  desc: Idioma.t("Los deja quietos"), recarga: 32, glifo: 0xF04AB,
                  efecto: "aturdir", potencia: 3 },
                { nivel: 16, id: "puntaHerbada", nombre: Idioma.t("Punta herbada"),
                  desc: Idioma.t("Veneno en cada punta"), recarga: 22, glifo: 0xF058C,
                  efecto: "veneno", potencia: 6 },
                { nivel: 25, id: "tiroCerte", nombre: Idioma.t("Tiro certero"),
                  desc: Idioma.t("Al más malherido, y sin fallo"), recarga: 18, glifo: 0xF0289,
                  efecto: "remate", potencia: 10 }
            ]
        },
        {
            id: "domadora", nombre: Idioma.t("Domadora"), sprite: "h13",
            vida: 205, daño: 12, armadura: 4, magia: 0.1, resistencia: 2, papel: Idioma.t("Controla la oleada"),
            ataque: "Latigazo", glifo: 0xF04E5,
            visual: { forma: "flecha", color: "#ff2d92" },
            reto: { tipo: "jefes", meta: 50 },
            porNivel: { vida: 0.085, daño: 0.115, armadura: 0.4, resistencia: 0.315 },
            habilidades: [
                { nivel: 1, id: "restallar", nombre: Idioma.t("Restallar"),
                  desc: Idioma.t("Los deja quietos de golpe"), recarga: 24, glifo: 0xF04AB,
                  efecto: "aturdir", potencia: 4 },
                { nivel: 7, id: "reclamo", nombre: Idioma.t("Reclamo"),
                  desc: Idioma.t("Se lleva toda la atención"), recarga: 26, glifo: 0xF0849,
                  efecto: "provocar", potencia: 7 },
                { nivel: 15, id: "azote", nombre: Idioma.t("Azote en cadena"),
                  desc: Idioma.t("El látigo salta de uno a otro"), recarga: 17, glifo: 0xF0241,
                  efecto: "cadena", potencia: 2.6 },
                { nivel: 24, id: "correa", nombre: Idioma.t("Correa corta"),
                  desc: Idioma.t("Escudo mientras aguanta el tirón"), recarga: 30, glifo: 0xF0BC2,
                  efecto: "escudoUno", potencia: 0.42 }
            ]
        },
        {
            id: "cazadora", nombre: Idioma.t("Cazadora"), sprite: "h14",
            vida: 165, daño: 16, armadura: 1, magia: 0.0, resistencia: 1, papel: Idioma.t("Remata heridos"),
            ataque: "Venablo", glifo: 0xF0289,
            visual: { forma: "flecha", color: "#64d2ff" },
            reto: { tipo: "oleada", meta: 60 },
            porNivel: { vida: 0.07, daño: 0.15, armadura: 0.15, resistencia: 0.105 },
            habilidades: [
                { nivel: 1, id: "rastro", nombre: Idioma.t("Rastro de sangre"),
                  desc: Idioma.t("Desangra al de delante"), recarga: 14, glifo: 0xF0289,
                  efecto: "sangrar", potencia: 5 },
                { nivel: 9, id: "cepo", nombre: Idioma.t("Cepo"),
                  desc: Idioma.t("Detiene a la oleada entera"), recarga: 34, glifo: 0xF04AB,
                  efecto: "aturdir", potencia: 3 },
                { nivel: 18, id: "estocadaFinal", nombre: Idioma.t("Golpe de gracia"),
                  desc: Idioma.t("Se ceba en el más malherido"), recarga: 16, glifo: 0xF04E5,
                  efecto: "remate", potencia: 12 },
                { nivel: 28, id: "jauria", nombre: Idioma.t("Jauría"),
                  desc: Idioma.t("Todo cae sobre la oleada"), recarga: 26, glifo: 0xF0F1B,
                  efecto: "area", potencia: 4.4 }
            ]
        },
        {
            id: "corsario", nombre: Idioma.t("Corsario"), sprite: "h15",
            vida: 185, daño: 15, armadura: 2, magia: 0.0, resistencia: 1, papel: Idioma.t("Saquea y aguanta"),
            ataque: "Sable", glifo: 0xF0498,
            visual: { forma: "tajo", color: "#ff9f0a" },
            reto: { tipo: "cofres", meta: 250 },
            porNivel: { vida: 0.08, daño: 0.135, armadura: 0.25, resistencia: 0.175 },
            habilidades: [
                { nivel: 1, id: "abordaje", nombre: Idioma.t("Abordaje"),
                  desc: Idioma.t("Se lanza y se lleva parte"), recarga: 15, glifo: 0xF0498,
                  efecto: "robarVida", potencia: 4.5 },
                { nivel: 8, id: "botin", nombre: Idioma.t("Reparto del botín"),
                  desc: Idioma.t("Cura a toda la tripulación"), recarga: 28, glifo: 0xF05E1,
                  efecto: "curaGrupo", potencia: 0.26 },
                { nivel: 17, id: "metralla", nombre: Idioma.t("Metralla"),
                  desc: Idioma.t("Barre la cubierta entera"), recarga: 21, glifo: 0xF0241,
                  efecto: "area", potencia: 3.6 },
                { nivel: 26, id: "bravata", nombre: Idioma.t("Bravata"),
                  desc: Idioma.t("Todos van a por él, y aguanta"), recarga: 30, glifo: 0xF0849,
                  efecto: "provocar", potencia: 8 }
            ]
        },
        {
            id: "brujoSangre", nombre: Idioma.t("Brujo de sangre"), sprite: "h16",
            vida: 150, daño: 18, armadura: 0, magia: 0.85, resistencia: 4, papel: Idioma.t("Pega fuerte y se sirve"),
            ataque: "Zarpa carmesí", glifo: 0xF0E20,
            visual: { forma: "proyectil", color: "#ff375f" },
            reto: { tipo: "nivel", meta: 90 },
            porNivel: { vida: 0.06, daño: 0.16, armadura: 0.1, resistencia: 0.367 },
            habilidades: [
                { nivel: 1, id: "sangria", nombre: Idioma.t("Sangría"),
                  desc: Idioma.t("Le arranca la vida y se la queda"), recarga: 14, glifo: 0xF0E20,
                  efecto: "robarVida", potencia: 6.5 },
                { nivel: 10, id: "hemorragia", nombre: Idioma.t("Hemorragia"),
                  desc: Idioma.t("El de delante se desangra a chorros"), recarga: 18, glifo: 0xF058C,
                  efecto: "sangrar", potencia: 9 },
                { nivel: 19, id: "ofrenda", nombre: Idioma.t("Ofrenda"),
                  desc: Idioma.t("Cura al grupo con lo robado"), recarga: 32, glifo: 0xF05E1,
                  efecto: "curaGrupo", potencia: 0.3 },
                { nivel: 30, id: "carniceria", nombre: Idioma.t("Carnicería"),
                  desc: Idioma.t("Estalla sobre toda la oleada"), recarga: 25, glifo: 0xF0241,
                  efecto: "area", potencia: 5 }
            ]
        },
        {
            id: "licantropo", nombre: Idioma.t("Licántropo"), sprite: "h17",
            vida: 230, daño: 17, armadura: 3, magia: 0.0, resistencia: 1, papel: Idioma.t("Se crece herido"),
            ataque: "Dentellada", glifo: 0xF04E5,
            visual: { forma: "tajo", color: "#c7c7cc" },
            reto: { tipo: "muertes", meta: 12000 },
            porNivel: { vida: 0.095, daño: 0.145, armadura: 0.3, resistencia: 0.21 },
            habilidades: [
                { nivel: 1, id: "desgarro", nombre: Idioma.t("Desgarro"),
                  desc: Idioma.t("Deja una herida que no cierra"), recarga: 12, glifo: 0xF04E5,
                  efecto: "sangrar", potencia: 7 },
                { nivel: 9, id: "sedSangre", nombre: Idioma.t("Sed de sangre"),
                  desc: Idioma.t("Muerde y se alimenta"), recarga: 16, glifo: 0xF04E5,
                  efecto: "robarVida", potencia: 5.5 },
                { nivel: 18, id: "pelaje", nombre: Idioma.t("Pelaje hirsuto"),
                  desc: Idioma.t("Se recompone solo"), recarga: 24, glifo: 0xF05E1,
                  efecto: "regenerar", potencia: 10 },
                { nivel: 29, id: "luna", nombre: Idioma.t("Llamada de la luna"),
                  desc: Idioma.t("Arrasa con todo lo que tenga delante"), recarga: 28, glifo: 0xF0F1B,
                  efecto: "area", potencia: 4.8 }
            ]
        },
        {
            id: "caballeroNegro", nombre: Idioma.t("Caballero negro"), sprite: "h18",
            vida: 300, daño: 11, armadura: 9, magia: 0.25, resistencia: 5, papel: Idioma.t("Castiga al que le pega"),
            ataque: "Mandoble negro", glifo: 0xF0498,
            visual: { forma: "tajo", color: "#8e8e93" },
            reto: { tipo: "jefes", meta: 120 },
            porNivel: { vida: 0.115, daño: 0.085, armadura: 0.75, resistencia: 0.612 },
            habilidades: [
                { nivel: 1, id: "afrenta", nombre: Idioma.t("Afrenta"),
                  desc: Idioma.t("Los obliga a ir a por él"), recarga: 20, glifo: 0xF0849,
                  efecto: "provocar", potencia: 8 },
                { nivel: 7, id: "espinas", nombre: Idioma.t("Armadura de espinas"),
                  desc: Idioma.t("Les devuelve cada golpe"), recarga: 30, glifo: 0xF0BC2,
                  efecto: "reflejo", potencia: 9 },
                { nivel: 16, id: "juramento", nombre: Idioma.t("Juramento oscuro"),
                  desc: Idioma.t("Nada le toca un instante"), recarga: 46, glifo: 0xF0004,
                  efecto: "invulnerable", potencia: 4 },
                { nivel: 25, id: "sentencia", nombre: Idioma.t("Sentencia"),
                  desc: Idioma.t("Un tajo que parte en dos"), recarga: 22, glifo: 0xF0498,
                  efecto: "golpeUnico", potencia: 12 }
            ]
        },
        {
            id: "lancero", nombre: Idioma.t("Lancero carmesí"), sprite: "h19",
            vida: 215, daño: 14, armadura: 5, magia: 0.0, resistencia: 2, papel: Idioma.t("Alcanza a toda la fila"),
            ataque: "Lanzada", glifo: 0xF0F1B,
            visual: { forma: "flecha", color: "#ff453a" },
            reto: { tipo: "oleada", meta: 100 },
            porNivel: { vida: 0.09, daño: 0.125, armadura: 0.45, resistencia: 0.315 },
            habilidades: [
                { nivel: 1, id: "barrido", nombre: Idioma.t("Barrido"),
                  desc: Idioma.t("Alcanza a toda la fila de un golpe"), recarga: 15, glifo: 0xF0F1B,
                  efecto: "area", potencia: 3.4 },
                { nivel: 8, id: "empalar", nombre: Idioma.t("Empalar"),
                  desc: Idioma.t("Lo atraviesa y lo deja sangrando"), recarga: 17, glifo: 0xF0498,
                  efecto: "sangrar", potencia: 7 },
                { nivel: 17, id: "muralla", nombre: Idioma.t("Muralla de astas"),
                  desc: Idioma.t("Cubre al grupo tras las lanzas"), recarga: 26, glifo: 0xF0BC2,
                  efecto: "escudoGrupo", potencia: 0.22 },
                { nivel: 27, id: "carga", nombre: Idioma.t("Carga carmesí"),
                  desc: Idioma.t("Se lleva por delante al primero"), recarga: 20, glifo: 0xF0F1B,
                  efecto: "golpeUnico", potencia: 12 }
            ]
        }
    ]

    // El oro dejó de comprar estadísticas —subirlas a mano no era una decisión,
    // era un peaje— y ahora compra cofres: qué te llevas, no cuánto pegas.
    readonly property var tiendaDef: !Settings.juegoActivo ? [] : [
        { tipo: 0, nombre: Idioma.t("Cofre corriente"), base: 120,  glifo: 0xF04D6 },
        { tipo: 1, nombre: Idioma.t("Cofre de jefe"),   base: 900,  glifo: 0xF04D7 },
        { tipo: 2, nombre: Idioma.t("Cofre de acto"),   base: 6500, glifo: 0xF0A75 }
    ]

    readonly property var metaDef: !Settings.juegoActivo ? [] : [
        { id: "vida",    nombre: Idioma.t("Linaje robusto"), desc: Idioma.t("+8% vida del grupo"),     base: 40, glifo: 0xF1076 },
        { id: "daño",    nombre: Idioma.t("Filo ancestral"), desc: Idioma.t("+8% daño del grupo"),     base: 40, glifo: 0xF04E5 },
        { id: "fortuna", nombre: Idioma.t("Fortuna"),        desc: Idioma.t("Mejores rarezas"),        base: 60, glifo: 0xF0BC2 }
    ]
}
