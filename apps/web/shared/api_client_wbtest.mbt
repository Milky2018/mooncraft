///|
test "non-json gateway errors do not expose raw html" {
  let error = decode_error_response(
    502,
    (
      #|<html>
      #|  <head><title>502 Bad Gateway</title></head>
      #|  <body>nginx</body>
      #|</html>
    ),
  )
  debug_inspect(
    error,
    content=(
      #|{
      #|  code: UnexpectedResponse,
      #|  message: "MoonCraft is temporarily unavailable. Please try again.",
      #|}
    ),
  )
}

///|
test "non-json client errors use product fallback" {
  let error = decode_error_response(404, "<html>missing</html>")
  debug_inspect(
    error,
    content="{ code: NotFound, message: \"Unexpected response from MoonCraft.\" }",
  )
}
