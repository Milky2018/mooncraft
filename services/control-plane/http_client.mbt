///|
priv struct UpstreamHttpResponse {
  code : Int
  headers : Map[String, String]
  body : Bytes
}

///|
fn http_status_success(code : Int) -> Bool {
  code >= 200 && code < 300
}

///|
fn http_response_text(response : UpstreamHttpResponse) -> String {
  bytes_to_string(response.body)
}

///|
fn split_http_url(url : String) -> Result[(String, String), String] {
  let scheme_index = match url.find("://") {
    Some(index) => index
    None => return Err("HTTP URL is missing a scheme.")
  }
  let after_scheme = scheme_index + 3
  let path_index = match url[after_scheme:].find("/") {
    Some(index) => after_scheme + index
    None => return Ok((url, "/"))
  }
  let origin = url[:path_index].to_owned()
  let path = url[path_index:].to_owned()
  if path == "" {
    Ok((origin, "/"))
  } else {
    Ok((origin, path))
  }
}

///|
async fn http_request_bytes(
  request_method : @http.RequestMethod,
  url : String,
  headers : Map[String, String],
  body : Bytes,
) -> Result[UpstreamHttpResponse, String] noraise {
  let (origin, path) = match split_http_url(url) {
    Ok(parts) => parts
    Err(message) => return Err(message)
  }
  let client = try @http.Client::new(origin) catch {
    err => return Err("HTTP client could not connect: \{err}")
  } noraise {
    client => client
  }
  defer client.close()
  let response = try {
    client.request(request_method, path, extra_headers=headers)
    if body.length() > 0 {
      client.write(body)
    }
    client.end_request()
  } catch {
    err => return Err("HTTP request failed: \{err}")
  } noraise {
    response => response
  }
  let response_body = try client.read_all().binary() catch {
    err => return Err("HTTP response body could not be read: \{err}")
  } noraise {
    body => body
  }
  Ok({ code: response.code, headers: response.headers, body: response_body })
}

///|
async fn http_get(
  url : String,
  headers? : Map[String, String] = {},
) -> Result[UpstreamHttpResponse, String] noraise {
  let result = try @http.get(url, headers~) catch {
    err => return Err("HTTP GET failed: \{err}")
  } noraise {
    result => result
  }
  let (response, body) = result
  Ok({ code: response.code, headers: response.headers, body: body.binary() })
}

///|
async fn http_post(
  url : String,
  body : String,
  headers? : Map[String, String] = {},
) -> Result[UpstreamHttpResponse, String] noraise {
  let result = try @http.post(url, body, headers~) catch {
    err => return Err("HTTP POST failed: \{err}")
  } noraise {
    result => result
  }
  let (response, response_body) = result
  Ok({
    code: response.code,
    headers: response.headers,
    body: response_body.binary(),
  })
}
