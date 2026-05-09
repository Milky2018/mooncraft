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
  @html.div(style=["display: grid", "place-items: center", "flex: 1"]) <| [
    @html.div(
      style=panel_style() +
        [
          "width: min(420px, 100%)", "min-width: 320px", "padding: 8px", "display: flex",
          "flex-direction: column", "gap: 6px",
        ],
    ) <| [
      @html.div(style=["display: flex", "align-items: center", "gap: 6px"]) <| [
        brand_logo(42),
        @html.div(
          style=["display: flex", "flex-direction: column", "gap: 4px"],
          [@html.div(style=title_text_style(), "Sign in to MoonCraft")],
        ),
      ],
      render_notice_card(model.auth_notice, "var(--danger-soft)"),
      if model.github_enabled {
        @html.a(
          href=@sdk.github_login_path(),
          style=primary_button_style(true) +
            [
              "text-decoration: none", "justify-content: center", "padding: 13px 16px",
            ],
        ) <| "Continue with GitHub"
      } else {
        @html.div(
          style=value_text_style() +
            [
              "padding: 8px", "border-radius: var(--radius-control)", "background: var(--warning-soft)",
              "border: 1px solid var(--border-soft)",
            ],
        ) <| "Sign-in is temporarily unavailable. Please try again later."
      },
    ],
  ]
}
