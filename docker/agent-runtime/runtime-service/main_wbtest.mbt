///|
fn init_request_for_test() -> InitRequest {
  {
    project: { id: "project-1" },
    source_repository: {
      url: "https://github.com/moonbitlang/project-1.git",
      default_branch: "main",
      current_commit_sha: Some("abc123"),
    },
    source_credential: {
      kind: "git_https_token",
      username: "x-access-token",
      password: "token with spaces",
    },
    secrets: [{ name: "OPENROUTER_API_KEY", value: "runtime-key" }],
  }
}

///|
test "source authenticated url encodes credential without changing repository path" {
  debug_inspect(
    source_authenticated_url(init_request_for_test()),
    content=(
      #|Ok("https://x-access-token:token%20with%20spaces@github.com/moonbitlang/project-1.git")
    ),
  )
}

///|
test "preview subtree paths map to generated app paths" {
  debug_inspect(
    [
      preview_upstream_path("/preview"),
      preview_upstream_path("/preview/"),
      preview_upstream_path("/preview/assets/app.js"),
    ],
    content=(
      #|["/", "/", "/assets/app.js"]
    ),
  )
}
