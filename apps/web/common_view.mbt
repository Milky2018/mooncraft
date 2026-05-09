///|
fn status_badge(state : @sdk.RunState) -> @rabbita.Html {
  let (background, foreground) = match state {
    Idle => ("var(--badge-idle-bg)", "var(--badge-idle-fg)")
    Running => ("var(--badge-running-bg)", "var(--badge-running-fg)")
    Succeeded => ("var(--badge-success-bg)", "var(--badge-success-fg)")
    Failed => ("var(--badge-failed-bg)", "var(--badge-failed-fg)")
  }
  @html.div(
    style=value_text_style() +
      [
        "padding: 6px 10px",
        "border-radius: var(--radius-control)",
        "background: " + background,
        "color: " + foreground,
        "border: 1px solid var(--border-soft)",
      ],
  ) <| state.label()
}

///|
fn logo_asset_url() -> String {
  "/assets/logo.svg"
}

///|
fn brand_logo(size : Int) -> @rabbita.Html {
  let px = size.to_string() + "px"
  @html.div(
    style=[
      "width: " + px,
      "height: " + px,
      "display: grid",
      "place-items: center",
      "border-radius: var(--radius-control)",
      "background: #05080c",
      "border: 1px solid var(--border-soft)",
      "overflow: hidden",
      "flex-shrink: 0",
    ],
  ) <| @html.img(
    src=logo_asset_url(),
    alt="MoonCraft logo",
    loading="eager",
    decoding="async",
    style=["width: 100%", "height: 100%", "object-fit: contain"],
    "",
  )
}

///|
fn project_headline(model : Model) -> String {
  match model.project_detail {
    Some(project) => project.display_name
    None =>
      if model.projects.length() == 0 {
        "No project selected"
      } else {
        "Workspace"
      }
  }
}

///|
fn active_project_status(model : Model) -> @sdk.RunState {
  match model.project_detail {
    Some(project) => project.status
    None => if active_run(model) is Some(_) { Running } else { Idle }
  }
}
