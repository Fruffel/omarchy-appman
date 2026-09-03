import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "fruffel.appman"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var status: Model.emptyStatus()
  property bool startupHandled: false
  property string pendingRemove: ""
  property string pendingInstall: ""
  property int spinFrame: 0
  readonly property var spinFrames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

  readonly property int count: Model.appCount(status)
  readonly property bool checking: status.checking === true || statusProc.running
  readonly property bool updating: status.updating === true || quietUpgradeProc.running
  readonly property bool installing: installProc.running
  readonly property bool removing: removeProc.running
  readonly property bool busy: checking || updating || installing || removing
  readonly property string statusError: String(status.error || "")
  readonly property bool upgradeOnStart: setting("upgradeOnStart", true) !== false
  readonly property int pollMinutes: {
    var n = parseInt(String(setting("pollMinutes", 30)), 10)
    if (!isFinite(n)) n = 30
    if (n < 15) n = 15
    if (n > 1440) n = 1440
    return n
  }

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color contentUrgent: bar ? bar.urgent : Color.urgent
  readonly property color contentDim: Qt.darker(contentForeground, 1.55)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string statusScript: pluginDir + "/scripts/appman-status"
  readonly property string upgradeScript: pluginDir + "/scripts/appman-upgrade"
  readonly property string installFileScript: pluginDir + "/scripts/appman-install-file"
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/appman.json"

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function applyStatus(raw) {
    root.status = Model.parseStatus(raw)
  }

  function refresh() {
    if (statusProc.running || quietUpgradeProc.running) return
    statusProc.command = ["bash", root.statusScript]
    statusProc.running = true
  }

  function upgradeQuiet() {
    if (quietUpgradeProc.running) return
    quietUpgradeProc.command = ["bash", root.upgradeScript, "--quiet", "--notify"]
    quietUpgradeProc.running = true
  }

  function runUpgrade() {
    if (quietUpgradeProc.running) return
    quietUpgradeProc.command = ["bash", root.upgradeScript, "--quiet", "--notify", "--report"]
    quietUpgradeProc.running = true
  }

  function browseFile() {
    if (browseProc.running) return
    browseProc.command = ["omarchy", "file", "select", "--title", "Pick an AppImage", "--extensions", "AppImage appimage"]
    browseProc.running = true
  }

  function integrateFile() {
    var p = fileField.text.trim()
    if (p === "" || installProc.running) return
    pendingInstall = p.split("/").pop()
    installProc.command = ["bash", root.installFileScript, p]
    installProc.running = true
  }

  function removeApp(name) {
    var n = String(name || "").trim()
    if (n === "" || removeProc.running) return
    pendingRemove = n
    removeProc.command = ["appman", "-R", n]
    removeProc.running = true
  }

  function notify(head, body) {
    notifyProc.command = ["omarchy-notification-send", "-g", Model.icon(), "--app-name", "AppMan", String(head || ""), String(body || "")]
    notifyProc.running = true
  }

  function handleStartup() {
    if (root.startupHandled) return
    root.startupHandled = true
    if (root.upgradeOnStart) root.upgradeQuiet()
    else root.refresh()
  }

  onOpenedChanged: if (opened) {
    stateFile.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyStatus(text())
    onLoadFailed: { /* first run has no file yet */ }
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.count === 0 && root.statusError === "")
        root.applyStatus(JSON.stringify({ ok: false, error: "AppMan check failed", apps: [] }))
      stateFile.reload()
    }
  }

  Process {
    id: quietUpgradeProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: function() {
      stateFile.reload()
    }
  }

  Process {
    id: installProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var label = root.pendingInstall !== "" ? root.pendingInstall : "App"
      root.pendingInstall = ""
      if (exitCode === 0) {
        fileField.text = ""
        root.notify(label + " installed", "It is now in the app menu.")
      } else {
        root.notify(label + " failed to install", "Run appman --launcher by hand to see why.")
      }
      root.refresh()
    }
  }

  Process {
    id: removeProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var label = root.pendingRemove !== "" ? root.pendingRemove : "App"
      root.pendingRemove = ""
      if (exitCode === 0) root.notify(label + " removed", "")
      else root.notify(label + " could not be removed", "Run appman -R by hand to see why.")
      root.refresh()
    }
  }

  Process {
    id: notifyProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: browseProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = String(text || "").trim().split("\n")[0]
        p = p.replace(/^file:\/\//, "")
        if (p !== "") fileField.text = p
      }
    }
  }

  // Braille spinner frames while an upgrade runs.
  Timer {
    id: spinTimer
    interval: 80
    running: root.updating
    repeat: true
    onTriggered: root.spinFrame = (root.spinFrame + 1) % root.spinFrames.length
  }

  // Let the session settle before the first appman process.
  Timer {
    id: startupTimer
    interval: 45000
    running: true
    repeat: false
    onTriggered: root.handleStartup()
  }

  Timer {
    id: pollTimer
    interval: root.pollMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.runUpgrade()
      onReturnRequested: root.runUpgrade()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "u" || t === "U") root.runUpgrade()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          // Keep bordered controls off the Flickable clip edge so the
          // left stroke of the first button is not sheared off.
          x: 1
          width: panelFlick.width - 2
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "AppMan"
            meta: root.checking ? "Checking…" : (root.updating ? "Updating…" : Model.formatCheckedAt(root.status.checkedAt))
            detail: root.count > 0 ? (root.count + (root.count === 1 ? " app" : " apps")) : (root.statusError !== "" ? "Error" : "None yet")
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            iconComponent: Component {
              Text {
                text: Model.icon()
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            visible: root.statusError !== ""
            width: parent.width
            text: root.statusError
            color: root.contentUrgent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.statusError === "" && root.count === 0 && !root.updating
            width: parent.width
            text: "No AppMan apps installed yet. Drop an .AppImage below to add one."
            color: root.contentDim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          AppSection {
            visible: root.status.apps.length > 0
            title: "INSTALLED"
            packages: root.status.apps
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: root.updating ? "Updating" : "Update all"
              iconText: root.updating ? root.spinFrames[root.spinFrame] : Model.icon()
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              enabled: root.count > 0 && !root.busy
              opacity: root.busy ? 0.45 : 1
              onClicked: root.runUpgrade()
            }
          }

          PanelSectionHeader {
            text: "INSTALL"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Item {
            width: parent.width
            implicitHeight: fileCol.implicitHeight

            Column {
              id: fileCol
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: fileField
                width: parent.width
                placeholderText: "/path/to/app.AppImage (or drop one here)"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                onAccepted: root.integrateFile()
              }

              Row {
                width: parent.width
                spacing: Style.space(8)

                Button {
                  text: "Browse…"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  bordered: true
                  onClicked: root.browseFile()
                }

                Button {
                  text: root.installing ? "…" : "Install"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  bordered: true
                  enabled: fileField.text.trim() !== "" && !root.busy
                  opacity: root.busy ? 0.45 : 1
                  onClicked: root.integrateFile()
                }
              }
            }

            DropArea {
              anchors.fill: parent
              onDropped: function(drop) {
                if (drop.urls.length > 0)
                  fileField.text = String(drop.urls[0]).replace(/^file:\/\//, "")
              }
            }
          }

        }
      }
    }
  }

  component AppSection: Column {
    property string title: ""
    property var packages: []

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(8)

    PanelSectionHeader {
      text: title
      foreground: root.contentForeground
      fontFamily: root.contentFontFamily
    }

    Repeater {
      model: packages

      delegate: Item {
        id: appRow
        required property var modelData
        property bool armed: false
        width: parent ? parent.width : 0
        implicitHeight: row.implicitHeight

        Timer {
          id: disarmTimer
          interval: 3000
          repeat: false
          onTriggered: parent.armed = false
        }

        Row {
          id: row
          width: parent.width
          spacing: Style.space(8)

          Text {
            id: nameText
            width: Math.max(60, parent.width * 0.32)
            anchors.verticalCenter: parent.verticalCenter
            text: String(modelData.name || "")
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            width: Math.max(60, parent.width - nameText.width - removeButton.width - 2 * Style.space(8))
            anchors.verticalCenter: parent.verticalCenter
            text: Model.describe(modelData)
            color: root.contentDim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
          }

          Button {
            id: removeButton
            text: appRow.armed ? "Sure?" : "Remove"
            foreground: appRow.armed ? root.contentUrgent : root.contentForeground
            fontFamily: root.contentFontFamily
            bordered: true
            enabled: !root.busy
            opacity: root.busy ? 0.45 : 1
            onClicked: {
              if (appRow.armed) {
                appRow.armed = false
                root.removeApp(modelData.name)
              } else {
                appRow.armed = true
                disarmTimer.restart()
              }
            }
          }
        }
      }
    }
  }
}
