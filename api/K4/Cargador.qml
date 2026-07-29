//  Carga algo solo cuando hace falta, y lo suelta cuando deja de hacer falta.
//
//  Para lo caro que no debe existir siempre: una ventana a pantalla completa,
//  una vista con vídeo dentro. Reexporta LazyLoader.
//
//  Ojo con una cosa que no se ve: su propiedad por defecto es `component`, así
//  que lo que se declare dentro ES lo que se carga, no un hijo suyo.
//
//      K4.Cargador {
//          active: seleccionando
//          MiVentana {}
//      }

import Quickshell

LazyLoader {}
