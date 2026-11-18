local color = require("csoul.color")

local M = {}

local cache = {}
local waiting = {}
local queue = {}
local pending = {}
local running = 0
local original = nil
local LIGHT_LUMINANCE = 0.179
local MAX_JOBS = 4
local ROOT = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local PROBE = table.concat({
  "lua for name in pairs(package.loaded) do if name:find('^csoul') then package.loaded[name] = nil end end",
  "table.insert(package.loaders or package.searchers, 1, function(name) local file = package.searchpath(name, vim.env.CSOUL_ROOT .. '/lua/?.lua') if file then return loadfile(file) end end)",
  "require('csoul.palette').probe()",
}, "; ")

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

local function extract(background_light, read)
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

  local measured = first("bg", "Normal")
  local light = background_light
  if measured then
    light = color.luminance(measured) > LIGHT_LUMINANCE
  end
  local bg = measured or (light and "#ffffff" or "#000000")
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

local function scheme_root(entry)
  return entry.path:match("^(.*)/colors/[^/]+$")
end

local function lazy_load(entry)
  if not entry.lazy or not package.loaded.lazy then
    return false
  end
  local plugin = require("lazy.core.config").plugins[entry.lazy]
  if not plugin or plugin._.loaded then
    return false
  end
  require("lazy").load({ plugins = { entry.lazy } })
  return true
end

local function set_scheme(entry)
  lazy_load(entry)
  if entry.package then
    pcall(vim.cmd.packadd, entry.package)
  end
  local root = scheme_root(entry)
  if root then
    vim.opt.runtimepath:prepend(root)
  end
  vim.o.background = original.background
  local ok, err = pcall(vim.cmd, { cmd = "colorscheme", args = { entry.name } })
  if not ok then
    vim.notify("csoul: " .. tostring(err), vim.log.levels.WARN)
  end
  return ok
end

local function read_result(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines[1] then
    return nil
  end
  local decoded, data = pcall(vim.json.decode, lines[1])
  if decoded and type(data) == "table" and data.light ~= nil then
    return data
  end
  return nil
end

local function finish(entry, result)
  running = running - 1
  pending[entry.name] = nil
  cache[entry.name] = result or false
  if result then
    entry.light = result.light
  end
  local callbacks = waiting[entry.name] or {}
  waiting[entry.name] = nil
  for _, callback in ipairs(callbacks) do
    callback(result)
  end
  M.pump()
end

local function run_job(entry)
  local path = vim.fn.tempname()
  vim.system({
    vim.v.progpath,
    "--headless",
    "-n",
    "-i",
    "NONE",
    "-c",
    PROBE,
  }, {
    env = {
      CSOUL_ROOT = ROOT,
      CSOUL_SCHEME = entry.name,
      CSOUL_OUT = path,
      CSOUL_BACKGROUND = original.background,
    },
    timeout = 30000,
  }, function()
    vim.schedule(function()
      local result = read_result(path)
      pcall(vim.fn.delete, path)
      finish(entry, result)
    end)
  end)
end

function M.pump()
  while running < MAX_JOBS and #queue > 0 do
    local entry = table.remove(queue, 1)
    running = running + 1
    run_job(entry)
  end
end

function M.reset(state)
  original = {
    colors_name = state.colors_name,
    background = state.background,
  }
end

function M.cached(entry)
  return cache[entry.name] or nil
end

function M.measure(entry, callback, urgent)
  local name = entry.name
  if cache[name] ~= nil then
    if callback then
      vim.schedule(function()
        callback(cache[name] or nil)
      end)
    end
    return
  end
  if callback then
    waiting[name] = waiting[name] or {}
    table.insert(waiting[name], callback)
  end
  if pending[name] then
    if urgent then
      for i, queued in ipairs(queue) do
        if queued.name == name then
          table.remove(queue, i)
          table.insert(queue, 1, queued)
          break
        end
      end
    end
    return
  end
  pending[name] = true
  if urgent then
    table.insert(queue, 1, entry)
  else
    queue[#queue + 1] = entry
  end
  M.pump()
end

function M.probe()
  local function run()
    local ok, err = pcall(function()
      local name = vim.env.CSOUL_SCHEME
      local entry
      for _, candidate in ipairs(require("csoul.discover").schemes()) do
        if candidate.name == name then
          entry = candidate
          break
        end
      end
      if not entry then
        error("colorscheme not found: " .. tostring(name))
      end
      M.reset({ colors_name = vim.g.colors_name, background = vim.env.CSOUL_BACKGROUND or vim.o.background })
      if not set_scheme(entry) then
        error("colorscheme failed: " .. entry.name)
      end
      local palette = M.live(vim.o.background == "light")
      vim.fn.writefile({ vim.json.encode(palette) }, vim.env.CSOUL_OUT)
    end)
    if not ok then
      vim.fn.writefile({ vim.json.encode({ error = tostring(err) }) }, vim.env.CSOUL_OUT)
    end
    vim.cmd("qa!")
  end
  if vim.v.vim_did_enter == 1 then
    run()
  else
    vim.api.nvim_create_autocmd("VimEnter", { once = true, nested = true, callback = run })
  end
end

function M.apply(entry)
  return set_scheme(entry)
end

function M.live(light)
  return extract(light, true)
end

return M
