pragma Singleton

//  El tiempo, vía Open-Meteo.
//
//  Sin clave de API y sin cuenta: se pide por curl y se parsea el JSON. La
//  ubicación se adivina por IP la primera vez —que es aproximada, así que cae
//  en la ciudad grande más cercana— y a partir de ahí manda la que busques tú,
//  que se guarda en ~/.local/state/k4/weather.json.
//
//  Los códigos son los WMO que devuelve Open-Meteo; el mapa de abajo los pasa
//  a glifo e idioma, con variante de día y de noche donde tiene sentido.

import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

Singleton {
    id: weather

    readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/k4/weather.json"

    // ── ubicación ─────────────────────────────────────────────────
    property string place: ""
    property string region: ""
    property real latitude: 0
    property real longitude: 0
    property bool located: false

    // ── datos ─────────────────────────────────────────────────────
    property var current: null      // { temp, feels, humidity, precip, wind, code, isDay }
    property var hourly: []         // [{ hour, temp, code, rain }]
    property var daily: []          // [{ date, code, max, min }]
    property string updated: ""

    property bool loading: false
    property string error: ""

    // resultados del buscador de ciudades
    property var matches: []
    property bool searching: false

    readonly property bool ready: current !== null

    // ── códigos WMO ───────────────────────────────────────────────
    readonly property var codes: ({
        0:  { d: 0xE30D, n: 0xE32B, t: "Despejado" },
        1:  { d: 0xE30D, n: 0xE32B, t: "Casi despejado" },
        2:  { d: 0xE302, n: 0xE37E, t: "Parcialmente nublado" },
        3:  { d: 0xE312, n: 0xE312, t: "Nublado" },
        45: { d: 0xE303, n: 0xE346, t: "Niebla" },
        48: { d: 0xE303, n: 0xE346, t: "Niebla helada" },
        51: { d: 0xE30B, n: 0xE328, t: "Llovizna débil" },
        53: { d: 0xE31B, n: 0xE31B, t: "Llovizna" },
        55: { d: 0xE31B, n: 0xE31B, t: "Llovizna intensa" },
        56: { d: 0xE3AD, n: 0xE3AD, t: "Llovizna helada" },
        57: { d: 0xE3AD, n: 0xE3AD, t: "Llovizna helada intensa" },
        61: { d: 0xE308, n: 0xE325, t: "Lluvia débil" },
        63: { d: 0xE318, n: 0xE318, t: "Lluvia" },
        65: { d: 0xE318, n: 0xE318, t: "Lluvia fuerte" },
        66: { d: 0xE3AD, n: 0xE3AD, t: "Lluvia helada" },
        67: { d: 0xE3AD, n: 0xE3AD, t: "Lluvia helada fuerte" },
        71: { d: 0xE30A, n: 0xE327, t: "Nieve débil" },
        73: { d: 0xE31A, n: 0xE31A, t: "Nieve" },
        75: { d: 0xE31A, n: 0xE31A, t: "Nieve intensa" },
        77: { d: 0xE31A, n: 0xE31A, t: "Granizo fino" },
        80: { d: 0xE309, n: 0xE326, t: "Chubascos" },
        81: { d: 0xE319, n: 0xE319, t: "Chubascos moderados" },
        82: { d: 0xE319, n: 0xE319, t: "Chubascos fuertes" },
        85: { d: 0xE30A, n: 0xE327, t: "Chubascos de nieve" },
        86: { d: 0xE31A, n: 0xE31A, t: "Chubascos de nieve fuertes" },
        95: { d: 0xE30F, n: 0xE32A, t: "Tormenta" },
        96: { d: 0xE314, n: 0xE314, t: "Tormenta con granizo" },
        99: { d: 0xE314, n: 0xE314, t: "Tormenta con granizo fuerte" }
    })

    function icon(code, isDay) {
        const entry = codes[code]
        if (!entry)
            return String.fromCodePoint(0xE374)   // weather-na
        return String.fromCodePoint(isDay === false ? entry.n : entry.d)
    }

    function describe(code) {
        const entry = codes[code]
        return entry ? entry.t : "Sin datos"
    }

    // ── consultas ─────────────────────────────────────────────────
    function refresh() {
        if (!located)
            return

        loading = true
        error = ""
        forecast.command = ["curl", "-s", "--max-time", "15",
            "https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + latitude
            + "&longitude=" + longitude
            + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,"
            + "precipitation,weather_code,wind_speed_10m"
            + "&hourly=temperature_2m,weather_code,precipitation_probability"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
            + "&timezone=auto&forecast_days=6&forecast_hours=24"]
        forecast.running = true
    }

    function locate() {
        loading = true
        ipLookup.running = true
    }

    function search(query) {
        const q = query.trim()
        if (q.length < 2) {
            matches = []
            return
        }

        searching = true
        geocode.command = ["curl", "-s", "--max-time", "12",
            "https://geocoding-api.open-meteo.com/v1/search"
            + "?name=" + encodeURIComponent(q) + "&count=6&language=es&format=json"]
        geocode.running = true
    }

    function setPlace(name, area, lat, lon) {
        place = name
        region = area
        latitude = lat
        longitude = lon
        located = true
        matches = []
        save()
        refresh()
    }

    // ── persistencia ──────────────────────────────────────────────
    function save() {
        stateView.setText(JSON.stringify({
            place: place, region: region,
            latitude: latitude, longitude: longitude
        }, null, 2))
    }

    function load() {
        const raw = stateView.text()
        if (raw.length === 0) {
            locate()          // primera vez: se adivina por IP
            return
        }

        let s
        try {
            s = JSON.parse(raw)
        } catch (e) {
            locate()
            return
        }

        if (s.latitude === undefined || s.longitude === undefined) {
            locate()
            return
        }

        place = s.place || ""
        region = s.region || ""
        latitude = s.latitude
        longitude = s.longitude
        located = true
        refresh()
    }

    FileView { id: stateView; path: weather.stateFile; blockLoading: true }

    Process {
        // el estado vive en ~/.local/state/k4, que puede no existir aún
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/k4"]
        running: true
        onExited: weather.load()
    }

    Process {
        id: ipLookup
        command: ["curl", "-s", "--max-time", "10", "https://ipwho.is/"]

        stdout: StdioCollector {
            onStreamFinished: {
                let d
                try {
                    d = JSON.parse(this.text)
                } catch (e) {
                    weather.error = "No se pudo situar por IP"
                    weather.loading = false
                    return
                }

                if (!d.success) {
                    weather.error = "No se pudo situar por IP"
                    weather.loading = false
                    return
                }

                weather.setPlace(d.city || "", d.region || d.country || "",
                                 d.latitude, d.longitude)
            }
        }
    }

    Process {
        id: geocode

        stdout: StdioCollector {
            onStreamFinished: {
                weather.searching = false
                let d
                try {
                    d = JSON.parse(this.text)
                } catch (e) {
                    weather.matches = []
                    return
                }

                const found = []
                const list = d.results || []
                for (let i = 0; i < list.length; ++i) {
                    found.push({
                        name: list[i].name,
                        region: [list[i].admin1, list[i].country]
                            .filter(function (x) { return !!x }).join(" · "),
                        latitude: list[i].latitude,
                        longitude: list[i].longitude
                    })
                }
                weather.matches = found
            }
        }

        onExited: weather.searching = false
    }

    Process {
        id: forecast

        stdout: StdioCollector {
            onStreamFinished: {
                weather.loading = false

                let d
                try {
                    d = JSON.parse(this.text)
                } catch (e) {
                    weather.error = "Respuesta ilegible del servicio"
                    return
                }

                if (!d.current) {
                    weather.error = "Sin datos para esta ubicación"
                    return
                }

                weather.error = ""
                weather.current = {
                    temp: Math.round(d.current.temperature_2m),
                    feels: Math.round(d.current.apparent_temperature),
                    humidity: d.current.relative_humidity_2m,
                    precip: d.current.precipitation,
                    wind: Math.round(d.current.wind_speed_10m),
                    code: d.current.weather_code,
                    isDay: d.current.is_day === 1
                }
                weather.updated = d.current.time.substring(11, 16)

                // ── por horas: desde la actual, de dos en dos
                const hours = []
                if (d.hourly && d.hourly.time) {
                    const now = d.current.time.substring(0, 13)
                    let start = d.hourly.time.indexOf(now + ":00")
                    if (start < 0)
                        start = 0

                    for (let i = start; i < d.hourly.time.length && hours.length < 7; i += 2) {
                        hours.push({
                            hour: d.hourly.time[i].substring(11, 16),
                            temp: Math.round(d.hourly.temperature_2m[i]),
                            code: d.hourly.weather_code[i],
                            rain: d.hourly.precipitation_probability[i],
                            // la franja horaria no trae is_day: se deduce
                            isDay: parseInt(d.hourly.time[i].substring(11, 13)) >= 7
                                && parseInt(d.hourly.time[i].substring(11, 13)) < 21
                        })
                    }
                }
                weather.hourly = hours

                // ── por días
                const days = []
                if (d.daily && d.daily.time) {
                    for (let j = 0; j < d.daily.time.length; ++j) {
                        days.push({
                            date: d.daily.time[j],
                            code: d.daily.weather_code[j],
                            max: Math.round(d.daily.temperature_2m_max[j]),
                            min: Math.round(d.daily.temperature_2m_min[j])
                        })
                    }
                }
                weather.daily = days
            }
        }

        onExited: function (code) {
            weather.loading = false
            if (code !== 0 && weather.current === null)
                weather.error = "No se pudo conectar"
        }
    }

    // Open-Meteo actualiza cada cuarto de hora; pedirlo más a menudo no da
    // datos nuevos, solo tráfico.
    Timer {
        interval: 900000
        repeat: true
        running: weather.located
        onTriggered: weather.refresh()
    }
}
