//  La barra de desplazamiento de la casa, edición de dentro.
//
//  Es un envoltorio de K4.Desplazador y nada más: la implementación vive UNA
//  vez, en la API, porque los plugins de fuera también la necesitan — sin
//  ella sus listas salían con la barra de fábrica de Qt y desentonaban. Aquí
//  solo se le da el nombre de la familia de core.

import K4 as K4

K4.Desplazador {}
