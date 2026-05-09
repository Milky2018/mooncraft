///|
priv enum MarkdownBlock {
  Heading(Int, String)
  Paragraph(String)
  BulletList(Array[String])
  NumberedList(Array[String])
  CodeBlock(String, String)
}

///|
fn markdown_find_from(text : String, needle : String, start : Int) -> Int? {
  if start >= text.length() {
    None
  } else {
    match text[start:].find(needle) {
      Some(index) => Some(start + index)
      None => None
    }
  }
}

///|
fn markdown_heading_level(line : String) -> Int {
  if line.has_prefix("### ") {
    3
  } else if line.has_prefix("## ") {
    2
  } else if line.has_prefix("# ") {
    1
  } else {
    0
  }
}

///|
fn markdown_heading_text(line : String, level : Int) -> String {
  line[level + 1:].to_owned().trim().to_owned()
}

///|
fn markdown_bullet_item(line : String) -> String? {
  if line.has_prefix("- ") || line.has_prefix("* ") {
    Some(line[2:].to_owned())
  } else {
    None
  }
}

///|
fn markdown_is_ascii_digits(text : String) -> Bool {
  if text == "" {
    return false
  }
  for index in 0..<text.length() {
    let code = text[index]
    if code < 48 || code > 57 {
      return false
    }
  }
  true
}

///|
fn markdown_numbered_item(line : String) -> String? {
  match line.find(". ") {
    Some(dot) if dot > 0 && markdown_is_ascii_digits(line[:dot].to_owned()) =>
      Some(line[dot + 2:].to_owned())
    _ => None
  }
}

///|
fn markdown_is_block_start(line : String) -> Bool {
  let trimmed = line.trim().to_owned()
  trimmed == "" ||
  trimmed.has_prefix("```") ||
  markdown_heading_level(trimmed) > 0 ||
  markdown_bullet_item(trimmed) is Some(_) ||
  markdown_numbered_item(trimmed) is Some(_)
}

///|
fn parse_markdown_blocks(content : String) -> Array[MarkdownBlock] {
  let normalized = content.replace_all(old="\r\n", new="\n")
  let lines = normalized.split("\n").to_array()
  let blocks : Array[MarkdownBlock] = []
  let mut index = 0
  while index < lines.length() {
    let line = lines[index].to_owned()
    let trimmed = line.trim().to_owned()
    if trimmed == "" {
      index += 1
    } else if trimmed.has_prefix("```") {
      let language = if trimmed.length() > 3 {
        trimmed[3:].to_owned().trim().to_owned()
      } else {
        ""
      }
      let code_lines : Array[String] = []
      index += 1
      while index < lines.length() &&
            !lines[index].to_owned().trim().to_owned().has_prefix("```") {
        code_lines.push(lines[index].to_owned())
        index += 1
      }
      if index < lines.length() {
        index += 1
      }
      blocks.push(CodeBlock(language, code_lines.join("\n")))
    } else {
      let heading_level = markdown_heading_level(trimmed)
      if heading_level > 0 {
        blocks.push(
          Heading(heading_level, markdown_heading_text(trimmed, heading_level)),
        )
        index += 1
      } else {
        match markdown_bullet_item(trimmed) {
          Some(first_item) => {
            let items : Array[String] = [first_item]
            index += 1
            while index < lines.length() {
              match
                markdown_bullet_item(lines[index].to_owned().trim().to_owned()) {
                Some(item) => {
                  items.push(item)
                  index += 1
                }
                None => break
              }
            }
            blocks.push(BulletList(items))
          }
          None =>
            match markdown_numbered_item(trimmed) {
              Some(first_item) => {
                let items : Array[String] = [first_item]
                index += 1
                while index < lines.length() {
                  match
                    markdown_numbered_item(
                      lines[index].to_owned().trim().to_owned(),
                    ) {
                    Some(item) => {
                      items.push(item)
                      index += 1
                    }
                    None => break
                  }
                }
                blocks.push(NumberedList(items))
              }
              None => {
                let paragraph_lines : Array[String] = [line]
                index += 1
                while index < lines.length() &&
                      !markdown_is_block_start(lines[index].to_owned()) {
                  paragraph_lines.push(lines[index].to_owned())
                  index += 1
                }
                blocks.push(
                  Paragraph(paragraph_lines.join("\n").trim().to_owned()),
                )
              }
            }
        }
      }
    }
  }
  blocks
}

///|
fn markdown_container_style() -> Array[String] {
  normal_text_style() +
  [
    "display: flex", "flex-direction: column", "gap: 6px", "overflow-wrap: anywhere",
  ]
}

///|
fn markdown_heading_style(_level : Int) -> Array[String] {
  title_text_style() + ["margin: 4px 0 0"]
}

///|
fn markdown_paragraph_style() -> Array[String] {
  ["margin: 0", "white-space: pre-wrap"]
}

///|
fn markdown_list_style() -> Array[String] {
  [
    "margin: 0", "padding-left: 20px", "display: flex", "flex-direction: column",
    "gap: 5px",
  ]
}

///|
fn markdown_list_item_style() -> Array[String] {
  ["padding-left: 2px", "white-space: pre-wrap"]
}

///|
fn markdown_inline_code_style(is_user : Bool) -> Array[String] {
  let background = if is_user {
    "rgba(255,255,255,0.18)"
  } else {
    "var(--surface-3)"
  }
  value_text_style() +
  [
    "padding: 1px 5px",
    "border-radius: var(--radius-control)",
    "background: " + background,
  ]
}

///|
fn markdown_code_block_style(is_user : Bool) -> Array[String] {
  let background = if is_user {
    "rgba(15, 23, 42, 0.22)"
  } else {
    "var(--surface-3)"
  }
  value_text_style() +
  [
    "margin: 0",
    "padding: 8px 10px",
    "border-radius: var(--radius-control)",
    "background: " + background,
    "overflow-x: auto",
    "white-space: pre",
  ]
}

///|
fn markdown_push_text(nodes : Array[@rabbita.Html], text : String) -> Unit {
  if text != "" {
    nodes.push(@html.span(text))
  }
}

///|
fn render_markdown_inline(
  content : String,
  is_user~ : Bool,
) -> Array[@rabbita.Html] {
  let nodes : Array[@rabbita.Html] = []
  let mut index = 0
  while index < content.length() {
    let mut next_index = content.length()
    let mut marker = ""
    match markdown_find_from(content, "`", index) {
      Some(found) if found < next_index => {
        next_index = found
        marker = "`"
      }
      _ => ignore(())
    }
    match markdown_find_from(content, "**", index) {
      Some(found) if found < next_index => {
        next_index = found
        marker = "**"
      }
      _ => ignore(())
    }
    match markdown_find_from(content, "*", index) {
      Some(found) if found < next_index => {
        next_index = found
        marker = "*"
      }
      _ => ignore(())
    }
    if marker == "" {
      markdown_push_text(nodes, content[index:].to_owned())
      index = content.length()
    } else {
      markdown_push_text(nodes, content[index:next_index].to_owned())
      let content_start = next_index + marker.length()
      match markdown_find_from(content, marker, content_start) {
        Some(end_index) => {
          let inner = content[content_start:end_index].to_owned()
          if marker == "`" {
            nodes.push(
              @html.code(style=markdown_inline_code_style(is_user), inner),
            )
          } else if marker == "**" {
            nodes.push(@html.strong(render_markdown_inline(inner, is_user~)))
          } else {
            nodes.push(@html.em(render_markdown_inline(inner, is_user~)))
          }
          index = end_index + marker.length()
        }
        None => {
          markdown_push_text(nodes, content[next_index:].to_owned())
          index = content.length()
        }
      }
    }
  }
  nodes
}

///|
fn render_markdown_block(
  block : MarkdownBlock,
  is_user~ : Bool,
) -> @rabbita.Html {
  match block {
    Heading(level, text) =>
      match level {
        1 =>
          @html.h1(
            style=markdown_heading_style(level),
            render_markdown_inline(text, is_user~),
          )
        2 =>
          @html.h2(
            style=markdown_heading_style(level),
            render_markdown_inline(text, is_user~),
          )
        _ =>
          @html.h3(
            style=markdown_heading_style(level),
            render_markdown_inline(text, is_user~),
          )
      }
    Paragraph(text) =>
      @html.p(
        style=markdown_paragraph_style(),
        render_markdown_inline(text, is_user~),
      )
    BulletList(items) =>
      @html.ul(
        style=markdown_list_style(),
        items.map(fn(item) {
          @html.li(
            style=markdown_list_item_style(),
            render_markdown_inline(item, is_user~),
          )
        }),
      )
    NumberedList(items) =>
      @html.ol(
        style=markdown_list_style(),
        items.map(fn(item) {
          @html.li(
            style=markdown_list_item_style(),
            render_markdown_inline(item, is_user~),
          )
        }),
      )
    CodeBlock(language, code) =>
      @html.div(style=["display: flex", "flex-direction: column", "gap: 6px"], [
        if language == "" {
          @html.nothing
        } else {
          @html.div(style=normal_text_style() + ["opacity: 0.72"], language)
        },
        @html.pre(style=markdown_code_block_style(is_user), @html.code(code)),
      ])
  }
}

///|
fn render_markdown_message(content : String, is_user~ : Bool) -> @rabbita.Html {
  let blocks = parse_markdown_blocks(content)
  @html.div(
    style=markdown_container_style(),
    blocks.map(fn(block) { render_markdown_block(block, is_user~) }),
  )
}
