///|
test "bootstrap prompt includes the core execution rules" {
  let prompt = bootstrap_prompt("Build a todo app")
  assert_true(
    prompt.contains(
      "Default to MoonBit unless the user explicitly asks for another technology.",
    ),
  )
  assert_true(
    prompt.contains(
      "Use subagents only for concrete, bounded implementation tasks.",
    ),
  )
  assert_true(prompt.contains("moon fmt"))
  assert_true(prompt.contains("Build a todo app"))
}

///|
test "extract thread id from codex json event" {
  let events = "{\"type\":\"thread.started\",\"thread_id\":\"019db86f-4b45-75c3-a409-984993d1f897\"}\n{\"type\":\"turn.started\"}"
  inspect(
    extract_thread_id(events),
    content="Some(\"019db86f-4b45-75c3-a409-984993d1f897\")",
  )
}
