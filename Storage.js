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

// Read shell.json, upsert our plugin entry with the given settings, and
// return the serialized JSON ready to write back. Values that are null,
// undefined, or empty strings are removed from the entry (so the plugin
// falls back to its manifest defaults). Array/object values with .length === 0
// are also treated as "unset".
function updatePluginSettings(rawJson, pluginId, updates) {
  var config
  try {
    config = JSON.parse(String(rawJson || "{}"))
  } catch (e) {
    config = {}
  }
  if (!config || typeof config !== "object") config = {}
  if (!Array.isArray(config.plugins)) config.plugins = []

  var idx = -1
  for (var i = 0; i < config.plugins.length; i++) {
    var entry = config.plugins[i]
    if (entry && String(entry.id) === String(pluginId)) { idx = i; break }
  }
  if (idx < 0) {
    config.plugins.push({ id: pluginId })
    idx = config.plugins.length - 1
  }

  var target = config.plugins[idx]
  target.id = pluginId
  for (var key in updates) {
    var value = updates[key]
    var empty = value === undefined
      || value === null
      || (typeof value === "string" && value.length === 0)
      || (Array.isArray(value) && value.length === 0)
    if (empty) delete target[key]
    else target[key] = value
  }

  return JSON.stringify(config, null, 2) + "\n"
}

// Tokenize a shell-style command line into an argv array. Supports single
// and double quotes; no variable/backtick expansion. Adequate for the
// openCommand field where users type things like:
//   xdg-open "obsidian://open?path={pathUri}"
function shellSplit(input) {
  var s = String(input || "")
  var out = []
  var current = ""
  var quote = null
  var haveToken = false
  for (var i = 0; i < s.length; i++) {
    var c = s.charAt(i)
    if (quote) {
      if (c === quote) { quote = null }
      else if (c === "\\" && quote === "\"" && i + 1 < s.length) {
        current += s.charAt(++i)
      } else { current += c }
      continue
    }
    if (c === "\"" || c === "'") { quote = c; haveToken = true; continue }
    if (c === " " || c === "\t" || c === "\n") {
      if (haveToken) { out.push(current); current = ""; haveToken = false }
      continue
    }
    current += c
    haveToken = true
  }
  if (haveToken) out.push(current)
  return out
}

// Join an argv array back into a shell-like display string. Arguments
// containing whitespace or quote chars get double-quoted; embedded double
// quotes are backslash-escaped.
function shellJoin(argv) {
  if (!Array.isArray(argv)) return ""
  return argv.map(function(arg) {
    var s = String(arg == null ? "" : arg)
    if (s.length === 0) return "\"\""
    if (/[\s"'\\]/.test(s)) return "\"" + s.replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\""
    return s
  }).join(" ")
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
