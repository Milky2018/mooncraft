///|
struct Model {
  info : @shared.AppInfo
}

///|
enum Msg {}

///|
fn view(_dispatch : @rabbita.Dispatch[Msg], model : Model) -> @rabbita.Html {
  @html.div(
    class="preview-shell",
    [
      @html.div(
        class="preview-card",
        [
          @html.h1(class="preview-title", model.info.title),
          @html.p(class="preview-copy", model.info.subtitle),
          @html.p(
            class="preview-copy muted",
            "This scaffold is intentionally small. The agent will turn it into a real product after your first request.",
          ),
        ],
      ),
    ],
  )
}

///|
fn main {
  let app = @rabbita.simple_cell(
    model={ info: @shared.default_info() },
    update=(_ : Msg, model) => model,
    view=view,
  )
  @rabbita.new(app).mount("app")
}
