local M = {}

function M.parse(hex)
  local n = tonumber(hex:sub(2), 16)
  return { math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256 }
end

function M.mix(a, b, t)
  t = math.max(0, math.min(1, t))
  local from, to = M.parse(a), M.parse(b)
  local out = 0
  for i = 1, 3 do
    out = out * 256 + math.floor(from[i] + (to[i] - from[i]) * t + 0.5)
  end
  return string.format("#%06x", out)
end

local function linear(c)
  c = c / 255
  if c <= 0.04045 then
    return c / 12.92
  end
  return ((c + 0.055) / 1.055) ^ 2.4
end

function M.luminance(hex)
  local c = M.parse(hex)
  return 0.2126 * linear(c[1]) + 0.7152 * linear(c[2]) + 0.0722 * linear(c[3])
end

function M.contrast(a, b)
  local la, lb = M.luminance(a), M.luminance(b)
  local light, dark = math.max(la, lb), math.min(la, lb)
  return (light + 0.05) / (dark + 0.05)
end

function M.ink_on(background)
  local dark, light = "#16161d", "#f4f1e8"
  if M.contrast(dark, background) >= M.contrast(light, background) then
    return dark
  end
  return light
end

return M
