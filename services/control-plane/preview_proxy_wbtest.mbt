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
