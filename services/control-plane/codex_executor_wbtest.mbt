///|
test "preview audit targets public preview proxy path" {
  let preview : @sdk.PreviewTarget = {
    url: "/p/public-preview-id/",
    port: 4792,
    healthy: true,
  }
  debug_inspect(
    preview_audit_target_url_for_base("http://127.0.0.1:8080", preview),
    content="\"http://127.0.0.1:8080/p/public-preview-id/\"",
  )
  debug_inspect(
    preview_audit_target_url_for_base("http://127.0.0.1:8080/", preview),
    content="\"http://127.0.0.1:8080/p/public-preview-id/\"",
  )
}
