///|
fn app_page_html() -> String {
  (
    #|<!doctype html>
    #|<html>
    #|<head>
    #|  <meta charset='utf-8'>
    #|  <title>MoonCraft Starter</title>
    #|  <style>
    #|    body{font-family:sans-serif;margin:48px;background:#f7faf8;color:#15211f}
    #|    main{max-width:720px;margin:auto;padding:32px;border:1px solid #d8e4df;border-radius:24px;background:white}
    #|  </style>
    #|</head>
    #|<body>
    #|  <main>
    #|    <h1>MoonCraft Starter</h1>
    #|    <p>This project is ready for the builder to replace with your requested app.</p>
    #|  </main>
    #|</body>
    #|</html>
  )
}

///|
async fn main {
  let args = @env.args()
  let port = if args.length() > 1 {
    @string.parse_int(args[1]) catch {
      _ => 4300
    }
  } else {
    4300
  }
  let app = @mocket.new()
  app.get("/api/health", _ => {
    @mocket.HttpResponse::new(OK, headers={ "Content-Type": "application/json" }).body(
      "{\"ok\":true}",
    )
  })
  app.get("/", _ => {
    @mocket.HttpResponse::new(OK, headers={
      "Content-Type": "text/html; charset=utf-8",
    }).body(app_page_html())
  })
  app.listen("0.0.0.0:\{port}")
}
