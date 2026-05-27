///|
fn web_public_root(root : String) -> String {
  "\{root}/apps/web/public"
}

///|
fn web_public_path(root : String, relative : String) -> String {
  "\{web_public_root(root)}/\{relative}"
}

///|
async fn web_public_string(
  root : String,
  relative : String,
  fallback : String,
) -> String noraise {
  @async_fs.read_file(web_public_path(root, relative)).text() catch {
    _ => fallback
  }
}

///|
fn safe_web_public_relative_path(path : String) -> String? {
  let parts = path.split("/").to_array()
  let safe_parts : Array[String] = []
  for part in parts {
    let piece = part.to_owned()
    if piece == "" {
      continue
    }
    if piece == "." || piece == ".." {
      return None
    }
    safe_parts.push(piece)
  }
  if safe_parts.length() == 0 {
    None
  } else {
    Some(safe_parts.join("/"))
  }
}

///|
async fn web_public_response(
  root : String,
  path : String,
) -> @mocket.HttpResponse noraise {
  match safe_web_public_relative_path(path) {
    Some(relative) => {
      let asset_path = web_public_path(root, relative)
      let asset_exists = fs_is_file(asset_path) catch { _ => false }
      if !asset_exists {
        return text_response(NotFound, "Not Found")
      }
      let content = @async_fs.read_file(asset_path).binary() catch {
        _ => return text_response(NotFound, "Not Found")
      }
      asset_response_bytes(static_preview_content_type(relative), content)
    }
    None => text_response(NotFound, "Not Found")
  }
}
