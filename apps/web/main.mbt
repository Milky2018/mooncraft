///|
struct Model {
  projects : Array[@sdk.ProjectSummary]
  selected_project_id : String?
  project_detail : @sdk.ProjectDetail?
  messages : Array[@sdk.ChatMessage]
  run_status : @sdk.RunStatusResponse?
  draft : String
  create_project_pending : Bool
  sending_message : Bool
  notice : String?
}

///|
enum Msg {
  Bootstrap
  ProjectsLoaded(Result[Array[@sdk.ProjectSummary], Error])
  SelectProject(String)
  ProjectLoaded(Result[@sdk.ProjectDetail, Error])
  MessagesLoaded(Result[Array[@sdk.ChatMessage], Error])
  DraftChanged(String)
  CreateProject
  ProjectCreated(Result[@sdk.CreateProjectResponse, Error])
  SendDraft
  MessageSent(Result[@sdk.SendMessageResponse, Error])
  PollRun(String, String)
  RunLoaded(String, String, Result[@sdk.RunStatusResponse, Error])
}

///|
fn initial_model() -> Model {
  {
    projects: [],
    selected_project_id: None,
    project_detail: None,
    messages: [],
    run_status: None,
    draft: "",
    create_project_pending: false,
    sending_message: false,
    notice: None,
  }
}

///|
fn load_projects_cmd(dispatch : @rabbita.Dispatch[Msg]) -> @rabbita.Cmd {
  @http.get("/api/projects").expect_json(fn(result) {
    dispatch(ProjectsLoaded(result))
  })
}

///|
fn load_project_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
) -> @rabbita.Cmd {
  @rabbita.batch([
    @http.get("/api/projects/\{project_id}").expect_json(fn(result) {
      dispatch(ProjectLoaded(result))
    }),
    @http.get("/api/projects/\{project_id}/messages").expect_json(fn(result) {
      dispatch(MessagesLoaded(result))
    }),
  ])
}

///|
fn create_project_cmd(dispatch : @rabbita.Dispatch[Msg]) -> @rabbita.Cmd {
  let payload : @sdk.CreateProjectRequest = @sdk.CreateProjectRequest::{
    display_name: None,
  }
  @http.post("/api/projects")
  .with_json(payload)
  .expect_json(fn(result) { dispatch(ProjectCreated(result)) })
}

///|
fn send_message_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
  content : String,
) -> @rabbita.Cmd {
  let payload : @sdk.SendMessageRequest = @sdk.SendMessageRequest::{ content, }
  @http.post("/api/projects/\{project_id}/messages")
  .with_json(payload)
  .expect_json(fn(result) { dispatch(MessageSent(result)) })
}

///|
fn load_run_cmd(
  dispatch : @rabbita.Dispatch[Msg],
  project_id : String,
  run_id : String,
) -> @rabbita.Cmd {
  @http.get("/api/projects/\{project_id}/runs/\{run_id}").expect_json(fn(
    result,
  ) {
    dispatch(RunLoaded(project_id, run_id, result))
  })
}

///|
fn pick_selected_project_id(
  model : Model,
  projects : Array[@sdk.ProjectSummary],
) -> String? {
  match model.selected_project_id {
    Some(selected) => {
      for project in projects {
        if project.id == selected {
          return Some(selected)
        }
      }
      None
    }
    None => if projects.length() > 0 { Some(projects[0].id) } else { None }
  }
}

///|
fn active_run(model : Model) -> @sdk.RunStatusResponse? {
  match model.run_status {
    Some(run) if run.state is @sdk.Running => Some(run)
    _ =>
      match model.project_detail {
        Some(project) if project.status is @sdk.Running =>
          match project.current_run_id {
            Some(run_id) =>
              Some(@sdk.RunStatusResponse::{
                run_id,
                project_id: project.id,
                state: @sdk.Running,
                summary: None,
                error_message: None,
                preview: project.preview,
                started_at: project.updated_at,
                finished_at: None,
              })
            None => None
          }
        _ => None
      }
  }
}

///|
fn can_send(model : Model) -> Bool {
  model.selected_project_id is Some(_) &&
  model.draft != "" &&
  !model.sending_message &&
  active_run(model) is None
}

///|
fn append_local_user_message(
  model : Model,
  project_id : String,
  content : String,
) -> Array[@sdk.ChatMessage] {
  let messages = model.messages.copy()
  messages.push(@sdk.ChatMessage::{
    id: "local-" + content.length().to_string(),
    project_id,
    run_id: None,
    role: @sdk.User,
    content,
    created_at: "now",
  })
  messages
}

///|
fn error_notice(prefix : String, error : Error) -> String {
  prefix + " " + error.to_string()
}

///|
fn update(
  dispatch : @rabbita.Dispatch[Msg],
  msg : Msg,
  model : Model,
) -> (@rabbita.Cmd, Model) {
  match msg {
    Bootstrap => (load_projects_cmd(dispatch), { ..model, notice: None })
    ProjectsLoaded(Ok(projects)) => {
      let selected_project_id = pick_selected_project_id(model, projects)
      let cmd = match selected_project_id {
        Some(project_id) => load_project_cmd(dispatch, project_id)
        None => @rabbita.none
      }
      (cmd, { ..model, projects, selected_project_id })
    }
    ProjectsLoaded(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          notice: Some(error_notice("Projects could not be loaded.", error)),
        },
      )
    SelectProject(project_id) =>
      (
        load_project_cmd(dispatch, project_id),
        {
          ..model,
          selected_project_id: Some(project_id),
          project_detail: None,
          messages: [],
          notice: None,
        },
      )
    ProjectLoaded(Ok(project)) => {
      let cmd = match project.current_run_id {
        Some(run_id) if project.status is @sdk.Running =>
          @rabbita.delay(dispatch(PollRun(project.id, run_id)), 1000)
        _ => @rabbita.none
      }
      (cmd, { ..model, project_detail: Some(project) })
    }
    ProjectLoaded(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          notice: Some(
            error_notice("Project details could not be loaded.", error),
          ),
        },
      )
    MessagesLoaded(Ok(messages)) => (@rabbita.none, { ..model, messages, })
    MessagesLoaded(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          notice: Some(error_notice("Chat history could not be loaded.", error)),
        },
      )
    DraftChanged(value) => (@rabbita.none, { ..model, draft: value })
    CreateProject =>
      if model.create_project_pending {
        (@rabbita.none, model)
      } else {
        (
          create_project_cmd(dispatch),
          { ..model, create_project_pending: true, notice: None },
        )
      }
    ProjectCreated(Ok(response)) => {
      let project = response.project
      (
        @rabbita.batch([
          load_projects_cmd(dispatch),
          @http.get("/api/projects/\{project.id}/messages").expect_json(fn(
            result,
          ) {
            dispatch(MessagesLoaded(result))
          }),
        ]),
        {
          ..model,
          create_project_pending: false,
          selected_project_id: Some(project.id),
          project_detail: Some(project),
          messages: [],
          run_status: None,
        },
      )
    }
    ProjectCreated(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          create_project_pending: false,
          notice: Some(
            error_notice("A new project could not be created.", error),
          ),
        },
      )
    SendDraft =>
      match model.selected_project_id {
        Some(project_id) if can_send(model) => {
          let content = model.draft
          (
            send_message_cmd(dispatch, project_id, content),
            {
              ..model,
              draft: "",
              sending_message: true,
              notice: None,
              messages: append_local_user_message(model, project_id, content),
            },
          )
        }
        _ => (@rabbita.none, model)
      }
    MessageSent(Ok(response)) =>
      (
        @rabbita.delay(
          dispatch(PollRun(response.run.project_id, response.run.run_id)),
          1000,
        ),
        { ..model, run_status: Some(response.run), sending_message: false },
      )
    MessageSent(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          sending_message: false,
          notice: Some(error_notice("The request could not be sent.", error)),
        },
      )
    PollRun(project_id, run_id) =>
      (load_run_cmd(dispatch, project_id, run_id), model)
    RunLoaded(project_id, run_id, Ok(run)) =>
      if run.state is @sdk.Running {
        (
          @rabbita.delay(dispatch(PollRun(project_id, run_id)), 1000),
          { ..model, run_status: Some(run) },
        )
      } else {
        (
          @rabbita.batch([
            load_projects_cmd(dispatch),
            load_project_cmd(dispatch, project_id),
          ]),
          { ..model, run_status: Some(run), notice: run.error_message },
        )
      }
    RunLoaded(_, _, Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          notice: Some(
            error_notice("Run status could not be refreshed.", error),
          ),
        },
      )
  }
}

///|
fn shell_style() -> Array[String] {
  [
    "min-height: 100vh", "display: grid", "grid-template-columns: 272px minmax(360px, 1fr) minmax(420px, 0.95fr)",
    "gap: 18px", "padding: 18px",
  ]
}

///|
fn panel_style() -> Array[String] {
  [
    "background: rgba(255, 255, 255, 0.84)", "backdrop-filter: blur(16px)", "border: 1px solid rgba(21, 38, 58, 0.08)",
    "border-radius: 28px", "box-shadow: 0 24px 70px rgba(17, 40, 66, 0.10)", "overflow: hidden",
  ]
}

///|
fn status_badge(state : @sdk.RunState) -> @rabbita.Html {
  let label = state.label()
  let background = match state {
    @sdk.Idle => "#f1f5f9"
    @sdk.Running => "#e3f2ff"
    @sdk.Succeeded => "#e6f8ed"
    @sdk.Failed => "#fff0ea"
  }
  let foreground = match state {
    @sdk.Idle => "#425466"
    @sdk.Running => "#0f5ea6"
    @sdk.Succeeded => "#0b7a44"
    @sdk.Failed => "#bb4d2b"
  }
  @html.div(
    style=[
      "padding: 6px 10px",
      "border-radius: 999px",
      "background: " + background,
      "color: " + foreground,
      "font-size: 12px",
      "font-weight: 600",
      "letter-spacing: 0.02em",
    ],
    label,
  )
}

///|
fn render_project_tile(
  dispatch : @rabbita.Dispatch[Msg],
  selected_project_id : String?,
  project : @sdk.ProjectSummary,
) -> @rabbita.Html {
  let is_selected = selected_project_id == Some(project.id)
  let background = if is_selected {
    "linear-gradient(135deg, #1f7cff, #3fb6ff)"
  } else {
    "rgba(244, 247, 251, 0.92)"
  }
  let foreground = if is_selected { "#ffffff" } else { "#15263a" }
  @html.button(
    type_="button",
    on_click=dispatch(SelectProject(project.id)),
    style=[
      "width: 100%",
      "display: flex",
      "justify-content: space-between",
      "align-items: center",
      "gap: 12px",
      "padding: 14px 16px",
      "border: none",
      "border-radius: 18px",
      "background: " + background,
      "color: " + foreground,
      "text-align: left",
      "cursor: pointer",
    ],
    [
      @html.div(
        style=[
          "display: flex", "flex-direction: column", "gap: 4px", "min-width: 0",
        ],
        [
          @html.div(
            style=[
              "font-size: 15px", "font-weight: 650", "white-space: nowrap", "overflow: hidden",
              "text-overflow: ellipsis",
            ],
            project.display_name,
          ),
          @html.div(
            style=["font-size: 12px", "opacity: 0.75"],
            project.updated_at,
          ),
        ],
      ),
      status_badge(project.status),
    ],
  )
}

///|
fn render_message(message : @sdk.ChatMessage) -> @rabbita.Html {
  let is_user = message.role is @sdk.User
  let justify = if is_user { "flex-end" } else { "flex-start" }
  let background = if is_user {
    "linear-gradient(135deg, #1f7cff, #4ca8ff)"
  } else {
    "rgba(241, 245, 249, 0.98)"
  }
  let foreground = if is_user { "#ffffff" } else { "#203247" }
  @html.div(
    style=["display: flex", "justify-content: " + justify],
    @html.div(
      style=[
        "max-width: 78%",
        "padding: 16px 18px",
        "border-radius: 24px",
        "background: " + background,
        "color: " + foreground,
        "box-shadow: 0 16px 36px rgba(30, 62, 95, 0.10)",
      ],
      [
        @html.div(
          style=[
            "font-size: 12px", "font-weight: 700", "letter-spacing: 0.04em", "opacity: 0.82",
            "margin-bottom: 8px",
          ],
          message.role.label(),
        ),
        @html.div(
          style=[
            "font-size: 15px", "line-height: 1.65", "white-space: pre-wrap",
          ],
          message.content,
        ),
      ],
    ),
  )
}

///|
fn render_notice(notice : String?) -> @rabbita.Html {
  match notice {
    Some(message) =>
      @html.div(
        style=[
          "padding: 14px 16px", "border-radius: 18px", "background: rgba(255, 240, 234, 0.96)",
          "color: #9f3d20", "font-size: 14px", "line-height: 1.6",
        ],
        message,
      )
    None => @html.nothing
  }
}

///|
fn render_spinner(model : Model) -> @rabbita.Html {
  match active_run(model) {
    Some(_) =>
      @html.div(
        style=[
          "display: flex", "align-items: center", "gap: 12px", "padding: 14px 16px",
          "border-radius: 18px", "background: rgba(227, 242, 255, 0.88)", "color: #135c9e",
          "font-size: 14px", "font-weight: 600",
        ],
        [
          @html.div(
            style=[
              "width: 12px", "height: 12px", "border-radius: 999px", "background: #1f7cff",
              "box-shadow: 0 0 0 8px rgba(31, 124, 255, 0.12)",
            ],
            "",
          ),
          @html.div(
            "MoonBit Cloud is updating your app and refreshing the preview.",
          ),
        ],
      )
    None => @html.nothing
  }
}

///|
fn render_projects_panel(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let tiles = model.projects.map(fn(project) {
    render_project_tile(dispatch, model.selected_project_id, project)
  })
  @html.div(
    style=panel_style() +
      ["display: flex", "flex-direction: column", "padding: 18px", "gap: 18px"],
    [
      @html.div(
        style=[
          "display: flex", "justify-content: space-between", "align-items: center",
          "gap: 12px",
        ],
        [
          @html.div([
            @html.div(
              style=[
                "font-size: 13px", "font-weight: 700", "letter-spacing: 0.08em",
                "text-transform: uppercase", "color: #4d6278",
              ],
              "MoonBit Cloud",
            ),
            @html.div(
              style=["margin-top: 6px", "font-size: 24px", "font-weight: 760"],
              "Projects",
            ),
          ]),
          @html.button(
            type_="button",
            disabled=model.create_project_pending,
            on_click=dispatch(CreateProject),
            style=[
              "padding: 12px 16px", "border: none", "border-radius: 16px", "background: linear-gradient(135deg, #0fbc85, #2fd6a2)",
              "color: #ffffff", "font-size: 14px", "font-weight: 700", "cursor: pointer",
            ],
            if model.create_project_pending {
              "Creating..."
            } else {
              "+ New"
            },
          ),
        ],
      ),
      @html.div(
        style=["display: flex", "flex-direction: column", "gap: 10px"],
        if tiles.length() == 0 {
          [
            @html.div(
              style=[
                "padding: 18px", "border-radius: 18px", "background: rgba(244, 247, 251, 0.92)",
                "font-size: 14px", "line-height: 1.6", "color: #5c6d7f",
              ],
              "Create the first project to open an empty chat and start building.",
            ),
          ]
        } else {
          tiles
        },
      ),
    ],
  )
}

///|
fn render_workspace_panel(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let title = match model.project_detail {
    Some(project) => project.display_name
    None => "Workspace"
  }
  let message_nodes = if model.messages.length() == 0 &&
    model.selected_project_id is Some(_) {
    [
      @html.div(
        style=[
          "padding: 28px", "border-radius: 24px", "background: rgba(243, 247, 251, 0.94)",
          "font-size: 15px", "line-height: 1.75", "color: #596b7d",
        ],
        "Start with a product request. MoonBit Cloud will create a real workspace, run one Codex thread for this project, and keep the code hidden while the preview updates.",
      ),
    ]
  } else {
    model.messages.map(render_message)
  }
  let send_disabled = !can_send(model)
  let composer_placeholder = if model.selected_project_id is Some(_) {
    "Describe the product change you want. Code stays hidden; the preview is the main output."
  } else {
    "Create or select a project first."
  }
  let send_label = if active_run(model) is Some(_) {
    "Working..."
  } else {
    "Send"
  }
  @html.div(
    style=panel_style() +
      ["display: flex", "flex-direction: column", "min-height: 0"],
    [
      @html.div(
        style=[
          "padding: 22px 24px 18px", "border-bottom: 1px solid rgba(21, 38, 58, 0.06)",
          "display: flex", "justify-content: space-between", "align-items: center",
          "gap: 12px",
        ],
        [
          @html.div([
            @html.div(
              style=[
                "font-size: 13px", "font-weight: 700", "letter-spacing: 0.06em",
                "text-transform: uppercase", "color: #5c6d7f",
              ],
              "Chat Workspace",
            ),
            @html.div(
              style=["margin-top: 6px", "font-size: 28px", "font-weight: 760"],
              title,
            ),
          ]),
          match model.project_detail {
            Some(project) => status_badge(project.status)
            None => @html.nothing
          },
        ],
      ),
      @html.div(
        style=[
          "padding: 18px 24px", "display: flex", "flex-direction: column", "gap: 14px",
        ],
        [render_notice(model.notice), render_spinner(model)],
      ),
      @html.div(
        style=[
          "flex: 1", "padding: 0 24px 20px", "display: flex", "flex-direction: column",
          "gap: 14px", "overflow-y: auto",
        ],
        message_nodes,
      ),
      @html.div(
        style=[
          "padding: 20px 24px 24px", "border-top: 1px solid rgba(21, 38, 58, 0.06)",
          "display: flex", "flex-direction: column", "gap: 14px",
        ],
        [
          @html.textarea(
            rows=5,
            value=model.draft,
            disabled=model.selected_project_id is None ||
              active_run(model) is Some(_),
            placeholder=composer_placeholder,
            on_input=fn(value) { dispatch(DraftChanged(value)) },
            style=[
              "width: 100%", "padding: 18px 18px 16px", "border: 1px solid rgba(21, 38, 58, 0.08)",
              "border-radius: 22px", "font-size: 15px", "line-height: 1.6", "resize: none",
              "background: rgba(248, 250, 253, 0.96)",
            ],
            "",
          ),
          @html.div(
            style=[
              "display: flex", "justify-content: space-between", "align-items: center",
              "gap: 12px",
            ],
            [
              @html.div(
                style=["font-size: 13px", "color: #687a8c", "line-height: 1.6"],
                "One workspace and one persistent Codex thread are kept per project.",
              ),
              @html.button(
                type_="button",
                disabled=send_disabled,
                on_click=dispatch(SendDraft),
                style=[
                  "padding: 14px 18px", "border: none", "border-radius: 18px", "background: linear-gradient(135deg, #1f7cff, #45b0ff)",
                  "color: #ffffff", "font-size: 14px", "font-weight: 700", "cursor: pointer",
                ],
                send_label,
              ),
            ],
          ),
        ],
      ),
    ],
  )
}

///|
fn render_preview_panel(model : Model) -> @rabbita.Html {
  let preview = model.project_detail.bind(fn(project) { project.preview })
  let body = match model.project_detail {
    None =>
      @html.div(
        style=[
          "display: grid", "place-items: center", "height: 100%", "padding: 30px",
          "text-align: center", "font-size: 15px", "line-height: 1.7", "color: #617386",
        ],
        "Pick a project to inspect the live preview. The app view is the main artifact in this v1 flow.",
      )
    Some(_) =>
      match preview {
        Some(target) =>
          @html.iframe(title="Live Preview", src=target.url, loading="eager", style=[
            "width: 100%", "height: 100%", "border: none", "background: #ffffff",
          ])
        None =>
          @html.div(
            style=[
              "display: grid", "place-items: center", "height: 100%", "padding: 30px",
              "text-align: center", "font-size: 15px", "line-height: 1.7", "color: #617386",
            ],
            if active_run(model) is Some(_) {
              "The preview panel will load here as soon as the first successful run finishes."
            } else {
              "No preview yet. Send the first message to generate and run the app."
            },
          )
      }
  }
  let status = match preview {
    Some(target) => if target.healthy { @sdk.Succeeded } else { @sdk.Failed }
    None => if active_run(model) is Some(_) { @sdk.Running } else { @sdk.Idle }
  }
  @html.div(
    style=panel_style() +
      ["display: flex", "flex-direction: column", "overflow: hidden"],
    [
      @html.div(
        style=[
          "padding: 22px 24px 18px", "border-bottom: 1px solid rgba(21, 38, 58, 0.06)",
          "display: flex", "justify-content: space-between", "align-items: center",
          "gap: 12px",
        ],
        [
          @html.div([
            @html.div(
              style=[
                "font-size: 13px", "font-weight: 700", "letter-spacing: 0.06em",
                "text-transform: uppercase", "color: #5c6d7f",
              ],
              "Live Preview",
            ),
            @html.div(
              style=["margin-top: 6px", "font-size: 28px", "font-weight: 760"],
              "Running App",
            ),
          ]),
          status_badge(status),
        ],
      ),
      @html.div(
        style=[
          "flex: 1", "min-height: 0", "background: linear-gradient(180deg, rgba(251,253,255,0.96), rgba(244,247,251,0.88))",
        ],
        body,
      ),
    ],
  )
}

///|
fn view(dispatch : @rabbita.Dispatch[Msg], model : Model) -> @rabbita.Html {
  @html.div(style=shell_style(), [
    render_projects_panel(dispatch, model),
    render_workspace_panel(dispatch, model),
    render_preview_panel(model),
  ])
}

///|
fn main {
  let (dispatch, root) = @rabbita.cell_with_dispatch(
    model=initial_model(),
    update~,
    view~,
  )
  let app = @rabbita.new(root)
  app.with_init(dispatch(Bootstrap))
  app.mount("app")
}
