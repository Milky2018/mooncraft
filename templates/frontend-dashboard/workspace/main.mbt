///|
struct Metric {
  label : String
  value : String
  delta : String
}

///|
struct PipelineRow {
  name : String
  owner : String
  status : String
}

///|
struct Bar {
  label : String
  value : String
  width : String
}

///|
let metrics : Array[Metric] = [
  { label: "Revenue", value: "$128k", delta: "+18.4% this month" },
  { label: "Activation", value: "72%", delta: "+9.1% this week" },
  { label: "Retention", value: "91%", delta: "+3.8% cohort lift" },
  { label: "Pipeline", value: "34", delta: "12 high-intent teams" },
]

///|
let bars : Array[Bar] = [
  { label: "Product qualified", value: "84%", width: "84%" },
  { label: "Sales assisted", value: "62%", width: "62%" },
  { label: "Expansion ready", value: "48%", width: "48%" },
]

///|
let pipeline : Array[PipelineRow] = [
  { name: "Northstar Labs", owner: "Mina", status: "Closing" },
  { name: "Orbit Studio", owner: "Tao", status: "Design" },
  { name: "Fieldnote AI", owner: "Iris", status: "Pilot" },
  { name: "Cedar Works", owner: "Niko", status: "Review" },
]

///|
fn metric_card(metric : Metric) -> @rabbita.Html {
  @html.article(class="metric-card", [
    @html.p(class="metric-label", metric.label),
    @html.p(class="metric-value", metric.value),
    @html.p(class="metric-delta", metric.delta),
  ])
}

///|
fn bar_row(bar : Bar) -> @rabbita.Html {
  @html.div(class="bar-row", [
    @html.div(class="bar-meta", [@html.span(bar.label), @html.strong(bar.value)]),
    @html.div(class="bar-track", [
      @html.div(class="bar-fill", style=["width: \{bar.width}"], ""),
    ]),
  ])
}

///|
fn pipeline_row(row : PipelineRow) -> @rabbita.Html {
  @html.div(class="row", [
    @html.strong(row.name),
    @html.span(row.owner),
    @html.span(class="status-pill", row.status),
  ])
}

///|
fn view(_dispatch : @rabbita.Dispatch[Unit], _model : Unit) -> @rabbita.Html {
  @html.div(class="dashboard-shell", [
    @html.section(class="dashboard-frame", [
      @html.header(class="hero-panel", [
        @html.div([
          @html.p(class="eyebrow", "MoonBit frontend template"),
          @html.h1(
            class="hero-title",
            "Operate from one calm, high-signal dashboard.",
          ),
          @html.p(
            class="hero-copy",
            "A pure frontend app shell for metrics, launches, and customer operations. No backend required, just a fast MoonBit UI ready for the agent to reshape.",
          ),
          @html.div(class="hero-actions", [
            @html.button(class="primary-action", "Plan next sprint"),
            @html.button(class="secondary-action", "View report"),
          ]),
        ]),
        @html.aside(class="signal-card", [
          @html.p(class="signal-value", "4.8x"),
          @html.p(
            class="signal-label",
            "Faster signal review after the dashboard refresh.",
          ),
        ]),
      ]),
      @html.section(class="metrics-grid", metrics.map(metric_card)),
      @html.section(class="content-grid", [
        @html.article(class="insight-panel", [
          @html.h2(class="section-title", "Conversion signals"),
          @html.div(class="bar-list", bars.map(bar_row)),
        ]),
        @html.article(class="table-panel", [
          @html.h2(class="section-title", "Active pipeline"),
          @html.div(pipeline.map(pipeline_row)),
        ]),
      ]),
    ]),
  ])
}

///|
fn main {
  let app = @rabbita.simple_cell(
    model=(),
    update=(_ : Unit, model) => model,
    view~,
  )
  @rabbita.new(app).mount("app")
}
