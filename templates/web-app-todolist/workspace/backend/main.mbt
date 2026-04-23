///|
fn asset_response(
  path : String,
  content_type : String,
) -> @mocket.HttpResponse {
  @mocket.HttpResponse::new(
    OK,
    headers={ "Content-Type": content_type },
    raw_body=@fs.read_file_to_bytes(path),
  ) catch {
    _ => @mocket.HttpResponse::new(NotFound).body("Not Found")
  }
}

///|
fn main {
  let args = @env.args()
  let port = if args.length() > 1 {
    @string.parse_int(args[1]) catch {
      _ => 4300
    }
  } else {
    4300
  }
  let static_dir = if args.length() > 2 { args[2] } else { "./preview-dist" }
  let info = @shared.default_info()
  let app = @mocket.new()
  app.get("/api/health", _ => @shared.HealthStatus::{
    ok: true,
    title: info.title,
    subtitle: info.subtitle,
  }.to_json())
  app.get("/", _ => asset_response(static_dir + "/index.html", "text/html; charset=utf-8"))
  app.get("/app", _ => asset_response(static_dir + "/app.js", "text/javascript; charset=utf-8"))
  app.get("/styles", _ => asset_response(static_dir + "/styles.css", "text/css; charset=utf-8"))
  app.serve(port=port)
}
