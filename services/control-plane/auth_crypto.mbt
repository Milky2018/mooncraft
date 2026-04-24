///|
#borrow(byte_count)
extern "C" fn random_hex_ffi(byte_count : Int) -> Bytes = "moonbitcloud_random_hex"

///|
let pbkdf2_iterations = 100000

///|
fn random_hex(byte_count : Int) -> String {
  bytes_to_string(random_hex_ffi(byte_count))
}

///|
fn new_session_token() -> String {
  random_hex(32)
}

///|
fn new_account_action_token() -> String {
  random_hex(32)
}

///|
fn new_preview_public_id() -> String {
  random_hex(24)
}

///|
fn new_oauth_state() -> String {
  random_hex(24)
}

///|
fn new_pkce_verifier() -> String {
  random_hex(32)
}

///|
fn new_password_salt() -> String {
  random_hex(16)
}

///|
fn append_uint32_be(bytes : Array[Byte], value : Int) -> Unit {
  bytes.push(((value >> 24) & 0xff).to_byte())
  bytes.push(((value >> 16) & 0xff).to_byte())
  bytes.push(((value >> 8) & 0xff).to_byte())
  bytes.push((value & 0xff).to_byte())
}

///|
fn pbkdf2_sha256(password : String, salt : String, iterations : Int) -> String {
  let password_bytes = @utf8.encode(password)
  let salt_bytes = @utf8.encode(salt)
  let block = salt_bytes.to_array()
  append_uint32_be(block, 1)
  let mut u = @crypto.hmac(
    @crypto.SHA256::new(),
    password_bytes,
    Bytes::from_array(block),
  )
  let mixed = FixedArray::make(u.length(), b'\x00')
  for i = 0; i < u.length(); i = i + 1 {
    mixed[i] = u[i]
  }
  for _ in 1..<iterations {
    u = @crypto.hmac(
      @crypto.SHA256::new(),
      password_bytes,
      u.unsafe_reinterpret_as_bytes(),
    )
    for i = 0; i < mixed.length(); i = i + 1 {
      mixed[i] = mixed[i] ^ u[i]
    }
  }
  @crypto.bytes_to_hex_string(mixed.unsafe_reinterpret_as_bytes())
}

///|
fn hash_password(password : String) -> String {
  let salt = new_password_salt()
  let digest = pbkdf2_sha256(password, salt, pbkdf2_iterations)
  "pbkdf2_sha256$\{pbkdf2_iterations}$\{salt}$\{digest}"
}

///|
fn timing_safe_equals(left : String, right : String) -> Bool {
  let left_bytes = @utf8.encode(left)
  let right_bytes = @utf8.encode(right)
  if left_bytes.length() != right_bytes.length() {
    return false
  }
  let mut diff = 0
  for i = 0; i < left_bytes.length(); i = i + 1 {
    diff = diff | (left_bytes[i].to_int() ^ right_bytes[i].to_int())
  }
  diff == 0
}

///|
fn verify_password(password : String, stored_hash : String) -> Bool {
  let parts = stored_hash.split("$").to_array()
  if parts.length() != 4 || parts[0].to_string() != "pbkdf2_sha256" {
    return false
  }
  let iterations = @string.parse_int(parts[1]) catch { _ => return false }
  let expected = pbkdf2_sha256(password, parts[2].to_string(), iterations)
  timing_safe_equals(expected, parts[3].to_string())
}

///|
fn session_token_hash(token : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(token)))
}

///|
fn account_action_token_hash(token : String) -> String {
  session_token_hash(token)
}
