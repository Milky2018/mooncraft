///|
priv struct RuntimeDisplayEvent {
  kind : String
  code : String
  content : String
}

///|
fn runtime_display_event_value(
  kind : String,
  code : String,
  content : String,
) -> RuntimeDisplayEvent {
  { kind, code, content }
}

///|
fn json_object_fields(line : String) -> Map[String, Json]? {
  let parsed = @json.parse(line) catch { _ => return None }
  match parsed {
    Object(fields) => Some(fields)
    _ => None
  }
}

///|
fn json_string_field(fields : Map[String, Json], name : String) -> String? {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn json_line_string_field(line : String, field : String) -> String? {
  match json_object_fields(line) {
    Some(fields) => json_string_field(fields, field)
    None => None
  }
}

///|
fn extract_runtime_session_id(events : String) -> String? {
  let mut session_id : String? = None
  for raw_line in events.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.to_owned()
    match json_line_string_field(line, "runtime_session_id") {
      Some(value) if value.trim() != "" => session_id = Some(value)
      _ => ()
    }
  }
  session_id
}

///|
fn runtime_display_event(line : String) -> RuntimeDisplayEvent? {
  let trimmed = line.trim().to_owned()
  match json_object_fields(trimmed) {
    Some(fields) =>
      match json_string_field(fields, "type") {
        Some("runtime.started") =>
          Some(
            runtime_display_event_value(
              "status",
              @sdk.run_event_code_builder_started(),
              "Started the builder session.",
            ),
          )
        Some("turn.started") =>
          Some(
            runtime_display_event_value(
              "status",
              @sdk.run_event_code_turn_planning(),
              "Planning the change.",
            ),
          )
        Some("turn.completed") =>
          Some(
            runtime_display_event_value(
              "status",
              @sdk.run_event_code_builder_ended(),
              "Builder session ended.",
            ),
          )
        Some("turn.failed") =>
          Some(
            runtime_display_event_value(
              "status",
              @sdk.run_event_code_builder_failed(),
              "The app update failed.",
            ),
          )
        _ => None
      }
    None => None
  }
}
