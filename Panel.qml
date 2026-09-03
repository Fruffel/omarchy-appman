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
  property var searchResults: []
  property bool searching: false
  property string searchError: ""

  readonly property int count: Model.appCount(status)
  readonly property bool checking: status.checking === true || statusProc.running
  readonly property bool updating: status.updating === true || quietUpgradeProc.running
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
  readonly property string installDbScript: pluginDir + "/scripts/appman-install-db"
  readonly property string installExtraScript: pluginDir + "/scripts/appman-install-extra"
  readonly property string installFileScript: pluginDir + "/scripts/appman-install-file"
  readonly property string installUrlScript: pluginDir + "/scripts/appman-install-url"
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/appman.json"

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function applyStatus(raw) {
    root.status = Model.parseStatus(raw)
  }

  function applySearch(raw) {
    root.searching = false
    try {
      root.searchResults = Model.parseSearch(raw)
      root.searchError = root.searchResults.length === 0 ? "No matches. Try another keyword." : ""
    } catch (e) {
      root.searchResults = []
      root.searchError = "Search failed"
    }
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

  function runInTerminal(args) {
    if (!root.bar) return
    var quoted = []
    for (var i = 0; i < args.length; i++) quoted.push(Util.shellQuote(String(args[i])))
    root.bar.run("omarchy-launch-floating-terminal-with-presentation " + quoted.join(" "))
  }

  function runUpgrade() {
    runInTerminal([root.upgradeScript])
  }

  function installDb(entry) {
    var arg = Model.installArg(entry)
    if (!arg) return
    runInTerminal([root.installDbScript, arg])
  }

  function doSearch() {
    var q = queryField.text.trim()
    if (q === "" || searchProc.running) return
    root.searching = true
    root.searchError = ""
    searchProc.command = ["appman", "-q", "--all", q]
    searchProc.running = true
  }

  function browseFile() {
    if (browseProc.running) return
    browseProc.command = ["omarchy", "file", "select", "--title", "Pick an AppImage", "--extensions", "AppImage appimage"]
    browseProc.running = true
  }

  function integrateFile() {
    var p = fileField.text.trim()
    if (p === "") return
    runInTerminal([root.installFileScript, p])
  }

  function installExtra() {
    var repo = extraRepoField.text.trim()
    var name = extraNameField.text.trim()
    var keyword = extraKeywordField.text.trim()
    if (repo === "" || name === "") return
    var args = [root.installExtraScript, repo, name]
    if (keyword !== "") args.push(keyword)
    runInTerminal(args)
  }

  function installUrl() {
    var url = urlField.text.trim()
    var name = urlNameField.text.trim()
    if (url === "") return
    var args = [root.installUrlScript, url]
    if (name !== "") args.push(name)
    runInTerminal(args)
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
    id: searchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySearch(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.searching = false
        root.searchError = "Search failed"
      }
    }
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
            visible: root.statusError === "" && root.count === 0 && !root.checking && !root.updating
            width: parent.width
            text: "No AppMan apps installed yet. Search below to add one."
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
              text: "Update all"
              iconText: Model.icon()
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              enabled: root.count > 0 && !root.updating
              onClicked: root.runUpgrade()
            }

            Button {
              text: "Check now"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              enabled: !root.checking && !root.updating
              onClicked: root.refresh()
            }
          }

          PanelSectionHeader {
            text: "INSTALL FROM DATABASE"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: queryField
              width: parent.width - searchButton.width - parent.spacing
              placeholderText: "Search AppMan database…"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              onAccepted: root.doSearch()
            }

            Button {
              id: searchButton
              text: root.searching ? "…" : "Search"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              enabled: queryField.text.trim() !== "" && !root.searching
              onClicked: root.doSearch()
            }
          }

          Text {
            visible: root.searchError !== ""
            width: parent.width
            text: root.searchError
            color: root.contentDim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.searchResults

            delegate: Item {
              required property var modelData
              required property int index
              visible: index < 8
              width: parent ? parent.width : 0
              implicitHeight: entryCol.implicitHeight
              height: visible ? implicitHeight : 0

              Column {
                id: entryCol
                width: parent.width
                spacing: Style.space(2)

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    width: parent.width - installButton.width - parent.spacing
                    text: String(modelData.name || "") + (modelData.flag ? "  •  --" + modelData.flag : "")
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Button {
                    id: installButton
                    text: "Install"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    bordered: true
                    onClicked: root.installDb(modelData)
                  }
                }

                Text {
                  visible: String(modelData.description || "") !== ""
                  width: parent.width
                  text: String(modelData.description || "")
                  color: root.contentDim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }
              }
            }
          }

          PanelSectionHeader {
            text: "INSTALL FROM GITHUB"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: extraRepoField
              width: parent.width
              placeholderText: "user/project or github.com URL"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }

            TextField {
              id: extraNameField
              width: parent.width
              placeholderText: "App name (short, for the CLI)"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }

            TextField {
              id: extraKeywordField
              width: parent.width
              placeholderText: "Keyword (optional, when several AppImages match)"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              onAccepted: root.installExtra()
            }

            Button {
              text: "Install from GitHub"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              enabled: extraRepoField.text.trim() !== "" && extraNameField.text.trim() !== ""
              onClicked: root.installExtra()
            }
          }

          PanelSectionHeader {
            text: "INSTALL APPIMAGE FILE"
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
                  text: "Integrate file"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  bordered: true
                  enabled: fileField.text.trim() !== ""
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

          PanelSectionHeader {
            text: "INSTALL FROM URL"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: urlField
              width: parent.width
              placeholderText: "https://… .AppImage link or github.com repo"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              inputMethodHints: Qt.ImhUrlCharactersOnly
            }

            TextField {
              id: urlNameField
              width: parent.width
              placeholderText: "App name (required for github.com repos)"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              onAccepted: root.installUrl()
            }

            Button {
              text: "Download & integrate"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              enabled: urlField.text.trim() !== ""
              onClicked: root.installUrl()
            }

            Text {
              width: parent.width
              text: "Direct .AppImage links land in ~/Downloads, then join the app menu. GitHub repos stay update-managed like the rest."
              color: root.contentDim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
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
        required property var modelData
        width: parent ? parent.width : 0
        implicitHeight: row.implicitHeight

        Row {
          id: row
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: Math.max(80, parent.width * 0.42)
            text: String(modelData.name || "")
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            width: Math.max(80, parent.width - parent.children[0].width - Style.space(8))
            text: Model.describe(modelData)
            color: root.contentDim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
          }
        }
      }
    }
  }
}
