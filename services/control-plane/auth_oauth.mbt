///|
fn oauth_hex_digit(value : Int) -> Char {
  "0123456789ABCDEF"[value & 0xf].unsafe_to_char()
}

///|
fn oauth_url_encode(text : String) -> String {
  let out = StringBuilder()
  let bytes = @utf8.encode(text)
  for byte in bytes {
    let code = byte.to_int()
    if (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      (code >= 48 && code <= 57) ||
      code == 45 ||
      code == 46 ||
      code == 95 ||
      code == 126 {
      out.write_char(code.unsafe_to_char())
    } else {
      out.write_char('%')
      out.write_char(oauth_hex_digit(code >> 4))
      out.write_char(oauth_hex_digit(code))
    }
  }
  out.to_string()
}

///|
fn oauth_push_param(
  parts : Array[String],
  key : String,
  value : String,
) -> Unit {
  parts.push("\{oauth_url_encode(key)}=\{oauth_url_encode(value)}")
}

///|
fn oauth_form_body(parts : Array[String]) -> String {
  parts.join("&")
}

///|
fn pkce_s256_challenge(verifier : String) -> String {
  let encoded = @base64.encode(
    @crypto.sha256(@utf8.encode(verifier)).unsafe_reinterpret_as_bytes(),
    url_safe=true,
  )
  encoded.trim_end(chars="=").to_owned()
}

///|
fn github_authorization_url(
  client_id : String,
  redirect_uri : String,
  state : String,
  verifier : String,
) -> String {
  let parts : Array[String] = []
  oauth_push_param(parts, "response_type", "code")
  oauth_push_param(parts, "client_id", client_id)
  oauth_push_param(parts, "redirect_uri", redirect_uri)
  oauth_push_param(parts, "scope", "read:user user:email")
  oauth_push_param(parts, "state", state)
  oauth_push_param(parts, "code_challenge", pkce_s256_challenge(verifier))
  oauth_push_param(parts, "code_challenge_method", "S256")
  oauth_push_param(parts, "prompt", "select_account")
  "https://github.com/login/oauth/authorize?\{oauth_form_body(parts)}"
}

///|
fn github_token_request_body(
  client_id : String,
  client_secret : String,
  code : String,
  redirect_uri : String,
  verifier : String,
) -> String {
  let parts : Array[String] = []
  oauth_push_param(parts, "grant_type", "authorization_code")
  oauth_push_param(parts, "code", code)
  oauth_push_param(parts, "redirect_uri", redirect_uri)
  oauth_push_param(parts, "client_id", client_id)
  oauth_push_param(parts, "client_secret", client_secret)
  oauth_push_param(parts, "code_verifier", verifier)
  oauth_form_body(parts)
}

///|
fn github_access_token_from_response(body : String) -> Result[String, String] {
  let parsed = @json.parse(body) catch {
    _ => return Err("GitHub returned an invalid token response.")
  }
  match parsed {
    Object(fields) =>
      match fields.get("access_token") {
        Some(String(token)) if token != "" => Ok(token)
        _ => Err("GitHub returned a token response without an access token.")
      }
    _ => Err("GitHub returned an invalid token response.")
  }
}
