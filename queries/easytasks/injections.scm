; inherits: toml

; Highlight the inline source of `lua` tasks as Lua.
;
; Scoped to `[[tasks]]` entries whose `type` is "lua": the pattern requires a
; sibling `type = "lua"` pair, which (per the schema's field order) precedes the
; `script` pair. The `#offset!` strips the string delimiters so only the Lua
; body is injected — 3 columns for `"""`/`'''`, 1 column for `"`/`'`.

; ── multiline basic string: script = """ ... """ ──
((table_array_element
  (pair (bare_key) @_type (string) @_typeval)
  (pair (bare_key) @_key (string) @injection.content))
 (#eq? @_type "type")
 (#lua-match? @_typeval "^['\"]lua['\"]$")
 (#eq? @_key "script")
 (#lua-match? @injection.content "^\"\"\"")
 (#set! injection.language "lua")
 (#offset! @injection.content 0 3 0 -3))

; ── multiline literal string: script = ''' ... ''' ──
((table_array_element
  (pair (bare_key) @_type (string) @_typeval)
  (pair (bare_key) @_key (string) @injection.content))
 (#eq? @_type "type")
 (#lua-match? @_typeval "^['\"]lua['\"]$")
 (#eq? @_key "script")
 (#lua-match? @injection.content "^'''")
 (#set! injection.language "lua")
 (#offset! @injection.content 0 3 0 -3))

; ── single-line basic string: script = "..." ──
((table_array_element
  (pair (bare_key) @_type (string) @_typeval)
  (pair (bare_key) @_key (string) @injection.content))
 (#eq? @_type "type")
 (#lua-match? @_typeval "^['\"]lua['\"]$")
 (#eq? @_key "script")
 (#lua-match? @injection.content "^\"")
 (#not-lua-match? @injection.content "^\"\"\"")
 (#set! injection.language "lua")
 (#offset! @injection.content 0 1 0 -1))

; ── single-line literal string: script = '...' ──
((table_array_element
  (pair (bare_key) @_type (string) @_typeval)
  (pair (bare_key) @_key (string) @injection.content))
 (#eq? @_type "type")
 (#lua-match? @_typeval "^['\"]lua['\"]$")
 (#eq? @_key "script")
 (#lua-match? @injection.content "^'")
 (#not-lua-match? @injection.content "^'''")
 (#set! injection.language "lua")
 (#offset! @injection.content 0 1 0 -1))
