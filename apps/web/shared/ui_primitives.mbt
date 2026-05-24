///|
pub fn button_base_style(
  text_style : Array[String],
  background : String,
  foreground : String,
  enabled : Bool,
  padding : String,
  border : String,
) -> Array[String] {
  let cursor = if enabled { "pointer" } else { "not-allowed" }
  let opacity = if enabled { "1" } else { "0.45" }
  text_style +
  [
    "border: " + border,
    "border-radius: var(--radius-control)",
    "background: " + background,
    "color: " + foreground,
    "padding: " + padding,
    "display: inline-flex",
    "align-items: center",
    "justify-content: center",
    "gap: 6px",
    "cursor: " + cursor,
    "opacity: " + opacity,
  ]
}

///|
pub fn action_button_box_style(
  foreground : String,
  background : String,
  enabled : Bool,
) -> Array[String] {
  button_base_style([], background, foreground, enabled, "0", "0") +
  ["width: 28px", "height: 28px", "flex-shrink: 0"]
}

///|
pub fn menu_surface_style(
  top : String,
  right : String,
  z_index : String,
  min_width : String,
  radius : String,
  background : String,
  border : String,
  display : String,
) -> Array[String] {
  let border_style = if border == "" { [] } else { ["border: " + border] }
  [
    "position: absolute",
    "top: " + top,
    "right: " + right,
    "z-index: " + z_index,
    "min-width: " + min_width,
    "padding: 4px",
    "border-radius: " + radius,
    "background: " + background,
    "box-shadow: var(--shadow)",
    "display: " + display,
    "flex-direction: column",
    "gap: 4px",
  ] +
  border_style
}

///|
pub fn menu_item_base_style(
  text_style : Array[String],
  foreground : String,
  background : String,
  enabled : Bool,
  radius : String,
  display : String,
) -> Array[String] {
  let cursor = if enabled { "pointer" } else { "not-allowed" }
  let opacity = if enabled { "1" } else { "0.45" }
  text_style +
  [
    "width: 100%",
    "height: 30px",
    "padding: 0 8px",
    "border: 0",
    "border-radius: " + radius,
    "background: " + background,
    "color: " + foreground,
    "display: " + display,
    "align-items: center",
    "justify-content: flex-start",
    "text-align: left",
    "cursor: " + cursor,
    "opacity: " + opacity,
  ]
}
