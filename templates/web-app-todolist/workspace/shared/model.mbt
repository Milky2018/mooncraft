///|
pub(all) struct AppInfo {
  title : String
  subtitle : String
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct HealthStatus {
  ok : Bool
  title : String
  subtitle : String
} derive(Debug, ToJson, FromJson)

///|
pub fn default_info() -> AppInfo {
  {
    title: "MoonBit Cloud App",
    subtitle: "Describe what you want, then let the agent reshape this project.",
  }
}
