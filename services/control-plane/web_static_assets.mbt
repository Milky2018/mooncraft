///|
fn web_static_assets_root(root : String) -> String {
  root + "/apps/web/assets/control-plane"
}

///|
fn web_static_asset_path(root : String, relative : String) -> String {
  web_static_assets_root(root) + "/" + relative
}

///|
fn web_static_asset_string(
  root : String,
  relative : String,
  fallback : String,
) -> String {
  safe_read_string_or(web_static_asset_path(root, relative), fallback)
}

///|
fn safe_web_static_asset_relative_path(path : String) -> String? {
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
fn web_static_asset_response(
  root : String,
  path : String,
) -> @mocket.HttpResponse {
  match safe_web_static_asset_relative_path(path) {
    Some(relative) => {
      let asset_path = web_static_asset_path(root, relative)
      if !(@fs.is_file(asset_path) catch { _ => false }) {
        return text_response(NotFound, "Not Found")
      }
      asset_response_bytes(
        static_preview_content_type(relative),
        safe_read_bytes_or(asset_path, b""),
      )
    }
    None => text_response(NotFound, "Not Found")
  }
}
