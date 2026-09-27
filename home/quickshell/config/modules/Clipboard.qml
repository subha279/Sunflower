import QtQuick
import Quickshell.Io

import "../components" as Components
import "../core" as Core
import "../services" as Services

Components.LauncherView {
    id: clipboard

    launcherId: "clipboard"

    promptIcon: Core.Icons.clipboard
    placeholder: "Search clipboard"

    headerActionIcon: Core.Icons.trash
    headerActionVisible: Services.ClipboardService.items.length > 0

    cardWidth: 460
    columns: 1

    rowHeight: 52

    contentMargins: 24

    readonly property var results: {
        const q = clipboard.query.trim().toLowerCase();

        if (q === "")
            return Services.ClipboardService.items;

        return Services.ClipboardService.items.filter(function (item) {
            return item.text.toLowerCase().includes(q);
        });
    }

    itemCount: clipboard.results.length

    counterText: clipboard.query.length === 0 ? clipboard.results.length + " items" : clipboard.results.length + " matches"

    property bool confirmClear: false

    onDidOpen: {
        Services.ClipboardService.refresh();
        confirmClear = false;
    }

    onDidClose: {
        confirmClear = false;
    }

    onDeleteRequested: {
        clipboard.deleteSelected();
    }

    onClearAllRequested: {
        clipboard.requestClearAll();
    }

    onHeaderActionTriggered: {
        clipboard.requestClearAll();
    }

    onAccepted: {
        if (results.length === 0)
            return;

        const item = results[selectedIndex];

        if (!item)
            return;

        Services.ClipboardService.paste(item);
        clipboard.dismiss();
    }

    function deleteSelected() {
        if (results.length === 0)
            return;

        const item = results[selectedIndex];

        if (!item)
            return;

        Services.ClipboardService.remove(item);

        selectedIndex = Math.max(0, Math.min(selectedIndex, results.length - 2));
    }

    function requestClearAll() {
        if (Services.ClipboardService.items.length === 0)
            return;

        confirmClear = true;
    }

    function clearAll() {
        Services.ClipboardService.clear();

        query = "";
        selectedIndex = 0;
        confirmClear = false;
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): void {
            clipboard.toggle();
        }

        function open(): void {
            clipboard.show();
        }

        function close(): void {
            clipboard.dismiss();
        }
    }

    contentComponent: Component {
        Item {
            width: parent.width
            height: parent.height

            ListView {
                id: list

                anchors.fill: parent
                anchors.margins: clipboard.contentMargins / 2

                model: clipboard.results

                currentIndex: clipboard.selectedIndex

                clip: true

                spacing: 4

                interactive: false

                highlightRangeMode: ListView.NoHighlightRange

                Behavior on contentY {
                    NumberAnimation {
                        duration: Core.Theme.durFast
                        easing.type: Easing.OutQuint
                    }
                }

                Component.onCompleted: clipboard.registerView(list)
                Component.onDestruction: clipboard.registerView(null)

                onContentHeightChanged: clipboard.keepInView()
                onHeightChanged: clipboard.keepInView()

                Text {
                    anchors.centerIn: parent

                    visible: clipboard.results.length === 0

                    text: clipboard.query.length > 0 ? "No clipboard matches" : "Clipboard is empty"

                    color: Core.Theme.foregroundFaint

                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize
                }

                delegate: Rectangle {
                    id: row

                    required property var modelData
                    required property int index

                    readonly property bool selected: row.index === clipboard.selectedIndex

                    width: list.width
                    height: 48

                    radius: Core.Theme.radiusRow

                    color: row.selected ? Core.Theme.surfaceGlass : "transparent"

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
                        height: row.selected ? parent.height * 0.5 : 0

                        radius: 2

                        color: Core.Theme.accent

                        Behavior on height {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutQuint
                            }
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: clipboard.textColumn - clipboard.contentMargins / 2

                        anchors.right: deleteButton.left
                        anchors.rightMargin: 8

                        anchors.verticalCenter: parent.verticalCenter

                        text: row.modelData.text

                        color: row.selected ? Core.Theme.foreground : Core.Theme.foregroundMuted

                        font.family: Core.Theme.fontFamily
                        font.pixelSize: Core.Theme.fontSize

                        elide: Text.ElideRight
                        maximumLineCount: 2
                    }

                    Text {
                        id: deleteButton

                        anchors.right: parent.right
                        anchors.rightMargin: Core.Theme.padding

                        anchors.verticalCenter: parent.verticalCenter

                        text: "×"

                        visible: row.selected

                        color: deleteMouse.containsMouse ? Core.Theme.danger : Core.Theme.foregroundFaint

                        font.family: Core.Theme.fontFamily
                        font.pixelSize: 20

                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }

                        MouseArea {
                            id: deleteMouse

                            anchors.fill: parent
                            anchors.margins: -8

                            hoverEnabled: true

                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                clipboard.deleteSelected();
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.rightMargin: 36

                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            clipboard.selectedIndex = row.index;
                            clipboard.accepted();
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent

                visible: clipboard.confirmClear

                radius: Core.Theme.radiusSmall

                color: Qt.rgba(Core.Theme.background.r, Core.Theme.background.g, Core.Theme.background.b, 0.96)

                z: 100

                Column {
                    anchors.centerIn: parent

                    spacing: 12

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text: "Clear clipboard history?"

                        color: Core.Theme.foreground

                        font.family: Core.Theme.fontFamily
                        font.pixelSize: Core.Theme.fontSizeLarge
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text: "All saved clipboard items will be removed."

                        color: Core.Theme.foregroundMuted

                        font.family: Core.Theme.fontFamily
                        font.pixelSize: Core.Theme.fontSizeSmall
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter

                        spacing: 8

                        Rectangle {
                            width: 100
                            height: 34

                            radius: Core.Theme.radiusRow

                            color: cancelMouse.containsMouse ? Core.Theme.surfaceGlassHover : Core.Theme.surfaceGlass

                            Text {
                                anchors.centerIn: parent

                                text: "Cancel"

                                color: Core.Theme.foreground

                                font.family: Core.Theme.fontFamily
                                font.pixelSize: Core.Theme.fontSizeSmall
                            }

                            MouseArea {
                                id: cancelMouse

                                anchors.fill: parent

                                hoverEnabled: true

                                cursorShape: Qt.PointingHandCursor

                                onClicked: {
                                    clipboard.confirmClear = false;
                                }
                            }
                        }

                        Rectangle {
                            width: 100
                            height: 34

                            radius: Core.Theme.radiusRow

                            color: clearConfirmMouse.containsMouse ? Core.Theme.danger : Core.Theme.surfaceGlass

                            Text {
                                anchors.centerIn: parent

                                text: "Clear all"

                                color: Core.Theme.foreground

                                font.family: Core.Theme.fontFamily
                                font.pixelSize: Core.Theme.fontSizeSmall
                            }

                            MouseArea {
                                id: clearConfirmMouse

                                anchors.fill: parent

                                hoverEnabled: true

                                cursorShape: Qt.PointingHandCursor

                                onClicked: {
                                    clipboard.clearAll();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
