///|
struct AdminSecretRecord {
  value : String
}

///|
fn admin_secret_hint(value : String) -> String {
  "saved value (\{value.length()} chars)"
}

///|
fn admin_secret_summary_from_row(
  row : Map[String, @db.Param],
) -> @sdk.AdminSecretSummary {
  {
    id: row_text(row, "id"),
    name: row_text(row, "name"),
    value_hint: admin_secret_hint(row_text(row, "secret_value")),
    created_at: row_text(row, "created_at"),
    updated_at: row_text(row, "updated_at"),
  }
}

///|
fn admin_secret_record_from_row(
  row : Map[String, @db.Param],
) -> AdminSecretRecord {
  { value: row_text(row, "secret_value") }
}

///|
async fn Store::list_admin_secrets(
  self : Store,
) -> Array[@sdk.AdminSecretSummary] noraise {
  let rows = self.query_rows(
    (
      #|SELECT
      #|  id,
      #|  name,
      #|  secret_value,
      #|  created_at,
      #|  updated_at
      #|FROM admin_secrets
      #|ORDER BY name ASC;
    ),
  )
  let items : Array[@sdk.AdminSecretSummary] = []
  for row in rows {
    items.push(admin_secret_summary_from_row(row))
  }
  items
}

///|
async fn Store::get_admin_secret(
  self : Store,
  id : String,
) -> @sdk.AdminSecretSummary? noraise {
  match
    self.query_one(
      (
        #|SELECT
        #|  id,
        #|  name,
        #|  secret_value,
        #|  created_at,
        #|  updated_at
        #|FROM admin_secrets
        #|WHERE id = ?;
      ),
      params=[String(id)],
    ) {
    Some(row) => Some(admin_secret_summary_from_row(row))
    None => None
  }
}

///|
async fn Store::get_admin_secret_record_by_name(
  self : Store,
  name : String,
) -> AdminSecretRecord? noraise {
  match
    self.query_one(
      (
        #|SELECT
        #|  secret_value
        #|FROM admin_secrets
        #|WHERE name = ?;
      ),
      params=[String(name)],
    ) {
    Some(row) => Some(admin_secret_record_from_row(row))
    None => None
  }
}

///|
async fn Store::get_admin_secret_record_by_id(
  self : Store,
  id : String,
) -> AdminSecretRecord? noraise {
  match
    self.query_one(
      (
        #|SELECT
        #|  secret_value
        #|FROM admin_secrets
        #|WHERE id = ?;
      ),
      params=[String(id)],
    ) {
    Some(row) => Some(admin_secret_record_from_row(row))
    None => None
  }
}

///|
async fn Store::create_admin_secret(
  self : Store,
  name_input : String,
  value_input : String,
) -> Result[@sdk.AdminSecretSummary, String] noraise {
  let name = name_input.trim().to_owned()
  if name == "" {
    return Err("Secret name is required.")
  }
  if value_input.trim() == "" {
    return Err("Secret value is required.")
  }
  let id = next_id("admin-secret")
  let now = now_string()
  match
    self.exec_or_error(
      (
        #|INSERT INTO admin_secrets (
        #|  id,
        #|  name,
        #|  kind,
        #|  secret_value,
        #|  value_hint,
        #|  created_at,
        #|  updated_at
        #|) VALUES (?, ?, ?, ?, ?, ?, ?);
      ),
      "create admin secret",
      params=[
        String(id),
        String(name),
        String("value"),
        String(value_input),
        String(admin_secret_hint(value_input)),
        String(now),
        String(now),
      ],
    ) {
    Ok(_) =>
      match self.get_admin_secret(id) {
        Some(secret) => Ok(secret)
        None => Err("The secret was saved but could not be loaded.")
      }
    Err(message) => Err(message)
  }
}

///|
async fn Store::update_admin_secret(
  self : Store,
  id : String,
  name_input : String,
  value_input : String,
) -> Result[@sdk.AdminSecretSummary, String] noraise {
  let existing = match self.get_admin_secret(id) {
    Some(secret) => secret
    None => return Err("Secret not found.")
  }
  let existing_record = match self.get_admin_secret_record_by_id(id) {
    Some(record) => record
    None => return Err("Secret not found.")
  }
  let name = if name_input.trim() == "" {
    existing.name
  } else {
    name_input.trim().to_owned()
  }
  let update_result = if value_input.trim() == "" {
    self.exec_or_error(
      (
        #|UPDATE admin_secrets
        #|SET name = ?,
        #|    value_hint = ?,
        #|    updated_at = ?
        #|WHERE id = ?;
      ),
      "update admin secret",
      params=[
        String(name),
        String(admin_secret_hint(existing_record.value)),
        String(now_string()),
        String(id),
      ],
    )
  } else {
    self.exec_or_error(
      (
        #|UPDATE admin_secrets
        #|SET name = ?,
        #|    secret_value = ?,
        #|    value_hint = ?,
        #|    updated_at = ?
        #|WHERE id = ?;
      ),
      "update admin secret",
      params=[
        String(name),
        String(value_input),
        String(admin_secret_hint(value_input)),
        String(now_string()),
        String(id),
      ],
    )
  }
  match update_result {
    Ok(_) =>
      match self.get_admin_secret(id) {
        Some(secret) => Ok(secret)
        None => Err("The secret was updated but could not be loaded.")
      }
    Err(message) => Err(message)
  }
}

///|
async fn Store::delete_admin_secret(
  self : Store,
  id : String,
) -> Result[Unit, String] noraise {
  if self.get_admin_secret(id) is None {
    return Err("Secret not found.")
  }
  self.exec_or_error(
    "DELETE FROM admin_secrets WHERE id = ?;",
    "delete admin secret",
    params=[String(id)],
  )
}
