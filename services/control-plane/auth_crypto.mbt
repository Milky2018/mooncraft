///|
#borrow(byte_count)
extern "C" fn random_hex_ffi(byte_count : Int) -> Bytes = "mooncraft_random_hex"

///|
fn random_hex(byte_count : Int) -> String {
  bytes_to_string(random_hex_ffi(byte_count))
}

///|
fn new_session_token() -> String {
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
fn session_token_hash(token : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(token)))
}
