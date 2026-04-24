///|
struct Channels {
  r : Int
  g : Int
  b : Int
}

///|
fn clamp_range(value : Int, minimum : Int, maximum : Int) -> Int {
  if value < minimum {
    minimum
  } else if value > maximum {
    maximum
  } else {
    value
  }
}

///|
fn int_abs(value : Int) -> Int {
  if value < 0 {
    -value
  } else {
    value
  }
}

///|
fn positive_mod(value : Int, modulus : Int) -> Int {
  let remainder = value % modulus
  if remainder < 0 {
    remainder + modulus
  } else {
    remainder
  }
}

///|
fn channel_mix(left : Int, right : Int, amount : Int) -> Int {
  let ratio = clamp_range(amount, 0, 255)
  (left * (255 - ratio) + right * ratio) / 255
}

///|
fn mix_channels(left : Channels, right : Channels, amount : Int) -> Channels {
  {
    r: channel_mix(left.r, right.r, amount),
    g: channel_mix(left.g, right.g, amount),
    b: channel_mix(left.b, right.b, amount),
  }
}

///|
fn pack_rgb(value : Channels) -> Int {
  clamp_range(value.r, 0, 255) * 65536 +
  clamp_range(value.g, 0, 255) * 256 +
  clamp_range(value.b, 0, 255)
}

///|
fn unpack_rgb(rgb : Int) -> Channels {
  let blue = positive_mod(rgb, 256)
  let rg = rgb / 256
  let green = positive_mod(rg, 256)
  let red = positive_mod(rg / 256, 256)
  { r: red, g: green, b: blue }
}

///|
fn luminance(value : Channels) -> Int {
  (value.r * 30 + value.g * 59 + value.b * 11) / 100
}

///|
fn noise_value(x : Int, y : Int, seed : Int) -> Int {
  positive_mod(x * 73856093 + y * 19349663 + seed * 83492791 + x * y * 17, 256)
}

///|
fn vignette_mask(x : Int, y : Int, width : Int, height : Int) -> Int {
  let safe_width = if width < 1 { 1 } else { width }
  let safe_height = if height < 1 { 1 } else { height }
  let dx = int_abs(x * 2 - safe_width)
  let dy = int_abs(y * 2 - safe_height)
  clamp_range((dx * 100 / safe_width + dy * 100 / safe_height) / 2, 0, 100)
}

///|
fn grade_channels(
  value : Channels,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
  exposure : Int,
  contrast : Int,
  grain : Int,
  vignette : Int,
  accent : Int,
) -> Channels {
  let exposure_offset = exposure * 3 / 2
  let contrast_factor = clamp_range(100 + contrast * 2, 0, 320)
  let grain_delta = (noise_value(x, y, accent + 41) - 128) * grain / 100
  let edge_darkening = vignette_mask(x, y, width, height) * vignette / 100
  let accent_lift = accent * 16 / 100
  let red = clamp_range(
    128 +
    (
      value.r +
      exposure_offset +
      accent_lift -
      edge_darkening +
      grain_delta -
      128
    ) *
    contrast_factor /
    100,
    0,
    255,
  )
  let green = clamp_range(
    128 +
    (value.g + exposure_offset + grain_delta / 2 - edge_darkening - 128) *
    contrast_factor /
    100,
    0,
    255,
  )
  let blue = clamp_range(
    128 +
    (
      value.b +
      exposure_offset -
      accent_lift / 2 -
      edge_darkening +
      grain_delta -
      128
    ) *
    contrast_factor /
    100,
    0,
    255,
  )
  { r: red, g: green, b: blue }
}

///|
fn thermal_palette(level : Int) -> Channels {
  let shadow = { r: 20, g: 34, b: 94 }
  let mid = { r: 103, g: 70, b: 208 }
  let warm = { r: 237, g: 110, b: 41 }
  let hot = { r: 255, g: 221, b: 102 }
  if level < 85 {
    mix_channels(shadow, mid, level * 3)
  } else if level < 170 {
    mix_channels(mid, warm, (level - 85) * 3)
  } else {
    mix_channels(warm, hot, clamp_range((level - 170) * 3, 0, 255))
  }
}

///|
fn posterize_channel(value : Int, levels : Int) -> Int {
  if levels <= 1 {
    clamp_range(value, 0, 255)
  } else {
    let bucket = clamp_range(value, 0, 255) * levels / 256
    clamp_range(bucket * 255 / (levels - 1), 0, 255)
  }
}

///|
fn stylize_channels(
  source : Channels,
  filter_mode : Int,
  accent : Int,
) -> Channels {
  let mode = positive_mod(filter_mode, 6)
  let accent_level = clamp_range(accent, 0, 100) * 255 / 100
  let lum = luminance(source)
  match mode {
    0 => {
      let warmth = {
        r: clamp_range(source.r + accent_level / 5, 0, 255),
        g: source.g,
        b: clamp_range(source.b - accent_level / 8, 0, 255),
      }
      mix_channels(source, warmth, 104)
    }
    1 => {
      let base = { r: lum, g: lum, b: lum }
      let silver = {
        r: clamp_range(lum + accent_level / 12, 0, 255),
        g: clamp_range(lum + 10, 0, 255),
        b: clamp_range(lum + accent_level / 8, 0, 255),
      }
      mix_channels(base, silver, 112)
    }
    2 => {
      let low = { r: 25, g: 41, b: clamp_range(72 + accent_level / 6, 0, 255) }
      let high = {
        r: 245,
        g: clamp_range(164 + accent_level / 10, 0, 255),
        b: 108,
      }
      mix_channels(low, high, lum)
    }
    3 => thermal_palette(lum)
    4 => {
      let levels = 3 + accent / 25
      {
        r: posterize_channel(source.r, levels),
        g: posterize_channel(source.g, levels),
        b: posterize_channel(source.b, levels),
      }
    }
    _ => {
      let highlight = clamp_range((lum - 120) * 2, 0, 255)
      let shadow = clamp_range((140 - lum) * 2, 0, 255)
      let bloom = {
        r: clamp_range(source.r + highlight / 3, 0, 255),
        g: clamp_range(source.g + highlight / 5, 0, 255),
        b: clamp_range(source.b + highlight / 2 + accent_level / 10, 0, 255),
      }
      let haze = {
        r: clamp_range(bloom.r - shadow / 6, 0, 255),
        g: clamp_range(bloom.g - shadow / 8, 0, 255),
        b: clamp_range(bloom.b + shadow / 5, 0, 255),
      }
      haze
    }
  }
}

///|
fn scene_channels(
  scene : Int,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
  accent : Int,
) -> Channels {
  let safe_width = if width < 1 { 1 } else { width }
  let safe_height = if height < 1 { 1 } else { height }
  let nx = x * 255 / safe_width
  let ny = y * 255 / safe_height
  let center_x = safe_width / 2
  let center_y = safe_height / 2
  let dx = int_abs(x - center_x)
  let dy = int_abs(y - center_y)
  let halo = clamp_range(
    255 - (dx * 160 / safe_width + dy * 220 / safe_height),
    0,
    255,
  )
  let strip = positive_mod(x * 5 + y * 3 + accent * 7, 255)
  match positive_mod(scene, 3) {
    0 => {
      let panel = if x > safe_width / 5 &&
        x < safe_width / 2 &&
        y > safe_height / 8 &&
        y < safe_height - safe_height / 7 {
        48
      } else {
        0
      }
      {
        r: clamp_range(28 + nx / 3 + halo / 4 + panel, 0, 255),
        g: clamp_range(44 + ny / 2 + panel / 2, 0, 255),
        b: clamp_range(84 + halo / 2 + strip / 10, 0, 255),
      }
    }
    1 => {
      let sweep = positive_mod(nx * 2 + ny + accent * 3, 255)
      {
        r: clamp_range(24 + sweep + halo / 5, 0, 255),
        g: clamp_range(56 + (255 - nx) / 2 + strip / 5, 0, 255),
        b: clamp_range(102 + ny / 3 + halo / 3, 0, 255),
      }
    }
    _ => {
      let scanner = if positive_mod(y + accent / 2, 24) < 12 { 18 } else { 0 }
      {
        r: clamp_range(18 + halo / 5 + scanner, 0, 255),
        g: clamp_range(74 + nx / 4 + halo / 3 + scanner, 0, 255),
        b: clamp_range(116 + ny / 3 + halo / 2, 0, 255),
      }
    }
  }
}

///|
pub fn filter_pixel(
  source_rgb : Int,
  filter_mode : Int,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
  exposure : Int,
  contrast : Int,
  grain : Int,
  vignette : Int,
  accent : Int,
) -> Int {
  let source = unpack_rgb(source_rgb)
  let styled = stylize_channels(source, filter_mode, accent)
  let graded = grade_channels(
    styled, x, y, width, height, exposure, contrast, grain, vignette, accent,
  )
  pack_rgb(graded)
}

///|
pub fn render_scene_pixel(
  scene : Int,
  filter_mode : Int,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
  exposure : Int,
  contrast : Int,
  grain : Int,
  vignette : Int,
  accent : Int,
) -> Int {
  let source = scene_channels(scene, x, y, width, height, accent)
  filter_pixel(
    pack_rgb(source),
    filter_mode,
    x,
    y,
    width,
    height,
    exposure,
    contrast,
    grain,
    vignette,
    accent,
  )
}

///|
fn main {
  ignore(())
}
