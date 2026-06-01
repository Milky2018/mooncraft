///|
async test "admin operation logs store recent errors" {
  let root = "/tmp/mooncraft-admin-operation-logs-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  store.record_admin_operation_log(
    "create_project",
    "error",
    "GitHub repository access is not connected.",
    Some("user-1"),
    Some("project-1"),
    None,
    Some(409),
    Some("source credential missing"),
  )
  let logs = store.list_recent_admin_operation_logs(10)
  debug_inspect(
    logs,
    content=(
        #|[
        #|  {
        #|    id: "operation-log-XXX",
        #|    level: "error",
        #|    operation: "create_project",
        #|    message: "GitHub repository access is not connected.",
        #|    detail: Some("source credential missing"),
        #|    user_id: Some("user-1"),
        #|    project_id: Some("project-1"),
        #|    run_id: None,
        #|    status_code: Some(409),
        #|    created_at: "XXX",
        #|  },
        #|]
      )
      .replace_all(old="operation-log-XXX", new=logs[0].id)
      .replace_all(old="\"XXX\"", new="\"\{logs[0].created_at}\""),
  )
}
