// Package-variant glyph. Never use the refresh glyph — that is Omarchy's updater.
function icon() {
  return "󰠮"
}

function emptyStatus() {
  return {
    ok: true,
    checkedAt: 0,
    checking: false,
    updating: false,
    error: "",
    apps: []
  }
}

function asList(value) {
  if (!value || typeof value.length !== "number") return []
  var out = []
  for (var i = 0; i < value.length; i++) out.push(value[i])
  return out
}

function parseStatus(raw) {
  var fallback = emptyStatus()
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return fallback
    fallback.ok = data.ok !== false
    fallback.checkedAt = Number(data.checkedAt || 0)
    fallback.checking = data.checking === true
    fallback.updating = data.updating === true
    fallback.error = typeof data.error === "string" ? data.error : ""
    fallback.apps = asList(data.apps)
    return fallback
  } catch (e) {
    fallback.ok = false
    fallback.error = "Could not read AppMan status"
    return fallback
  }
}

function appCount(status) {
  if (!status) return 0
  return asList(status.apps).length
}

function formatCheckedAt(ts) {
  var n = Number(ts || 0)
  if (!n) return "Not checked yet"
  var date = new Date(n * 1000)
  if (isNaN(date.getTime())) return "Not checked yet"
  return Qt.formatDateTime(date, "ddd HH:mm")
}

function describe(app) {
  if (!app) return ""
  var version = String(app.version || "")
  var db = String(app.db || "")
  if (version && db) return version + " • " + db
  return version || db
}

// Parse `appman -q` output into [{name, description, flag}].
// Continuation lines (wrapped descriptions) are folded into the entry.
// Entries that say "use the --foo flag" install via `appman -i name.foo`.
function parseSearch(raw) {
  var out = []
  var current = null
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\x1b\[[0-9;]*m/g, "")
    var head = line.match(/^\s*◆\s*([A-Za-z0-9_.+:-]+)\s*:?\s*(.*)$/)
    if (head) {
      if (current) out.push(current)
      current = { name: head[1], description: (head[2] || "").trim(), flag: "" }
    } else if (current && line.trim() !== "") {
      current.description += " " + line.trim()
    }
  }
  if (current) out.push(current)
  for (var j = 0; j < out.length; j++) {
    var m = out[j].description.match(/use the --([a-z0-9]+) flag/)
    if (m) out[j].flag = m[1]
  }
  return out
}

function installArg(entry) {
  if (!entry) return ""
  if (entry.flag) return entry.name + "." + entry.flag
  return entry.name
}
