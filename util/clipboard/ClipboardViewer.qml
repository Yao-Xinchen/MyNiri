import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    signal closeRequested()

    // ── Theme — populated from DMS's own cache files ───────────────────────────
    property color thPrimary:        "#42a5f5"
    property color thSurface:        "#1e2023"
    property color thSurfaceHigh:    "#292b2f"
    property color thSurfaceHighest: "#343740"
    property color thText:           "#e3e8ef"
    property color thOutline:        "#737685"
    property string thFont:          "Inter Variable"
    property real   thRadius:        12
    property real   thFontSm:        12
    property real   thFontMd:        14

    // Derived (mirrors Theme.qml)
    readonly property color thPrimaryHoverLight: Qt.rgba(thPrimary.r, thPrimary.g, thPrimary.b, 0.08)
    readonly property color thPrimaryPressed:    Qt.rgba(thPrimary.r, thPrimary.g, thPrimary.b, 0.16)
    readonly property color thPrimarySelected:   Qt.rgba(thPrimary.r, thPrimary.g, thPrimary.b, 0.30)
    readonly property color thBorder:            Qt.rgba(thOutline.r, thOutline.g, thOutline.b, 0.08)
    readonly property color thTextMuted:         Qt.rgba(thText.r, thText.g, thText.b, 0.5)
    readonly property color thPrimaryBg:         Qt.rgba(thPrimary.r, thPrimary.g, thPrimary.b, 0.15)

    // ── Socket state ──────────────────────────────────────────────────────────
    property string socketPath: ""
    property int    _reqId:     0
    property var    _pending:   ({})

    // ── Data state ────────────────────────────────────────────────────────────
    property var    allEntries:   []
    property int    selectedId:   -1
    property int    selectedIndex: -1
    property var    fullEntry:    null
    property string textContent:  ""
    property string previewImage: ""

    ListModel { id: clipModel }

    // ── Load DMS theme from cache ─────────────────────────────────────────────
    Process {
        id: colorsProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    var c = d.colors.dark
                    root.thPrimary        = c.primary
                    root.thSurface        = c.surface_container
                    root.thSurfaceHigh    = c.surface_container_high
                    root.thSurfaceHighest = c.surface_container_highest
                    root.thText           = c.on_surface
                    root.thOutline        = c.outline
                } catch(e) { console.warn("colors load:", e) }
            }
        }
    }

    Process {
        id: settingsProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    if (d.fontFamily)   root.thFont   = d.fontFamily
                    if (d.cornerRadius) root.thRadius = d.cornerRadius
                    if (d.fontScale)    { root.thFontSm = Math.round(d.fontScale * 12); root.thFontMd = Math.round(d.fontScale * 14) }
                } catch(e) { console.warn("settings load:", e) }
            }
        }
    }

    // ── DMS socket ────────────────────────────────────────────────────────────
    Process {
        id: findSocketProc
        command: ["bash", "-c",
            'printf "%s" "${DMS_SOCKET:-$(ls /run/user/$(id -u)/danklinux-*.sock 2>/dev/null | head -1)}"']
        stdout: SplitParser {
            onRead: data => { if (data.trim()) root.socketPath = data.trim() }
        }
        onExited: {
            if (root.socketPath) dmsSocket.connected = true
            else console.warn("ClipboardViewer: DMS socket not found")
        }
    }

    Socket {
        id: dmsSocket
        path: root.socketPath
        onConnectionStateChanged: {
            if (connected) { root.refresh(); searchField.forceActiveFocus() }
        }
        parser: SplitParser {
            onRead: line => root._handleMsg(line)
        }
    }

    // ── Protocol ──────────────────────────────────────────────────────────────
    function _handleMsg(line) {
        if (!line.trim()) return
        var msg; try { msg = JSON.parse(line) } catch(e) { return }
        if (typeof msg.id === "undefined") return
        var cb = root._pending[msg.id]
        if (cb) { delete root._pending[msg.id]; cb(msg) }
    }

    function _send(method, params, callback) {
        root._reqId++
        var id = root._reqId
        var req = {id: id, method: method}
        if (params !== null && params !== undefined) req.params = params
        if (callback) root._pending[id] = callback
        dmsSocket.write(JSON.stringify(req) + "\n")
        dmsSocket.flush()
    }

    // ── Data ──────────────────────────────────────────────────────────────────
    function refresh() {
        _send("clipboard.getHistory", null, function(resp) {
            if (resp.error) return
            root.allEntries = resp.result || []
            applyFilter()
        })
    }

    function applyFilter() {
        var q = searchField.text.trim().toLowerCase()
        var filtered = q
            ? root.allEntries.filter(function(e) { return e.preview.toLowerCase().includes(q) })
            : root.allEntries.slice()
        filtered.sort(function(a, b) {
            if (a.pinned !== b.pinned) return b.pinned ? 1 : -1
            return b.id - a.id
        })
        clipModel.clear()
        for (var i = 0; i < filtered.length; i++) clipModel.append(filtered[i])
        if (clipModel.count > 0) selectIndex(0)
        else { root.selectedId = -1; root.fullEntry = null; root.textContent = ""; root.previewImage = "" }
    }

    function selectIndex(idx) {
        if (idx < 0 || idx >= clipModel.count) return
        listView.currentIndex = idx
        root.selectedIndex = idx
        root.selectedId = clipModel.get(idx).id
        fetchEntry(root.selectedId)
    }

    function fetchEntry(id) {
        root.fullEntry = null; root.textContent = ""; root.previewImage = ""
        _send("clipboard.getEntry", {id: id}, function(resp) {
            if (resp.error) return
            var e = resp.result
            root.fullEntry = e
            if (e.isImage) {
                var mime = (e.mimeType || "image/png").split(";")[0]
                root.previewImage = "data:" + mime + ";base64," + (e.data || "")
            } else {
                try { root.textContent = atob(e.data || "") }
                catch(_) { root.textContent = e.preview || "" }
            }
        })
    }

    function copySelected() {
        if (root.selectedId < 0) return
        _send("clipboard.copyEntry", {id: root.selectedId}, function() { root.closeRequested() })
    }

    function deleteEntry(entryId) {
        _send("clipboard.deleteEntry", {id: entryId}, function(resp) {
            if (resp.error) return
            root.allEntries = root.allEntries.filter(function(e) { return e.id !== entryId })
            applyFilter()
        })
    }

    function deleteSelected() {
        if (root.selectedId < 0) return
        deleteEntry(root.selectedId)
    }

    function pinEntry(entryId) {
        _send("clipboard.pinEntry", {id: entryId}, function(resp) {
            if (!resp.error) refresh()
        })
    }

    function unpinEntry(entryId) {
        _send("clipboard.unpinEntry", {id: entryId}, function(resp) {
            if (!resp.error) refresh()
        })
    }

    Component.onCompleted: {
        var home = Quickshell.env("HOME") || "/home/" + Quickshell.env("USER")
        colorsProc.command   = ["cat", home + "/.cache/quickshell/dankshell/dms-colors.json"]
        settingsProc.command = ["cat", home + "/.config/DankMaterialShell/settings.json"]
        colorsProc.running   = true
        settingsProc.running = true
        findSocketProc.running = true
    }

    // ── Layout ────────────────────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // ── Header bar (mirrors ClipboardHeader.qml) ──────────────────────────
        Item {
            Layout.fillWidth: true
            height: 40

            // Left: clipboard icon + title
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    text: "📋"
                    font.pixelSize: root.thFontMd + 2
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "Clipboard History (" + clipModel.count + ")"
                    font.family: root.thFont
                    font.pixelSize: root.thFontMd + 2   // fontSizeLarge
                    font.weight: Font.Medium
                    color: root.thText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Right: action buttons
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                // Delete all / clear history
                Rectangle {
                    width: 32; height: 32; radius: 16
                    color: clearHover.containsMouse
                           ? Qt.rgba(root.thPrimary.r, root.thPrimary.g, root.thPrimary.b, 0.12)
                           : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "🗑"
                        font.pixelSize: 15
                        color: root.thText
                        opacity: 0.7
                    }
                    MouseArea {
                        id: clearHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            _send("clipboard.clearHistory", null, function(resp) {
                                if (!resp.error) refresh()
                            })
                        }
                    }
                }

                // Close button
                Rectangle {
                    width: 32; height: 32; radius: 16
                    color: closeHover.containsMouse
                           ? Qt.rgba(root.thPrimary.r, root.thPrimary.g, root.thPrimary.b, 0.12)
                           : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 14
                        color: root.thText
                        opacity: 0.7
                    }
                    MouseArea {
                        id: closeHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }
        }

        // ── Search bar ────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 44
            color: root.thSurfaceHigh
            radius: root.thRadius
            border.color: searchField.activeFocus
                          ? Qt.rgba(root.thPrimary.r, root.thPrimary.g, root.thPrimary.b, 0.5)
                          : root.thBorder
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                Text {
                    text: "🔍"
                    font.pixelSize: 14
                    opacity: 0.6
                }

                TextInput {
                    id: searchField
                    Layout.fillWidth: true
                    color: root.thText
                    font.family: root.thFont
                    font.pixelSize: root.thFontMd
                    selectionColor: Qt.rgba(root.thPrimary.r, root.thPrimary.g, root.thPrimary.b, 0.4)
                    selectedTextColor: root.thText
                    clip: true

                    Text {
                        anchors.fill: parent
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search clipboard history…"
                        color: root.thTextMuted
                        font.family: root.thFont
                        font.pixelSize: root.thFontMd
                        visible: !searchField.text && !searchField.activeFocus
                        verticalAlignment: Text.AlignVCenter
                    }

                    onTextChanged: root.applyFilter()

                    Keys.onUpPressed:     root.selectIndex(root.selectedIndex - 1)
                    Keys.onDownPressed:   root.selectIndex(root.selectedIndex + 1)
                    Keys.onReturnPressed: root.copySelected()
                    Keys.onEscapePressed: root.closeRequested()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Delete) { root.deleteSelected(); event.accepted = true }
                    }
                }

                Text {
                    text: "✕"
                    font.pixelSize: 12
                    color: root.thTextMuted
                    visible: searchField.text.length > 0
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: searchField.text = ""
                    }
                }
            }
        }

        // ── Split view ────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Left — entry list (~40%)
            Rectangle {
                id: leftPanel
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                width: Math.round(parent.width * 0.4 - 4)
                color: "transparent"
                clip: true

                ListView {
                    id: listView
                    anchors.fill: parent
                    model: clipModel
                    clip: true
                    spacing: 2
                    keyNavigationEnabled: false
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 24
                        z: 100
                        visible: listView.contentHeight > listView.height &&
                                 listView.contentY < listView.contentHeight - listView.height - 5
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: root.thSurface }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: !dmsSocket.connected ? "Connecting…" : "No entries"
                        color: root.thTextMuted
                        font.family: root.thFont
                        font.pixelSize: root.thFontMd
                        visible: clipModel.count === 0
                    }

                    delegate: Rectangle {
                        id: entryRow
                        width: listView.width
                        height: 72   // ClipboardConstants.itemHeight
                        radius: root.thRadius
                        // DMS ClipboardEntry.qml color logic
                        color: listView.currentIndex === index
                               ? root.thPrimaryPressed
                               : entryHover.containsMouse
                                 ? root.thPrimaryHoverLight
                                 : Qt.rgba(root.thSurfaceHigh.r, root.thSurfaceHigh.g, root.thSurfaceHigh.b, 0.5)

                        Behavior on color { ColorAnimation { duration: 80 } }

                        // Main content row
                        Item {
                            anchors {
                                fill: parent
                                leftMargin: 12
                                rightMargin: 12
                            }

                            // Index badge (always visible, matches DMS)
                            Rectangle {
                                id: indexBadge
                                width: 24; height: 24; radius: 12
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                color: listView.currentIndex === index ? root.thPrimarySelected : root.thPrimaryBg

                                Text {
                                    anchors.centerIn: parent
                                    text: index + 1
                                    font.family: root.thFont
                                    font.pixelSize: root.thFontSm
                                    font.weight: Font.Bold
                                    color: root.thPrimary
                                }
                            }

                            // Image indicator (shown instead of badge content for images)
                            Text {
                                anchors.centerIn: indexBadge
                                text: "🖼"
                                font.pixelSize: 11
                                visible: model.isImage
                                z: 1
                            }

                            // Text column
                            Column {
                                anchors {
                                    left: indexBadge.right
                                    leftMargin: 12
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                }
                                spacing: 4

                                Text {
                                    width: parent.width
                                    text: model.isImage
                                          ? (model.mimeType || "image")
                                          : (model.size > 200 ? "Long text" : "Text")
                                    font.family: root.thFont
                                    font.pixelSize: root.thFontSm
                                    font.weight: Font.Medium
                                    color: listView.currentIndex === index ? root.thPrimary : root.thTextMuted
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                Text {
                                    width: parent.width
                                    text: model.preview || ""
                                    font.family: root.thFont
                                    font.pixelSize: root.thFontMd
                                    color: root.thText
                                    opacity: listView.currentIndex === index ? 1.0 : 0.7
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
                        }

                        // Click handler
                        MouseArea {
                            id: entryHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { searchField.forceActiveFocus(); root.selectIndex(index) }
                            onDoubleClicked: root.copySelected()
                        }
                    }
                }
            }

            // Right — preview panel (~60%)
            Rectangle {
                anchors {
                    top: parent.top; bottom: parent.bottom
                    left: leftPanel.right; right: parent.right
                    leftMargin: 8
                }
                color: root.thSurfaceHigh
                radius: root.thRadius
                border.color: root.thBorder
                border.width: 1
                clip: true

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 16
                    visible: root.fullEntry !== null && !root.fullEntry.isImage
                    clip: true

                    TextArea {
                        text: root.textContent
                        color: root.thText
                        font.family: root.thFont
                        font.pixelSize: root.thFontMd
                        readOnly: true
                        wrapMode: TextArea.Wrap
                        selectByMouse: true
                        background: Rectangle { color: "transparent" }
                    }
                }

                Image {
                    anchors.fill: parent
                    anchors.margins: 12
                    visible: root.previewImage !== ""
                    source: root.previewImage
                    fillMode: Image.PreserveAspectFit
                    cache: false
                    asynchronous: true
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: root.fullEntry === null && root.previewImage === ""
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: !dmsSocket.connected ? "Connecting to DMS…"
                            : clipModel.count === 0 ? "No clipboard entries"
                            : "Select an entry to preview"
                        color: root.thTextMuted
                        font.family: root.thFont
                        font.pixelSize: root.thFontMd
                    }
                }
            }
        }

        // ── Status / hint bar ─────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 28
            color: root.thSurfaceHigh
            radius: root.thRadius / 2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (!root.fullEntry) return ""
                        var p = []
                        if (root.fullEntry.mimeType)  p.push(root.fullEntry.mimeType)
                        if (root.fullEntry.size)       p.push(root.fullEntry.size + " B")
                        if (root.fullEntry.timestamp)
                            p.push(root.fullEntry.timestamp.replace("T"," ").substring(0,19))
                        return p.join("  ·  ")
                    }
                    color: root.thTextMuted
                    font.family: root.thFont
                    font.pixelSize: root.thFontSm
                    elide: Text.ElideRight
                }

                Text {
                    text: "↵ Copy  Del Delete  Esc Close"
                    color: root.thTextMuted
                    font.family: root.thFont
                    font.pixelSize: root.thFontSm
                }
            }
        }
    }
}
