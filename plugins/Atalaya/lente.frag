//  La lente, de verdad y de una vez.
//
//  Antes cada tarjeta se inclinaba por su cuenta para fingir la curvatura, y
//  se notaba lo que era: rectángulos girados. Un ojo de pez no gira cosas,
//  dobla la IMAGEN — y eso solo se puede hacer cuando ya hay imagen. Así que
//  el plano entero se dibuja plano a una textura y aquí se dobla de una vez.
//
//  Lo que gana: la curvatura es continua (una ventana larga se arquea por el
//  medio, no se inclina entera), y de paso se pueden hacer las dos cosas que
//  delatan que hay un cristal delante y que por tarjetas eran imposibles: que
//  los colores se separen en los bordes y que la luz caiga hacia las esquinas.

#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    //  Cuánto dobla. 0 es un cristal plano.
    float curva;
    //  Cuánto se separan los colores en los bordes.
    float aberracion;
    //  Cuánta luz se pierde hacia las esquinas.
    float vineta;
    //  Ancho partido por alto: sin esto la lente sale ovalada en una pantalla
    //  apaisada, que es un defecto de óptica, no un efecto.
    float aspecto;
};

void main() {
    vec2 uv = qt_TexCoord0 - 0.5;
    uv.x *= aspecto;

    float r2 = dot(uv, uv);
    //  Se muestrea HACIA FUERA para que la imagen se encoja hacia dentro. La
    //  intuición pide lo contrario y es al revés: mirar más lejos trae aquí lo
    //  que estaba allí.
    float f = 1.0 + curva * r2;

    //  Tres radios, uno por color. La separación crece con el cuadrado del
    //  radio: en el centro no hay ninguna —ahí el cristal es plano— y en las
    //  esquinas es donde un objetivo real se rinde.
    float a = aberracion * r2;
    vec2 dr = uv * (f + a);
    vec2 dg = uv * f;
    vec2 db = uv * (f - a);

    vec2 tr = vec2(dr.x / aspecto, dr.y) + 0.5;
    vec2 tg = vec2(dg.x / aspecto, dg.y) + 0.5;
    vec2 tb = vec2(db.x / aspecto, db.y) + 0.5;

    //  Fuera de la textura no hay nada que enseñar, y el muestreo por defecto
    //  repetiría el píxel del borde: saldrían regueros hacia las esquinas.
    vec2 g = step(vec2(0.0), tg) * step(tg, vec2(1.0));
    float dentro = g.x * g.y;

    vec4 cr = texture(source, tr);
    vec4 cg = texture(source, tg);
    vec4 cb = texture(source, tb);

    //  El alfa lo pone el canal verde —el del centro— porque es el que marca
    //  dónde está de verdad el borde de una ventana. Los otros dos solo
    //  aportan color.
    vec4 col = vec4(cr.r, cg.g, cb.b, cg.a) * dentro;

    //  La luz cae hacia las esquinas. Con la cuarta potencia y no con la
    //  segunda: así el centro se queda limpio del todo y la caída ocurre justo
    //  donde la curvatura ya está apretando la imagen.
    float v = clamp(1.0 - vineta * r2 * r2, 0.0, 1.0);
    col.rgb *= v;

    fragColor = col * qt_Opacity;
}
