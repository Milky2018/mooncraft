///|
test "preview origin paths map to runtime preview subtree" {
  debug_inspect(
    [
      preview_target_path(""),
      preview_target_path("/"),
      preview_target_path("assets/app.js"),
      preview_target_path("/assets/app.js"),
    ],
    content=(
      #|[
      #|  "/preview/",
      #|  "/preview/",
      #|  "/preview/assets/app.js",
      #|  "/preview/assets/app.js",
      #|]
    ),
  )
}

///|
test "runtime service endpoint uses api origin for preview proxy" {
  debug_inspect(
    runtime_service_endpoint("mooncraft-runtime-project-1"),
    content=(
      #|{ url: "http://mooncraft-runtime-project-1:8080" }
    ),
  )
}

///|
test "preview proxy forwards safe cache headers" {
  let headers = proxy_response_headers({
    code: 200,
    headers: {
      "content-type": "text/javascript",
      "cache-control": "max-age=60",
      "etag": "\"abc\"",
      "last-modified": "Tue, 02 Jun 2026 00:00:00 GMT",
      "x-hidden": "no",
    },
    body: b"",
  })
  debug_inspect(
    headers.get("Content-Type").map(fn(value) { value.to_owned() }),
    content="Some(\"text/javascript\")",
  )
  debug_inspect(
    headers.get("Cache-Control").map(fn(value) { value.to_owned() }),
    content="Some(\"max-age=60\")",
  )
  debug_inspect(
    headers.get("ETag").map(fn(value) { value.to_owned() }),
    content="Some(\"\\\"abc\\\"\")",
  )
  debug_inspect(
    headers.get("Last-Modified").map(fn(value) { value.to_owned() }),
    content="Some(\"Tue, 02 Jun 2026 00:00:00 GMT\")",
  )
  debug_inspect(headers.get("x-hidden"), content="None")
}

///|
test "preview proxy forwards cache validators upstream" {
  let headers = proxy_request_headers({
    req: {
      http_method: "GET",
      url: "/p/preview/assets/app.js",
      raw_body: b"",
      headers: {
        "accept": "text/javascript",
        "if-none-match": "\"abc\"",
        "if-modified-since": "Tue, 02 Jun 2026 00:00:00 GMT",
        "cookie": "secret",
      },
    },
    res: @mocket.HttpResponse::new(OK),
    params: {},
  })
  debug_inspect(headers.get("Accept"), content="Some(\"text/javascript\")")
  debug_inspect(headers.get("If-None-Match"), content="Some(\"\\\"abc\\\"\")")
  debug_inspect(
    headers.get("If-Modified-Since"),
    content="Some(\"Tue, 02 Jun 2026 00:00:00 GMT\")",
  )
  debug_inspect(headers.get("cookie"), content="None")
}

///|
test "static preview cache policy separates html and assets" {
  inspect(
    @runtime_protocol.preview_cache_control("index.html"),
    content="no-store",
  )
  inspect(
    @runtime_protocol.preview_cache_control("assets/app.0123456789abcdef.js"),
    content="no-cache",
  )
  inspect(
    @runtime_protocol.preview_cache_control("assets/app.js"),
    content="no-cache",
  )
}
