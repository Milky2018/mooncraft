///|
fn status_badge(state : @sdk.RunState) -> @rabbita.Html {
  let (background, foreground) = match state {
    @sdk.Idle => ("var(--badge-idle-bg)", "var(--badge-idle-fg)")
    @sdk.Running => ("var(--badge-running-bg)", "var(--badge-running-fg)")
    @sdk.Succeeded => ("var(--badge-success-bg)", "var(--badge-success-fg)")
    @sdk.Failed => ("var(--badge-failed-bg)", "var(--badge-failed-fg)")
  }
  @html.div(
    style=mono_style() +
      [
        "padding: 6px 10px",
        "border-radius: 6px",
        "background: " + background,
        "color: " + foreground,
        "font-size: 11px",
        "font-weight: 700",
        "letter-spacing: 0.06em",
        "text-transform: uppercase",
        "border: 1px solid var(--border-soft)",
      ],
    state.label(),
  )
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
      "border-radius: 6px",
      "background: #05080c",
      "border: 1px solid var(--border-soft)",
      "overflow: hidden",
      "flex-shrink: 0",
    ],
    @html.img(
      src=logo_asset_url(),
      alt="Mooncraft logo",
      loading="eager",
      decoding="async",
      style=["width: 100%", "height: 100%", "object-fit: contain"],
      "",
    ),
  )
}

///|
fn user_name(model : Model) -> String {
  match model.current_user {
    Some(user) => user.display_name
    None => "Operator"
  }
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
    None => if active_run(model) is Some(_) { @sdk.Running } else { @sdk.Idle }
  }
}
