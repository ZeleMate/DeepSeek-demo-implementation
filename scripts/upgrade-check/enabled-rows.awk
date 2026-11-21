# Prints each top-level row that is not literally `disabled: true`, as "<id> <name>", plus
# "(disabled: <expr>)" for a row whose disabled value is anything else, such as an !!js expression.
function flush() {
  if (id != "" && dis != "true") print id " " name (dis == "" || dis == "false" ? "" : " (disabled: " dis ")")
}
/^- id: / { flush(); id = substr($0, 7); name = ""; dis = ""; next }
/^- / { flush(); id = ""; next }
/^  name: / { name = substr($0, 9); next }
/^  disabled: / { dis = substr($0, 13); next }
END { flush() }
