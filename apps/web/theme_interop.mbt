///|
extern "js" fn js_load_theme_mode(succeed~ : (String, String) -> Unit) =
  #| (succeed) => {
  #|   const resolveTheme = (mode) => {
  #|     if (mode === "light" || mode === "dark") return mode;
  #|     if (
  #|       window.matchMedia &&
  #|       window.matchMedia("(prefers-color-scheme: light)").matches
  #|     ) {
  #|       return "light";
  #|     }
  #|     return "dark";
  #|   };
  #|   let mode = "system";
  #|   try {
  #|     const stored = window.localStorage.getItem("mooncraft-theme");
  #|     if (stored === "dark" || stored === "light" || stored === "system") {
  #|       mode = stored;
  #|     }
  #|   } catch (_) {}
  #|   const resolved = resolveTheme(mode);
  #|   try {
  #|     document.documentElement.dataset.theme = mode;
  #|     document.documentElement.dataset.resolvedTheme = resolved;
  #|     document.documentElement.style.colorScheme = resolved;
  #|   } catch (_) {}
  #|   succeed(mode, resolved);
  #| }

///|
extern "js" fn js_persist_theme_mode(
  value : String,
  succeed~ : (String) -> Unit,
) =
  #| (value, succeed) => {
  #|   const resolveTheme = (mode) => {
  #|     if (mode === "light" || mode === "dark") return mode;
  #|     if (
  #|       window.matchMedia &&
  #|       window.matchMedia("(prefers-color-scheme: light)").matches
  #|     ) {
  #|       return "light";
  #|     }
  #|     return "dark";
  #|   };
  #|   const mode = value === "light" || value === "dark" || value === "system" ? value : "system";
  #|   const resolved = resolveTheme(mode);
  #|   try {
  #|     window.localStorage.setItem("mooncraft-theme", mode);
  #|   } catch (_) {}
  #|   try {
  #|     document.documentElement.dataset.theme = mode;
  #|     document.documentElement.dataset.resolvedTheme = resolved;
  #|     document.documentElement.style.colorScheme = resolved;
  #|   } catch (_) {}
  #|   succeed(resolved);
  #| }
