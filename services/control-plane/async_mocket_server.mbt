///|
fn mocket_match_path(
  template : String,
  path : String,
) -> Map[String, StringView]? {
  if !template.contains(":") && !template.contains("*") {
    return if template == path { Some({}) } else { None }
  }
  mocket_match_path_segments(
    template.split("/").to_array(),
    path.split("/").collect(),
    0,
    0,
    {},
  )
}

///|
fn mocket_match_path_segments(
  template_parts : Array[StringView],
  path_parts : Array[StringView],
  template_idx : Int,
  path_idx : Int,
  params : Map[String, StringView],
) -> Map[String, StringView]? {
  if template_idx >= template_parts.length() && path_idx >= path_parts.length() {
    return Some(params)
  }
  if template_idx >= template_parts.length() {
    return None
  }
  if path_idx >= path_parts.length() {
    let template_part = template_parts[template_idx]
    return if template_part == "**" { Some(params) } else { None }
  }
  let template_part = template_parts[template_idx]
  let path_part = path_parts[path_idx]
  if template_part.to_owned().strip_prefix(":") is Some(param_name) {
    params[param_name.to_owned()] = path_part
    mocket_match_path_segments(
      template_parts,
      path_parts,
      template_idx + 1,
      path_idx + 1,
      params,
    )
  } else if template_part == "*" {
    params["_"] = path_part
    mocket_match_path_segments(
      template_parts,
      path_parts,
      template_idx + 1,
      path_idx + 1,
      params,
    )
  } else if template_part == "**" {
    let remaining_path = []
    let mut i = path_idx
    while i < path_parts.length() {
      remaining_path.push(path_parts[i])
      i = i + 1
    }
    params["_"] = remaining_path.join("/")
    Some(params)
  } else if template_part == path_part {
    mocket_match_path_segments(
      template_parts,
      path_parts,
      template_idx + 1,
      path_idx + 1,
      params,
    )
  } else {
    None
  }
}

///|
fn mocket_find_route(
  app : @mocket.Mocket,
  http_method : String,
  path : String,
) -> (@mocket.HttpHandler, Map[String, StringView])? {
  match app.static_routes.get(http_method) {
    Some(routes) =>
      match routes.get(path) {
        Some(handler) => return Some((handler, {}))
        None => ignore(())
      }
    None => ignore(())
  }
  match app.static_routes.get("*") {
    Some(routes) =>
      match routes.get(path) {
        Some(handler) => return Some((handler, {}))
        None => ignore(())
      }
    None => ignore(())
  }
  if app.dynamic_routes.get(http_method) is Some(routes) {
    for route in routes {
      if mocket_match_path(route.0, path) is Some(params) {
        return Some((route.1, params))
      }
    }
  }
  if app.dynamic_routes.get("*") is Some(routes) {
    for route in routes {
      if mocket_match_path(route.0, path) is Some(params) {
        return Some((route.1, params))
      }
    }
  }
  None
}

///|
fn http_method_name(request_method : @http.RequestMethod) -> String {
  match request_method {
    Get => "GET"
    Head => "HEAD"
    Post => "POST"
    Put => "PUT"
    Delete => "DELETE"
    Connect => "CONNECT"
    Options => "OPTIONS"
    Trace => "TRACE"
    Patch => "PATCH"
  }
}

///|
fn mocket_headers_from_http(
  headers : Map[String, String],
) -> Map[StringView, StringView] {
  let out : Map[StringView, StringView] = {}
  for key, value in headers {
    out[key] = value
  }
  out
}

///|
fn response_headers_to_http(
  response : @mocket.HttpResponse,
) -> Map[String, String] {
  let out : Map[String, String] = {}
  response.headers.each((key, value) => out[key.to_owned()] = value.to_owned())
  let cookie_values : Array[String] = []
  response.cookies
  .values()
  .each(cookie => cookie_values.push(cookie.to_string()))
  if cookie_values.length() > 0 {
    out["Set-Cookie"] = cookie_values.join(", ")
  }
  out
}

///|
fn status_reason(code : @mocket.StatusCode) -> String {
  if code.to_int() >= 400 {
    "Error"
  } else {
    "OK"
  }
}

///|
async fn serve_mocket_request(
  app : @mocket.Mocket,
  request : @http.Request,
  body_reader : &@io.Reader,
  connection : @http.ServerConnection,
) -> Unit noraise {
  let body : Bytes = try body_reader.read_all().binary() catch {
    _ => b""
  } noraise {
    value => value
  }
  let route_path = request.path.split("?").to_array()[0].to_owned()
  let http_method = http_method_name(request.meth)
  let (handler, params) = match
    mocket_find_route(app, http_method, route_path) {
    Some(route) => route
    None => (@mocket.handle_not_found(), {})
  }
  let event = @mocket.MocketEvent::{
    req: @mocket.HttpRequest::{
      http_method,
      url: request.path,
      raw_body: body,
      headers: mocket_headers_from_http(request.headers),
    },
    res: @mocket.HttpResponse::new(OK),
    params,
  }
  let responder = @mocket.execute_middlewares(app.middlewares, event, handler)
  responder.options(event.res)
  let buffer = @buffer.new()
  responder.output(buffer)
  event.res.raw_body = buffer.to_bytes()
  try {
    connection.send_response(
      event.res.status_code.to_int(),
      status_reason(event.res.status_code),
      extra_headers=response_headers_to_http(event.res),
    )
    connection.write(event.res.raw_body)
    connection.end_response()
  } catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
async fn serve_mocket_async(app : @mocket.Mocket, port : Int) -> Unit {
  let server = @http.Server::new(@socket.Addr::new(0U, port), reuse_addr=true)
  server.run_forever(
    (request, body_reader, connection) => {
      serve_mocket_request(app, request, body_reader, connection)
    },
    allow_failure=true,
  )
}
