///|
pub(all) enum ApiErrorCode {
  InvalidJson
  ValidationFailed
  Unauthorized
  InvalidCredentials
  NotFound
  Conflict
  PreviewUnavailable
  ServiceUnavailable
  UnexpectedResponse
  NetworkFailure
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct ApiError {
  code : ApiErrorCode
  message : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct ApiErrorResponse {
  error : ApiError
} derive(Debug, ToJson, FromJson)
