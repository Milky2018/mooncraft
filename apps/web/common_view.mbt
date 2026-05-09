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
fn external_link_icon() -> @rabbita.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(
        d="M10.5 13.5l3-3",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
      @svg.path(
        d="M8.5 16.5l-1 1a4 4 0 0 1-5.7-5.7l3-3a4 4 0 0 1 5.7 0",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
      @svg.path(
        d="M15.5 7.5l1-1a4 4 0 0 1 5.7 5.7l-3 3a4 4 0 0 1-5.7 0",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
    ],
  )
}

///|
fn tun_poc_link() -> @rabbita.Html {
  @html.a(
    href="https://tun-poc.moonbitlang.com",
    target=Blank,
    rel="noopener noreferrer",
    style=secondary_button_style(true) +
      ["text-decoration: none", "height: 36px", "padding: 0 10px"],
    [external_link_icon(), @html.span("tun-poc")],
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
