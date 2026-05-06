///|
using @cmd {type Cmd, type Dispatch, trait Scheduler}

///|
struct RawHttpResponse {
  status : Int
  body : String
} derive(FromJson)

///|
enum RequestBody {
  Json(Json)
  Empty
}

///|
struct Request {
  url : String
  http_method : String
  body : RequestBody
}

///|
fn network_error(detail : String) -> @sdk.ApiError {
  let message = if detail == "" {
    "The network request failed before the server returned a response."
  } else {
    "The network request failed: \{detail}"
  }
  { code: NetworkFailure, message }
}

///|
fn unexpected_response_error(message : String) -> @sdk.ApiError {
  { code: UnexpectedResponse, message }
}

///|
fn fallback_error_code(status : Int) -> @sdk.ApiErrorCode {
  match status {
    400 => InvalidJson
    401 => Unauthorized
    404 => NotFound
    409 => Conflict
    422 => ValidationFailed
    503 => ServiceUnavailable
    _ => UnexpectedResponse
  }
}

///|
fn decode_raw_http_response(
  raw : String,
) -> Result[RawHttpResponse, @sdk.ApiError] {
  let parsed = @json.parse(raw) catch {
    _ =>
      return Err(
        unexpected_response_error(
          "The browser returned an invalid HTTP response envelope.",
        ),
      )
  }
  Ok(
    @json.from_json(parsed) catch {
      _ =>
        return Err(
          unexpected_response_error(
            "The browser returned an HTTP response envelope with an unexpected shape.",
          ),
        )
    },
  )
}

///|
fn[T : FromJson] decode_json_success(body : String) -> Result[T, @sdk.ApiError] {
  let parsed = @json.parse(body) catch {
    _ =>
      return Err(
        unexpected_response_error(
          "The server returned invalid JSON for this response.",
        ),
      )
  }
  Ok(
    @json.from_json(parsed) catch {
      _ =>
        return Err(
          unexpected_response_error(
            "The server returned JSON that did not match the expected response shape.",
          ),
        )
    },
  )
}

///|
fn decode_error_response(status : Int, body : String) -> @sdk.ApiError {
  let parsed = @json.parse(body) catch {
    _ => {
      let fallback = if body == "" {
        "The server returned an empty error response (\{status})."
      } else {
        body
      }
      return { code: fallback_error_code(status), message: fallback }
    }
  }
  let response : @sdk.ApiErrorResponse = @json.from_json(parsed) catch {
    _ => {
      let fallback = if body == "" {
        "The server returned an unexpected error response (\{status})."
      } else {
        body
      }
      return { code: fallback_error_code(status), message: fallback }
    }
  }
  response.error
}

///|
fn is_success_status(status : Int) -> Bool {
  status >= 200 && status < 300
}

///|
fn Request::send_response(
  self : Request,
  on_success~ : (RawHttpResponse) -> Cmd,
  on_failure~ : (@sdk.ApiError) -> Cmd,
) -> Cmd {
  @cmd.custom_cmd(fn(scheduler : &Scheduler) {
    let (content_type, body, has_body) = match self.body {
      Json(json) => ("application/json", json.stringify(), true)
      Empty => ("text/plain", "", false)
    }
    js_request(
      self.url,
      self.http_method,
      content_type~,
      body~,
      has_body~,
      succeed=raw => {
        match decode_raw_http_response(raw) {
          Ok(response) => scheduler.add(on_success(response))
          Err(error) => scheduler.add(on_failure(error))
        }
      },
      failed=detail => scheduler.add(on_failure(network_error(detail))),
    )
  })
}

///|
fn[T : FromJson] Request::expect_json(
  self : Request,
  msg : Dispatch[Result[T, @sdk.ApiError]],
) -> Cmd {
  self.send_response(
    on_success=response => {
      let result = if is_success_status(response.status) {
        decode_json_success(response.body)
      } else {
        Err(decode_error_response(response.status, response.body))
      }
      msg(result)
    },
    on_failure=error => msg(Err(error)),
  )
}

///|
fn Request::expect_empty(
  self : Request,
  msg : Dispatch[Result[Unit, @sdk.ApiError]],
) -> Cmd {
  self.send_response(
    on_success=response => {
      let result = if is_success_status(response.status) {
        Ok(())
      } else {
        Err(decode_error_response(response.status, response.body))
      }
      msg(result)
    },
    on_failure=error => msg(Err(error)),
  )
}

///|
pub fn[T : FromJson] get_json(
  url : String,
  msg : Dispatch[Result[T, @sdk.ApiError]],
) -> Cmd {
  { url, http_method: "GET", body: Empty }.expect_json(msg)
}

///|
pub fn[Req : ToJson, Resp : FromJson] post_json(
  url : String,
  payload : Req,
  msg : Dispatch[Result[Resp, @sdk.ApiError]],
) -> Cmd {
  { url, http_method: "POST", body: Json(payload.to_json()) }.expect_json(msg)
}

///|
pub fn[Req : ToJson, Resp : FromJson] put_json(
  url : String,
  payload : Req,
  msg : Dispatch[Result[Resp, @sdk.ApiError]],
) -> Cmd {
  { url, http_method: "PUT", body: Json(payload.to_json()) }.expect_json(msg)
}

///|
pub fn post_empty(
  url : String,
  msg : Dispatch[Result[Unit, @sdk.ApiError]],
) -> Cmd {
  { url, http_method: "POST", body: Empty }.expect_empty(msg)
}

///|
pub fn[Resp : FromJson] post_empty_json(
  url : String,
  msg : Dispatch[Result[Resp, @sdk.ApiError]],
) -> Cmd {
  { url, http_method: "POST", body: Empty }.expect_json(msg)
}

///|
pub fn delete_empty(
  url : String,
  msg : Dispatch[Result[Unit, @sdk.ApiError]],
) -> Cmd {
  { url, http_method: "DELETE", body: Empty }.expect_empty(msg)
}

///|
extern "js" fn js_request(
  url : String,
  http_method : String,
  content_type~ : String,
  body~ : String,
  has_body~ : Bool,
  succeed~ : (String) -> Unit,
  failed~ : (String) -> Unit,
) =
  #| (url, method, contentType, body, hasBody, succeed, failed) => {
  #|   const headers = { "Accept": "application/json" };
  #|   if (hasBody) {
  #|     headers["Content-Type"] = contentType;
  #|   }
  #|   const config = { method, headers };
  #|   if (hasBody) {
  #|     config.body = body;
  #|   }
  #|   fetch(url, config)
  #|     .then(async (response) => {
  #|       const text = await response.text();
  #|       succeed(JSON.stringify({ status: response.status, body: text }));
  #|     })
  #|     .catch((error) => failed(error?.toString?.() ?? String(error)));
  #| }
