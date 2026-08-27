//  El fondo: el plano donde están puestas las ventanas.
//
//  Sin esto el canvas no es un canvas, es un fondo negro con cosas encima. Lo
//  que convierte una cosa en la otra es que el suelo se MUEVA: una trama de
//  puntos que se desplaza y se agranda con la cámara le dice al ojo cuánto te
//  has movido y a qué distancia estás, y eso ningún borde ni ninguna sombra lo
//  cuenta igual.
//
//  Son dos tramas, una encima de otra. La de delante va pegada al plano y la
//  de detrás se mueve a la mitad: ese desajuste ES la profundidad — es cómo se
//  mide la distancia mirando por la ventanilla de un coche.
//
//  Y se dobla con la MISMA lente que las ventanas, porque si no, el suelo se
//  quedaría plano debajo de un mundo curvo y se vería el truco.

#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    //  El color de la luz. Va aquí arriba y no al final por la alineación de
    //  std140: un vec4 quiere empezar en múltiplo de 16, y detrás de la matriz
    //  y de `qt_Opacity` cae justo en 80.
    //
    //  Lo pone el tema de la barra, no este fichero. Un canvas con su propio
    //  azul se ve pegado encima del escritorio; con el azul que el usuario
    //  eligió para todo lo demás, se ve parte de él.
    vec4 luzColor;
    float curva;
    float aspecto;
    //  El alto de la pantalla en píxeles: es lo que traduce las coordenadas
    //  normalizadas del shader a las mismas unidades que usa la cámara en QML.
    float alto;
    float escala;
    float camX;
    float camY;
    //  Separación de la trama en unidades del plano.
    float paso;
    //  Cuánto se ve de todo esto (entra con la apertura).
    float fuerza;
    //  Dónde está el puntero, en coordenadas de pantalla de 0 a 1. El suelo
    //  se ilumina donde señalas: es lo que hace que el fondo deje de ser un
    //  telón y pase a ser una superficie que está ahí contigo.
    float luzX;
    float luzY;
    //  El reloj propio de la onda, de 0 a 1.
    //
    //  Y propio a conciencia: atarla a la apertura la dejaba invisible. La
    //  entrada va con `OutCubic`, que a los ciento cincuenta milisegundos ya
    //  ha recorrido el ochenta por ciento —eso es lo que hace que las ventanas
    //  se coloquen con brío— pero un aro que cruza la pantalla en ciento
    //  cincuenta milisegundos no se ve: se intuye que ha pasado algo.
    float onda;
};

//  Las líneas de la rejilla grande. Muy tenues: no están para verse, están
//  para que al arrastrar el ojo tenga algo largo a lo que agarrarse — un campo
//  de puntos solo dice cuánto te mueves, y una línea dice también en qué
//  dirección.
float rejilla(vec2 plano, float p, float grosorPx, float esc) {
    vec2 c = abs(fract(plano / p) - 0.5);
    float d = min(c.x, c.y);
    float u = grosorPx / (p * max(esc, 0.0001));
    return 1.0 - smoothstep(u * 0.3, u, d);
}

//  Un punto redondo y suave en el centro de cada celda de la trama. El tamaño
//  se da en píxeles de PANTALLA y se divide por la escala: si no, al alejarte
//  los puntos encogerían hasta desaparecer y el suelo se quedaría liso justo
//  cuando más falta hace saber dónde estás.
float trama(vec2 plano, float p, float radioPx, float esc) {
    vec2 celda = abs(fract(plano / p) - 0.5);
    float d = length(celda);
    float u = radioPx / (p * max(esc, 0.0001));
    return 1.0 - smoothstep(u * 0.35, u, d);
}

void main() {
    vec2 uv = qt_TexCoord0 - 0.5;
    uv.x *= aspecto;

    float r2 = dot(uv, uv);
    float f = 1.0 + curva * r2;
    vec2 d = uv * f;

    //  De coordenadas de pantalla a coordenadas del plano, deshaciendo la
    //  cámara. Es la misma cuenta que hace QML para colocar las tarjetas, y
    //  tiene que serlo: es lo que hace que una ventana se quede quieta sobre
    //  su punto de la trama al arrastrar.
    vec2 sp = d * alto;
    vec2 plano = sp / max(escala, 0.0001) + vec2(camX, camY);

    float cerca = trama(plano, paso, 2.4, escala);
    float lineas = rejilla(plano, paso * 4.0, 1.0, escala);
    //  La de detrás: mitad de recorrido y celdas más juntas.
    vec2 lejos_p = sp / max(escala, 0.0001) + vec2(camX, camY) * 0.45;
    float lejos = trama(lejos_p, paso * 0.5, 1.5, escala);

    //  El fondo no es negro: es un azul muy oscuro que se apaga hacia las
    //  esquinas. Un negro plano no tiene centro, y esto sí lo tiene — hay que
    //  mirar al medio.
    float caida = clamp(1.0 - 1.15 * sqrt(r2), 0.0, 1.0);
    vec3 fondo = mix(vec3(0.008, 0.010, 0.017),
                     vec3(0.055, 0.070, 0.115), caida * caida);

    vec3 luz = luzColor.rgb;
    //  El halo del puntero. Se mide en coordenadas de PANTALLA y no del
    //  plano, y es a propósito: esto no es una luz puesta sobre el suelo, es
    //  el reflejo del cristal por el que miras — se queda contigo cuando el
    //  mundo pasa por debajo.
    vec2 dl = qt_TexCoord0 - vec2(luzX, luzY);
    dl.x *= aspecto;
    float halo = exp(-dot(dl, dl) * 11.0);

    //  La onda de apertura: un aro de luz que sale del centro cuando esto se
    //  abre y se va por los bordes. Dura lo que dura la entrada y no vuelve —
    //  y al cerrar hace el camino de vuelta, porque `fuerza` deshace el suyo.
    //
    //  No informa de nada, y esa es su función: es lo que convierte «ha
    //  aparecido una ventana» en «ha pasado algo».
    float radio = sqrt(r2);
    float aro = exp(-pow((radio - onda * 1.45) * 5.5, 2.0))
              * onda * (1.0 - onda) * 4.0;

    vec3 col = fondo
             + luz * cerca * 0.50 * caida
             + luz * lejos * 0.19 * caida
             + luz * lineas * 0.055 * caida
             //  La luz del puntero se nota SOBRE la trama más que sobre el
             //  fondo: alumbrar el vacío no cuenta nada, y alumbrar los puntos
             //  hace que el suelo exista donde estás mirando.
             + luz * halo * (0.10 + cerca * 0.45 + lineas * 0.14)
             + luz * aro * 0.20;

    //  Casi opaco, y más hacia los bordes.
    //
    //  En el centro se deja pasar un pelo más de lo que hay debajo: ahí es
    //  donde estabas y ayuda a saber de dónde vienes. En los bordes no aporta
    //  nada y sólo mete ruido detrás de las tarjetas que ya están más
    //  apretadas por la lente, así que ahí se cierra del todo.
    float alfa = mix(0.995, 0.952, caida * caida) * fuerza;
    //  Premultiplicado, que es como Qt espera el color de un ShaderEffect.
    fragColor = vec4(col * alfa, alfa) * qt_Opacity;
}
