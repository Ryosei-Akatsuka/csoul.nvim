local color = require("csoul.color")

local M = {}

local cache = {}
local original = nil

local function group_color(group, key)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  if ok and hl and hl[key] then
    return string.format("#%06x", hl[key])
  end
  return nil
end

local SYNTAX = {
  keyword = { "@keyword", "Keyword", "Statement" },
  ["function"] = { "@function", "Function" },
  type = { "@type", "Type" },
  string = { "@string", "String" },
  number = { "@number", "Number", "Constant" },
  operator = { "@operator", "Operator" },
  variable = { "@variable", "Identifier" },
  module = { "@module", "Include", "Special" },
  macro = { "@function.macro", "@macro", "Macro", "PreProc" },
  punct = { "@punctuation.delimiter", "@punctuation", "Delimiter" },
}

local function syntax_styles(fg)
  local styles = {}
  for role, groups in pairs(SYNTAX) do
    styles[role] = { fg = fg }
    for _, group in ipairs(groups) do
      local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
      if ok and hl and hl.fg then
        styles[role] = {
          fg = string.format("#%06x", hl.fg),
          bold = hl.bold or false,
          italic = hl.italic or false,
        }
        break
      end
    end
  end
  return styles
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
    syntax = syntax_styles(fg),
  }
end

local function set_scheme(name, silent)
  vim.o.background = original.background
  local ok, err = pcall(vim.cmd, { cmd = "colorscheme", args = { name }, mods = { noautocmd = silent } })
  if not ok then
    vim.notify("csoul: " .. tostring(err), vim.log.levels.WARN)
  end
  return ok
end

local function restore_highlights(saved)
  for name in pairs(vim.api.nvim_get_hl(0, {})) do
    if saved[name] == nil and not name:find("^Csoul") then
      vim.api.nvim_set_hl(0, name, {})
    end
  end
  for name, attrs in pairs(saved) do
    vim.api.nvim_set_hl(0, name, attrs)
  end
end

local function restore()
  vim.g.colors_name = original.colors_name
  if vim.o.background ~= original.background then
    vim.o.background = original.background
  end
  restore_highlights(original.highlights)
end

function M.reset(state)
  cache = {}
  original = {
    colors_name = state.colors_name,
    background = state.background,
    highlights = vim.api.nvim_get_hl(0, {}),
  }
end

function M.get(entry)
  local cached = cache[entry.name]
  if cached ~= nil then
    return cached or nil
  end
  local palette = set_scheme(entry.name, true) and extract(entry.light, true) or false
  restore()
  cache[entry.name] = palette
  return palette or nil
end

function M.apply(name)
  return set_scheme(name, false)
end

function M.live(light)
  return extract(light, true)
end

return M
