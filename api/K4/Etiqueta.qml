//  Texto con los defaults de la barra: blanco, Adwaita, 12px.
//
//  Es el `IslandLabel` de core/, reexportado para que un plugin de fuera
//  escriba texto que se vea de la casa sin copiar tres propiedades en cada
//  sitio — y sin poder importar core/, que no es superficie pública.
//
//      K4.Etiqueta { text: "hola"; font.pixelSize: 14 }

import "../../core" as Nucleo

Nucleo.IslandLabel {}
