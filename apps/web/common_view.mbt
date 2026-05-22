///|
fn status_badge(state : @sdk.RunState) -> @rabbita.Html {
  let (background, foreground) = match state {
    Idle => ("var(--badge-idle-bg)", "var(--badge-idle-fg)")
    Running => ("var(--badge-running-bg)", "var(--badge-running-fg)")
    Succeeded => ("var(--badge-success-bg)", "var(--badge-success-fg)")
    Failed => ("var(--badge-failed-bg)", "var(--badge-failed-fg)")
    Cancelled => ("var(--badge-cancelled-bg)", "var(--badge-cancelled-fg)")
  }
  @html.div(
    style=value_text_style() +
      [
        "padding: 2px 6px",
        "border-radius: var(--radius-control)",
        "background: " + background,
        "color: " + foreground,
        "font-size: 11px",
      ],
  ) <| state.label()
}

///|
fn maybe_status_badge(state : @sdk.RunState) -> @rabbita.Html {
  match state {
    Idle => @html.nothing
    _ => status_badge(state)
  }
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
fn plus_icon() -> @rabbita.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(
        d="M12 5v14M5 12h14",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
    ],
  )
}

///|
fn theme_icon() -> @rabbita.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(
        d="M12 3a9 9 0 1 0 9 9 6.5 6.5 0 0 1-9-9z",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
    ],
  )
}

///|
fn logout_icon() -> @rabbita.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(
        d="M9 21H5V3h4",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
      @svg.path(
        d="M16 17l5-5-5-5",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
      @svg.path(
        d="M21 12H9",
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
    title="tun-poc",
    style=secondary_button_style(true) +
      ["text-decoration: none", "height: 28px", "padding: 0 8px", "gap: 4px"],
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
