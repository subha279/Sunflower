import QtQuick
import Quickshell
import Quickshell.Io
import "../components" as Components
import "../core" as Core
import "../services" as Services

// Application Launcher

Components.LauncherView {
    id: launcher

    launcherId: "launcher"
    promptIcon: Core.Icons.search
    placeholder: "Search applications"

    cardWidth: 460
    rowHeight: 44

    // Inset around the list: the row boxes sit 12px inside the card, and the
    // card grows by the same amount so no row ever touches the separator.
    contentMargins: 24

    columns: 1

    readonly property var results: Services.AppsService.search(launcher.query)

    itemCount: launcher.results.length

    counterText: launcher.query.length === 0 ? launcher.results.length + " apps" : launcher.results.length + " of " + Services.AppsService.count

    onAccepted: {
        const entry = launcher.results[launcher.selectedIndex];
        if (!entry)
            return;

        // Dismiss first: otherwise the closing surface and the new window race for keyboard focus.
        launcher.dismiss();
        Services.AppsService.launch(entry);
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            launcher.toggle();
        }

        function open(): void {
            launcher.show();
        }

        function close(): void {
            launcher.dismiss();
        }
    }

    contentComponent: Component {
        Item {
            width: parent.width
            height: parent.height

            ListView {
                id: list

                anchors.fill: parent
                anchors.margins: launcher.contentMargins / 2

                model: launcher.results
                currentIndex: launcher.selectedIndex

                clip: true
                boundsBehavior: Flickable.StopAtBounds

                spacing: 4

                interactive: false

                highlightRangeMode: ListView.NoHighlightRange

                Behavior on contentY {
                    NumberAnimation {
                        duration: Core.Theme.durFast
                        easing.type: Easing.OutQuint
                    }
                }

                Component.onCompleted: launcher.registerView(list)
                Component.onDestruction: launcher.registerView(null)

                onContentHeightChanged: launcher.keepInView()
                onHeightChanged: launcher.keepInView()

                delegate: Components.LauncherRow {
                    required property var modelData
                    required property int index

                    width: list.width
                    height: launcher.rowExtent - list.spacing

                    iconSource: Quickshell.iconPath(modelData.icon, "application-x-executable")
                    title: modelData.name
                    subtitle: modelData.genericName && modelData.genericName.length > 0 ? modelData.genericName : (modelData.comment || "")

                    selected: index === launcher.selectedIndex

                    onActivated: {
                        launcher.selectedIndex = index;
                        launcher.accepted();
                    }
                }
            }

            Text {
                anchors.centerIn: parent

                visible: launcher.results.length === 0

                text: "No matching applications"

                color: Core.Theme.foregroundFaint
                font.family: Core.Theme.fontMono
                font.pixelSize: Core.Theme.fontSize
            }
        }
    }
}
