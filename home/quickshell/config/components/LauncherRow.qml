import QtQuick

import "../core" as Core

Rectangle {
    id: root

    property string iconSource: ""
    property string title: ""
    property string subtitle: ""

    property bool selected: false

    signal activated

    readonly property int iconSlot: 22
    readonly property int titleLine: Math.round(Core.Theme.fontSize * 1.3)
    readonly property int subtitleLine: Math.round(Core.Theme.fontSizeSmall * 1.3)
    readonly property int textGap: 1

    radius: Core.Theme.radiusRow

    color: root.selected ? Core.Theme.surfaceGlass : mouse.containsMouse ? Core.Theme.surfaceGlassHover : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: Core.Theme.durFast
            easing.type: Easing.OutQuint
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 3
        anchors.verticalCenter: parent.verticalCenter

        width: 3
        height: root.selected ? parent.height * 0.5 : 0

        radius: 2

        color: Core.Theme.accent

        Behavior on height {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutQuint
            }
        }
    }

    Image {
        id: icon

        anchors.left: parent.left
        anchors.leftMargin: Core.Theme.padding
        anchors.verticalCenter: parent.verticalCenter

        width: root.iconSlot
        height: root.iconSlot

        asynchronous: true
        sourceSize.width: root.iconSlot * 2
        sourceSize.height: root.iconSlot * 2

        source: root.iconSource
    }

    Item {
        id: textBlock

        anchors.left: icon.right
        anchors.leftMargin: Core.Theme.padding
        anchors.right: parent.right
        anchors.rightMargin: Core.Theme.padding
        anchors.verticalCenter: parent.verticalCenter

        height: root.titleLine + root.textGap + root.subtitleLine

        Text {
            id: titleText

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            height: root.titleLine
            verticalAlignment: Text.AlignVCenter

            text: root.title

            elide: Text.ElideRight

            color: Core.Theme.foreground

            font.weight: root.selected ? Font.DemiBold : Font.Medium
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize
        }

        Text {
            id: subtitleText

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleText.bottom
            anchors.topMargin: root.textGap

            height: root.subtitleLine
            verticalAlignment: Text.AlignVCenter

            visible: root.subtitle.length > 0

            text: root.subtitle

            elide: Text.ElideRight

            color: root.selected ? Core.Theme.foregroundMuted : Core.Theme.foregroundFaint

            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSizeSmall
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent

        hoverEnabled: true

        cursorShape: Qt.PointingHandCursor

        onClicked: root.activated()
    }
}
