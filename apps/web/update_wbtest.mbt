///|
test "create project failure closes dialog so notice is visible" {
  let model = {
    ..initial_model(),
    create_project_pending: true,
    new_project_modal_open: true,
  }
  let (_, next) = update(
    fn(_) { @rabbita.none },
    ProjectCreated(
      Err({
        code: ServiceUnavailable,
        message: "MoonCraft is temporarily unavailable. Please try again.",
      }),
    ),
    model,
  )
  inspect(next.create_project_pending, content="false")
  inspect(next.new_project_modal_open, content="false")
  debug_inspect(
    next.notice,
    content=(
      #|Some("Failed to create project. MoonCraft is temporarily unavailable. Please try again.")
    ),
  )
}
