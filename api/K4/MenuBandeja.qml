//  El menú que ofrece un icono de la bandeja.
//
//  Reexporta QsMenuOpener. Los menús de bandeja son un protocolo del
//  escritorio —cada aplicación publica el suyo por D-Bus— y esto es lo que lo
//  convierte en un modelo que se puede pintar dentro de la island, en vez de
//  dejar que la aplicación abra su propia ventana emergente por su cuenta.

import Quickshell

QsMenuOpener {}
