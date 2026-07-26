//  Carátula: portada o miniatura de vídeo, si no el favicon del sitio, si no
//  el icono de la app, y si no una nota. Cada paso solo aparece cuando el
//  anterior ha fallado, así que un acierto nunca cuesta una segunda petición.

import QtQuick
import Quickshell.Widgets
import "../core"
import "../services"

ClippingRectangle {
    id: artwork

    property var player: Media.activePlayer
    property color placeholder: Theme.surface

    readonly property string coverUrl: Media.coverFor(player)
    readonly property string faviconUrl: Media.faviconFor(player)
    readonly property string appIcon: Media.appIconFor(player)

    color: placeholder
    radius: Math.round(width * 0.22)

    Image {
        id: coverImage
        anchors.fill: parent
        source: artwork.coverUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: 256
        visible: status === Image.Ready
    }

    Image {
        id: siteIcon
        anchors.centerIn: parent
        width: Math.round(parent.height * 0.5)
        height: width
        source: artwork.coverUrl.length === 0 || coverImage.status === Image.Error
            ? artwork.faviconUrl : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
        sourceSize.width: 64
        visible: !coverImage.visible && status === Image.Ready
    }

    IconImage {
        id: appIconImage
        anchors.centerIn: parent
        width: Math.round(parent.height * 0.56)
        height: width
        source: artwork.appIcon
        visible: !coverImage.visible && !siteIcon.visible && artwork.appIcon.length > 0
    }

    IconGlyph {
        anchors.centerIn: parent
        visible: !coverImage.visible && !siteIcon.visible && !appIconImage.visible
        text: Theme.ico.music
        color: Theme.muted
        font.pixelSize: Math.round(parent.height * 0.44)
    }
}
