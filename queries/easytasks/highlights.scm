; inherits: toml

; Base TOML highlights for the `easytasks` filetype. `; inherits: toml` pulls in
; any TOML highlights present on the runtimepath (e.g. nvim-treesitter's); the
; patterns below provide a self-contained baseline so highlighting works even
; when no TOML query is installed.

(comment) @comment @spell

; Keys
(bare_key) @property
(quoted_key) @string
(dotted_key (bare_key) @property)

; Values
(boolean) @boolean
(string) @string
(integer) @number
(float) @number.float

(offset_date_time) @string.special
(local_date_time) @string.special
(local_date) @string.special
(local_time) @string.special

; Tables
(table
  ["[" "]"] @punctuation.bracket)
(table_array_element
  ["[[" "]]"] @punctuation.bracket)

; Punctuation
["." ","] @punctuation.delimiter
"=" @operator
["{" "}"] @punctuation.bracket
(array
  ["[" "]"] @punctuation.bracket)
