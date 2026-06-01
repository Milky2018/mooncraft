///|
fn admin_operation_log_from_row(
  row : Map[String, @db.Param],
) -> @sdk.AdminOperationLog {
  {
    id: row_text(row, "id"),
    level: row_text(row, "level"),
    operation: row_text(row, "operation"),
    message: row_text(row, "message"),
    detail: empty_to_none(row_text(row, "detail")),
    user_id: empty_to_none(row_text(row, "user_id")),
    project_id: empty_to_none(row_text(row, "project_id")),
    run_id: empty_to_none(row_text(row, "run_id")),
    status_code: match empty_to_none(row_text(row, "status_code")) {
      Some(_) => Some(row_int(row, "status_code"))
      None => None
    },
    created_at: row_text(row, "created_at"),
  }
}

///|
async fn Store::record_admin_operation_log(
  self : Store,
  operation : String,
  level : String,
  message : String,
  user_id : String?,
  project_id : String?,
  run_id : String?,
  status_code : Int?,
  detail : String?,
) -> Unit noraise {
  ignore(
    self.exec_or_error(
      (
        #|INSERT INTO admin_operation_logs (
        #|  id,
        #|  level,
        #|  operation,
        #|  message,
        #|  detail,
        #|  user_id,
        #|  project_id,
        #|  run_id,
        #|  status_code,
        #|  created_at
        #|)
        #|VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      ),
      "record admin operation log",
      params=[
        String(next_id("operation-log")),
        String(level),
        String(operation),
        String(message),
        nullable_text_param(detail),
        nullable_text_param(user_id),
        nullable_text_param(project_id),
        nullable_text_param(run_id),
        match status_code {
          Some(value) => Int(value)
          None => Null
        },
        String(now_string()),
      ],
    ),
  )
}

///|
async fn Store::list_recent_admin_operation_logs(
  self : Store,
  limit : Int,
) -> Array[@sdk.AdminOperationLog] noraise {
  let rows = self.query_rows(
    (
      #|SELECT
      #|  id,
      #|  level,
      #|  operation,
      #|  message,
      #|  COALESCE(detail, '') AS detail,
      #|  COALESCE(user_id, '') AS user_id,
      #|  COALESCE(project_id, '') AS project_id,
      #|  COALESCE(run_id, '') AS run_id,
      #|  COALESCE(status_code, '') AS status_code,
      #|  created_at
      #|FROM admin_operation_logs
      #|ORDER BY created_at DESC
      #|LIMIT ?;
    ),
    params=[Int(limit)],
  )
  let items : Array[@sdk.AdminOperationLog] = []
  for row in rows {
    items.push(admin_operation_log_from_row(row))
  }
  items
}
