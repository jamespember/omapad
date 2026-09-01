// Pure helpers for Omapad persistence and settings.
// No QML imports so we can unit-test in a shell later if needed.

function expandPath(path, home) {
  var p = String(path || "")
  if (!p) return p
  var h = String(home || "")
  if (p === "~") return h
  if (p.indexOf("~/") === 0) return h + p.substring(1)
  if (p.indexOf("$HOME/") === 0) return h + p.substring(5)
  if (p === "$HOME") return h
  return p
}

function dirname(path) {
  var p = String(path || "")
  var slash = p.lastIndexOf("/")
  return slash <= 0 ? "/" : p.substring(0, slash)
}

// Look up the plugin's own entry in shell.json plugins[]. Returns {} on
// miss so callers can treat it as "no user settings, use manifest defaults".
function extractPluginSettings(rawJson, pluginId) {
  try {
    var config = JSON.parse(String(rawJson || "{}"))
    var entries = Array.isArray(config.plugins) ? config.plugins : []
    var key = String(pluginId || "")
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (entry && String(entry.id) === key) return entry
    }
  } catch (e) {
    // ignore — treat as no settings
  }
  return {}
}

// Sketch strokes on disk are [ [ [x,y], [x,y], ... ], ... ].
// A stroke of fewer than 2 points is a stray click, drop it.
function normalizeStrokes(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    if (!Array.isArray(parsed)) return []
    var out = []
    for (var i = 0; i < parsed.length; i++) {
      var s = parsed[i]
      if (!Array.isArray(s) || s.length < 2) continue
      var validPoints = []
      for (var j = 0; j < s.length; j++) {
        var p = s[j]
        if (Array.isArray(p) && p.length >= 2 && isFinite(p[0]) && isFinite(p[1]))
          validPoints.push([Number(p[0]), Number(p[1])])
      }
      if (validPoints.length >= 2) out.push(validPoints)
    }
    return out
  } catch (e) {
    return []
  }
}

function serializeStrokes(strokes) {
  return JSON.stringify(Array.isArray(strokes) ? strokes : [])
}

if (typeof module !== "undefined") {
  module.exports = {
    expandPath: expandPath,
    dirname: dirname,
    extractPluginSettings: extractPluginSettings,
    normalizeStrokes: normalizeStrokes,
    serializeStrokes: serializeStrokes
  }
}
