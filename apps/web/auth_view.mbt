///|
fn theme_toggle_button(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let label = "Theme: " + model.theme_mode.label()
  @html.button(
    type_="button",
    on_click=dispatch(ToggleTheme),
    style=secondary_button_style(true),
  ) <| label
}

///|
fn render_app_header(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  @html.div(
    style=panel_style() +
      [
        "padding: 8px 10px", "display: flex", "align-items: center", "justify-content: space-between",
        "gap: 6px",
      ],
  ) <| [
    @html.div(style=["display: flex", "align-items: center", "gap: 6px"], [
      brand_logo(38),
      @html.div(style=title_text_style(), "MoonCraft"),
    ]),
    @html.div(style=["display: flex", "align-items: center", "gap: 6px"]) <| [
      tun_poc_link(),
      theme_toggle_button(dispatch, model),
    ],
  ]
}

///|
fn render_notice_card(notice : String?, tone : String) -> @rabbita.Html {
  match notice {
    Some(message) =>
      @html.div(
        style=value_text_style() +
          [
            "padding: 8px 10px",
            "border-radius: var(--radius-control)",
            "background: " + tone,
            "border: 1px solid var(--border-soft)",
          ],
      ) <| message
    None => @html.nothing
  }
}

///|
fn render_auth_screen(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let _ = dispatch
  let _ = model.github_enabled
  let _ = model.auth_notice
  @html.div(
    style=[
      "min-height: 100vh", "position: relative", "padding: 16px", "background-image: linear-gradient(rgba(2, 6, 23, 0.58), rgba(2, 6, 23, 0.70)), url('/assets/factory.webp')",
      "background-size: cover", "background-position: center", "box-sizing: border-box",
    ],
  ) <| [
    @html.div(
      style=[
        "position: absolute", "top: 16px", "left: 16px", "display: flex", "align-items: center",
        "gap: 8px",
      ],
    ) <| [
      brand_logo(32),
      @html.div(
        style=title_text_style() +
          ["color: #ffffff", "text-shadow: 0 1px 18px rgba(0, 0, 0, 0.32)"],
        "MoonCraft",
      ),
    ],
    @html.div(
      style=[
        "position: absolute", "top: 16px", "right: 16px", "display: flex", "align-items: center",
        "gap: 8px",
      ],
    ) <| [
      tun_poc_link(),
      @html.a(
        href=@sdk.github_login_path(),
        style=primary_button_style(true) +
          [
            "text-decoration: none", "justify-content: center", "min-width: 0", "padding: 8px 12px",
          ],
      ) <| "Log in",
    ],
    @html.div(
      style=[
        "position: absolute", "inset: 0", "display: grid", "place-items: center",
        "pointer-events: none", "padding: 24px", "box-sizing: border-box",
      ],
    ) <| [
      @html.div(
        style=[
          "display: flex", "flex-direction: column", "align-items: center", "gap: 8px",
          "text-align: center",
        ],
      ) <| [
        @html.div(
          style=[
            "font-size: 52px", "font-weight: 800", "line-height: 1.05", "letter-spacing: -0.04em",
            "color: #ffffff", "text-shadow: 0 2px 24px rgba(0, 0, 0, 0.38)",
          ],
          "Craft Your App with AI",
        ),
        @html.div(
          style=[
            "font-size: 18px", "font-weight: 600", "line-height: 1.4", "color: rgba(226, 232, 240, 0.76)",
            "text-shadow: 0 1px 16px rgba(0, 0, 0, 0.35)",
          ],
          "Powered by MoonBit",
        ),
      ],
    ],
  ]
}
