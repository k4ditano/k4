//  El tiempo. Los datos y la ubicación viven en el servicio Weather; esto solo
//  decide cuándo se ve y guarda el estado de la búsqueda de ciudad.

import QtQuick
import Quickshell.Io
import "../../core"
import "../../services"

K4Plugin {
    id: self

    name: "weather"
    title: Idioma.t("El tiempo")
    priority: 62
    active: open

    property bool open: false
    property bool searchOpen: false
    property string query: ""

    // lo aparta al abrirse; lo inyecta el host
    property var panel: null

    islandWidth: 820
    islandHeight: 420

    // solo hace falta el teclado mientras se escribe una ciudad
    grabKeyboard: searchOpen
    tecladoOpcional: open

    handlesBackgroundTap: true
    onBackgroundTapped: {}   // se traga el clic: cerrar es cosa del botón

    closeOnHoverExit: true
    hoverExitDelay: 1000
    onHoverTimedOut: close()

    function toggle() {
        open = !open
        if (open) {
            if (panel) panel.close()
            Notifs.dismissToast()
            // al abrir se refresca si los datos ya tienen un rato
            if (Weather.located)
                Weather.refresh()
        } else {
            closeSearch()
        }
    }

    function close() {
        open = false
        closeSearch()
    }

    function openSearch() {
        query = ""
        searchOpen = true
    }

    function closeSearch() {
        searchOpen = false
        query = ""
        Weather.matches = []
    }

    function choose(match) {
        Weather.setPlace(match.name, match.region, match.latitude, match.longitude)
        closeSearch()
    }

    IpcHandler {
        target: "k4.weather"
        function toggle(): void { self.toggle() }
        function close(): void { self.close() }
        function refresh(): void { Weather.refresh() }
        function locate(): void { Weather.locate() }
        function place(city: string): void {
            self.open = true
            self.searchOpen = true
            self.query = city
            Weather.search(city)
        }
    }

    view: Component {
        WeatherView { plugin: self }
    }
}
