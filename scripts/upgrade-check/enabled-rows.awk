# Prints each top-level row that is not literally `disabled: true`, as "<id> <name>", plus
# "(disabled: <expr>)" for a row whose disabled value is anything else, such as an !!js expression.
# A row may omit its id; it is listed as "(no-id)" with its name, so it can't slip past the check.
function flush() {
  if (started && dis != "true") print id " " name (dis == "" || dis == "false" ? "" : " (disabled: " dis ")")
}
/^- / {
  flush(); started = 1; id = "(no-id)"; name = ""; dis = ""
  if ($0 ~ /^- id: /) id = substr($0, 7)
  else if ($0 ~ /^- name: /) name = substr($0, 9)
  else if ($0 ~ /^- disabled: /) dis = substr($0, 13)
  next
}
/^  id: / { id = substr($0, 7); next }
/^  name: / { name = substr($0, 9); next }
/^  disabled: / { dis = substr($0, 13); next }
END { flush() }
