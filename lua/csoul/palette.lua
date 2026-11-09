local color = require("csoul.color")

local M = {}

local cache = {}
local current = nil
local base_background = "dark"

local function group_color(group, key)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  if ok and hl and hl[key] then
    return string.format("#%06x", hl[key])
  end
  return nil
end

local function extract(light, read)
  local function first(key, ...)
    if not read then
      return nil
    end
    for _, group in ipairs({ ... }) do
      local value = group_color(group, key)
      if value then
        return value
      end
    end
    return nil
  end

  local bg = first("bg", "Normal") or (light and "#ffffff" or "#000000")
  local fg = first("fg", "Normal") or (light and "#000000" or "#c0c0c0")
  local accent = first("fg", "Function", "Title", "Identifier") or fg
  local amber = first("fg", "Number", "Constant", "Boolean") or fg
  local green = first("fg", "String", "DiffAdd") or accent
  local violet = first("fg", "Keyword", "Statement", "Conditional") or accent
  local cyan = first("fg", "Type", "Special", "DiagnosticInfo") or accent
  local red = first("fg", "DiagnosticError", "ErrorMsg", "DiffDelete") or color.mix(fg, "#ff0000", 0.6)
  local muted = first("fg", "Comment", "NonText", "LineNr") or color.mix(fg, bg, 0.5)
  local border = first("fg", "WinSeparator", "FloatBorder", "LineNr") or color.mix(fg, bg, 0.7)
  local surface = first("bg", "CursorLine", "Pmenu", "ColorColumn") or color.mix(bg, fg, 0.08)

  return {
    light = light,
    bg = bg,
    fg = fg,
    surface = surface,
    selection = first("bg", "Visual") or color.mix(bg, accent, 0.25),
    search = first("bg", "Search", "IncSearch") or color.mix(bg, amber, 0.3),
    muted = muted,
    border = border,
    accent = accent,
    violet = violet,
    green = green,
    amber = amber,
    red = red,
    cyan = cyan,
    mini = { red, amber, green, cyan, accent, violet, fg, muted, surface, border },
    swatches = { bg, fg, accent, violet, green, amber },
  }
end

local function apply(name)
  vim.o.background = base_background
  local ok, err = pcall(vim.cmd.colorscheme, name)
  current = ok and name or nil
  return ok, err
end

function M.reset(background)
  cache = {}
  current = nil
  base_background = background
end

function M.get(entry)
  local cached = cache[entry.name]
  if cached ~= nil then
    return cached or nil
  end
  local ok, err = apply(entry.name)
  if not ok then
    vim.notify("csoul: " .. tostring(err), vim.log.levels.WARN)
  end
  local palette = ok and extract(entry.light, true) or false
  cache[entry.name] = palette
  return palette or nil
end

function M.show(entry)
  local palette = M.get(entry)
  if current ~= entry.name then
    apply(entry.name)
  end
  return palette
end

function M.live(light)
  return extract(light, true)
end

function M.restore(original)
  if original.colors_name then
    apply(original.colors_name)
  else
    vim.cmd("highlight clear")
    vim.g.colors_name = nil
  end
  vim.o.background = original.background
  current = nil
end

return M
