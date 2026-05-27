///|
test "preview audit targets private preview port" {
  let preview : @sdk.PreviewTarget = {
    url: "/p/public-preview-id/",
    port: 4792,
    healthy: true,
  }
  debug_inspect(
    preview_audit_target_url(preview),
    content="\"http://127.0.0.1:4792/\"",
  )
}
