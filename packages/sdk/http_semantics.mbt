///|
pub(all) enum HttpMethod {
  GET
  POST
  PUT
  PATCH
  DELETE
} derive(Eq, Debug)

///|
pub(all) enum SuccessStatus {
  Ok
  Created
  Accepted
  NoContent
} derive(Eq, Debug)

///|
pub(all) struct RouteSpec {
  http_method : HttpMethod
  path_pattern : String
  success_status : SuccessStatus
} derive(Debug)

///|
pub fn SuccessStatus::code(self : SuccessStatus) -> Int {
  match self {
    Ok => 200
    Created => 201
    Accepted => 202
    NoContent => 204
  }
}
