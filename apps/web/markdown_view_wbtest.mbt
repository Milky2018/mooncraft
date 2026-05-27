///|
fn markdown_block_summaries(content : String) -> Array[String] {
  parse_markdown_blocks(content).map(fn(block) {
    match block {
      Heading(level, text) => "h\{level}:\{text}"
      Paragraph(text) => "p:\{text}"
      BulletList(items) => {
        let joined = items.join("|")
        "ul:\{joined}"
      }
      NumberedList(items) => {
        let joined = items.join("|")
        "ol:\{joined}"
      }
      CodeBlock(language, code) => {
        let normalized_code = code.replace_all(old="\n", new="\\n")
        "code:\{language}:\{normalized_code}"
      }
    }
  })
}

///|
test "markdown parser keeps common assistant message blocks" {
  debug_inspect(
    markdown_block_summaries(
      (
        #|# Done
        #|
        #|The app is ready with `moon build`.
        #|
        #|- Chat
        #|- Preview
        #|
        #|1. Build
        #|2. Run
        #|
        #|```moonbit
        #|fn main {
        #|  println("ok")
        #|}
        #|```
      ),
    ),
    content=(
      #|[
      #|  "h1:Done",
      #|  "p:The app is ready with `moon build`.",
      #|  "ul:Chat|Preview",
      #|  "ol:Build|Run",
      #|  "code:moonbit:fn main {\\n  println(\"ok\")\\n}",
      #|]
    ),
  )
}

///|
test "markdown parser treats raw html as text" {
  debug_inspect(
    markdown_block_summaries("<script>alert(1)</script>\n\n**safe** text"),
    content=(
      #|["p:<script>alert(1)</script>", "p:**safe** text"]
    ),
  )
}

///|
test "markdown inline renderer tolerates unclosed markers" {
  let nodes = render_markdown_inline(
    "Use `moon build and **retry",
    is_user=false,
  )
  inspect(nodes.length(), content="2")
}
