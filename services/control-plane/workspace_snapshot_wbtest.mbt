///|
async test "workspace snapshot stores archive as file metadata" {
  let root = "/tmp/mooncraft-workspace-snapshot-test-\{random_hex(6)}"
  ensure_dir(root)
  let store = match try_new_async("\{root}/state.sqlite") {
    Ok(store) => store
    Err(message) => abort(message)
  }
  let workspace = "\{root}/workspace"
  ensure_dir(workspace)
  ensure_dir("\{workspace}/.mooncakes/cache")
  @async_fs.write_file(
    "\{workspace}/main.mbt",
    "fn main { println(\"ok\") }\n",
    create=0o644,
    truncate=true,
  )
  @async_fs.write_file(
    "\{workspace}/.mooncakes/cache/tool.cache",
    "cache",
    create=0o644,
    truncate=true,
  )
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
  if !@async_fs.exists(metadata.path) {
    fail("expected workspace snapshot archive file")
  }
  inspect(metadata.checksum.length(), content="64")
  let snapshot_size = @string.parse_uint64(metadata.size_bytes) catch {
    _ => 0UL
  }
  if snapshot_size == 0UL {
    fail("expected non-empty workspace snapshot archive")
  }
  fs_remove_tree(workspace)
  if restore_workspace_snapshot_to_path(
      store, root, "project-snapshot", workspace,
    )
    is Err(message) {
    abort(message)
  }
  if !@async_fs.exists("\{workspace}/main.mbt") {
    fail("expected restored source file")
  }
  debug_inspect(@async_fs.exists("\{workspace}/.mooncakes"), content="false")
}
