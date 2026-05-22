///|
fn refresh_icon() -> @rabbita.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(
        d="M20 5v5h-5",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
      @svg.path(
        d="M19 10a7 7 0 1 0 1.3 4",
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
        d="M10 6H6.5A2.5 2.5 0 0 0 4 8.5v7A2.5 2.5 0 0 0 6.5 18H10",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
      @svg.path(
        d="M14 8l4 4-4 4",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
      @svg.path(
        d="M18 12H9",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
    ],
  )
}

///|
fn more_icon() -> @rabbita.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(
        d="M5 12h.01M12 12h.01M19 12h.01",
        fill="none",
        stroke="currentColor",
        stroke_width=3,
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
fn check_icon() -> @rabbita.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(
        d="M5 12.5l4 4L19 6.5",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
    ],
  )
}

///|
fn x_icon() -> @rabbita.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 24 24",
    style=["display: block"],
    [
      @svg.path(
        d="M7 7l10 10M17 7L7 17",
        fill="none",
        stroke="currentColor",
        stroke_width=2,
      ),
    ],
  )
}
