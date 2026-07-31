//  Compatibilidad: el contrato vive en la API pública desde que existen los
//  plugins de fuera.
//
//  El tipo de verdad es `K4.Plugin` (api/K4/Plugin.qml): un plugin externo no
//  puede llegar a core/ por ruta relativa, así que el contrato tiene que estar
//  donde llega cualquiera — el módulo K4. Los 20 de casa siguen escribiendo
//  `K4Plugin {}` y les llega por aquí, sin tocar veinte ficheros para un
//  renombrado.

import K4 as K4

K4.Plugin {}
