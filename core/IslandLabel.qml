import QtQuick

Text {
    //  Literal, siempre.
    //
    //  Un `Text` usa `AutoText` de fábrica: husmea la cadena y, si le parece
    //  marcado, la INTERPRETA. Por aquí pintan cuatrocientos y pico sitios de la
    //  barra, y buena parte del texto NO lo escribe nadie de esta casa: el
    //  cuerpo de una notificación lo manda cualquier aplicación, el título de
    //  una ventana lo pone quien la abrió, el nombre de la canción viene del
    //  reproductor. Una notificación cuyo cuerpo fuera `<img src="http://…">`
    //  no se leería: QML montaría la imagen y saldría a pedirla, o sea una
    //  baliza de lectura servida por la propia barra.
    //
    //  Medido: `<img src="x.png" width=400 height=60>` mide 475x60 —la caja de
    //  la imagen— y en `PlainText` mide 440x19, que es el texto tal cual.
    textFormat: Text.PlainText
    color: Theme.ink
    font.family: Theme.uiFont
    font.pixelSize: 12
}
