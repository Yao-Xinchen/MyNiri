import Quickshell
import Quickshell.Wayland
import QtQuick

ShellRoot {
    WlrLayershell {
        id: overlay

        namespace: "dms:clipboard-custom"
        layer: WlrLayer.Overlay
        keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusiveZone: -1

        // Span the full screen so we can dim the background
        anchors { top: true; bottom: true; left: true; right: true }

        color: "transparent"

        // Dim backdrop — click outside to close
        Rectangle {
            anchors.fill: parent
            color: "#99000000"

            MouseArea {
                anchors.fill: parent
                onClicked: Qt.quit()
            }

            // Centered content box
            // Colors/radius mirror what ClipboardViewer loads from dms-colors.json
            Rectangle {
                id: contentBox
                anchors.centerIn: parent
                width: 900
                height: 600

                // viewer exposes its loaded theme so shell can match
                color:        viewer.thSurface
                radius:       viewer.thRadius
                border.color: viewer.thBorder
                border.width: 1

                // Absorb clicks so they don't reach the dim MouseArea
                MouseArea {
                    anchors.fill: parent
                    propagateComposedEvents: false
                }

                ClipboardViewer {
                    id: viewer
                    anchors.fill: parent
                    onCloseRequested: Qt.quit()
                }
            }
        }
    }
}
