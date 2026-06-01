///|
async fn write_workspace_file(
  path : String,
  content : String,
) -> Result[Unit, String] noraise {
  ensure_dir(parent_dir(path)) catch {
    err => return Err("Failed to create parent directory for \{path}: \{err}")
  }
  @async_fs.write_file(path, content, create=0o644, truncate=true) catch {
    err => return Err("Failed to write \{path}: \{err}")
  }
  Ok(())
}
