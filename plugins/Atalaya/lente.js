//  Las cuentas de la atalaya: dónde cae cada ventana en el plano y cómo la
//  dobla la lente. Aquí no hay nada de QML a propósito — son funciones puras,
//  que es lo que permite probarlas de cabeza y reusarlas desde el minimapa.

.pragma library

//  ── la rejilla ───────────────────────────────────────────────────
//
//  Todas las ventanas sueltas sobre el plano, en una cuadrícula que tira a
//  cuadrada. Cuadrada y no una fila larga porque el plano se recorre con la
//  vista antes que con el ratón: leer cuatro por cuatro es de un vistazo, y
//  dieciséis en fila es un barrido.
//  `ceil` y no `round`, que se nota con pocas: dos ventanas redondeadas dan UNA
//  columna y dos filas —una torre en medio de una pantalla apaisada— y
//  redondeando hacia arriba dan dos y una, que es como las pondría cualquiera.
//  A partir de cinco las dos fórmulas se parecen; el caso que importa es el de
//  pocas, que es el de todos los días.
function columnas(n) {
    return n <= 0 ? 1 : Math.max(1, Math.ceil(Math.sqrt(n)))
}

//  Los CENTROS de cada celda, alrededor del origen. Alrededor del origen y no
//  desde la esquina para que la cámara nazca en (0,0) mirando al medio de todo
//  sin tener que calcular nada.
function reparto(n, celdaW, celdaH, hueco) {
    const cols = columnas(n)
    const filas = Math.ceil(n / cols)
    const pasoX = celdaW + hueco
    const pasoY = celdaH + hueco
    const ancho = cols * pasoX - hueco
    const alto = filas * pasoY - hueco
    const out = []
    for (let i = 0; i < n; ++i) {
        const f = Math.floor(i / cols)
        const c = i % cols
        //  La última fila, centrada. Una fila coja pegada a la izquierda se
        //  lee como un fallo de colocación, y arreglarlo cuesta una resta.
        const enEsta = Math.min(cols, n - f * cols)
        const sobra = (cols - enEsta) * pasoX / 2
        out.push({
            x: -ancho / 2 + c * pasoX + sobra + celdaW / 2,
            y: -alto / 2 + f * pasoY + celdaH / 2
        })
    }
    return { celdas: out, cols: cols, filas: filas, ancho: ancho, alto: alto }
}

//  ── ¿y la lente? ─────────────────────────────────────────────────
//
//  Ya no está aquí. Estuvo: había un `factor()` que encogía cada tarjeta
//  según su distancia al centro y una `inversa()` para poder deshacerlo al
//  buscar qué había bajo el puntero. Las dos se fueron a `lente.frag` cuando
//  la curvatura pasó a hacerse sobre la imagen ya pintada, que es donde tiene
//  sentido hacerla.
//
//  Lo que queda de aquello en QML es una sola línea, `aLienzo()` en
//  `Lienzo.qml`: la misma cuenta que hace el shader, para llevar el puntero de
//  la imagen doblada a la de verdad. Tiene que ser la misma o el ratón
//  señalaría un sitio y pulsaría otro.

//  ── contain ──────────────────────────────────────────────────────
//
//  Una ventana dentro de su celda sin deformarla. Las proporciones de verdad
//  importan aquí más que en cualquier otro sitio: lo que identifica un
//  terminal frente a un navegador, de lejos y sin poder leer el título, es su
//  forma.
function encajar(anchoV, altoV, celdaW, celdaH) {
    if (anchoV <= 0 || altoV <= 0)
        return { w: celdaW, h: celdaH }
    const e = Math.min(celdaW / anchoV, celdaH / altoV)
    return { w: anchoV * e, h: altoV * e }
}
