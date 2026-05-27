///|
async test "workspace snapshot stores archive as file metadata" {
  let root = "/tmp/mooncraft-workspace-snapshot-test-\{random_hex(6)}"
  ensure_dir(root)
  defer safe_remove_tree(root)
  let store = match try_new_async("\{root}/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let workspace = "\{root}/workspace"
  ensure_dir(workspace)
  ensure_dir("\{workspace}/.mooncakes/cache")
  safe_write_string("\{workspace}/main.mbt", "fn main { println(\"ok\") }\n")
  safe_write_string("\{workspace}/.mooncakes/cache/tool.cache", "cache")
  if snapshot_workspace(store, root, "project-snapshot", workspace)
    is Err(message) {
    abort(message)
  }
  let archive_column = match
    store.column_exists("project_workspace_snapshots", "archive") {
    Ok(value) => value
    Err(message) => abort(message)
  }
  debug_inspect(archive_column, content="false")
  let metadata = match
    store.get_workspace_snapshot_metadata("project-snapshot") {
    Some(metadata) => metadata
    None => abort("expected workspace snapshot metadata")
  }
  debug_inspect(
    metadata.path,
    content="\"\{root}/data/runtime/projects/project-snapshot/snapshots/workspace.tar\"",
  )
  if !@fs.path_exists(metadata.path) {
    fail("expected workspace snapshot archive file")
  }
  inspect(metadata.checksum.length(), content="64")
  let snapshot_size = @string.parse_uint64(metadata.size_bytes) catch {
    _ => 0UL
  }
  if snapshot_size == 0UL {
    fail("expected non-empty workspace snapshot archive")
  }
  safe_remove_tree(workspace)
  if restore_workspace_snapshot(store, root, "project-snapshot", workspace)
    is Err(message) {
    abort(message)
  }
  if !@fs.path_exists("\{workspace}/main.mbt") {
    fail("expected restored source file")
  }
  debug_inspect(@fs.path_exists("\{workspace}/.mooncakes"), content="false")
}
