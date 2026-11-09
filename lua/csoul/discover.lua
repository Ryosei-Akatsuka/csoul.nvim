local M = {}

local CORE_LIGHT = { morning = true, peachpuff = true, zellner = true, delek = true, shine = true }
local KNOWN_LIGHT = vim.tbl_extend("force", CORE_LIGHT, { ["kanagawa-lotus"] = true })

local function source_of(path)
  if path:find("/nvim/runtime/colors/", 1, true) then
    return "nvim runtime"
  end
  local lazy = path:match("/lazy/([^/]+)/colors/")
  if lazy then
    return lazy
  end
  local pack = path:match("/pack/[^/]+/%a+/([^/]+)/colors/")
  if pack then
    return pack
  end
  local store = path:match("^/nix/store/[^/]+%-([^/]+)/colors/")
  if store then
    return (store:gsub("^vimplugin%-", ""):gsub("%-unstable.*$", ""):gsub("%-%d.*$", ""))
  end
  if path:find("/site/colors/", 1, true) then
    return "local colors"
  end
  return "colors directory"
end

local function origin_of(source)
  if source == "nvim runtime" then
    return "CORE"
  end
  if source == "local colors" then
    return "USER"
  end
  return "PLUGIN"
end

local function declares_light(path)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  local text = file:read(131072) or ""
  file:close()
  text = text:lower()
  return text:find("background%s*=+%s*[\"']?light") ~= nil
end

local function is_light(name, path, source)
  if source == "nvim runtime" then
    return CORE_LIGHT[name] == true
  end
  if KNOWN_LIGHT[name] then
    return true
  end
  return declares_light(path)
end

function M.schemes()
  local found, names = {}, {}
  for _, pattern in ipairs({ "colors/*.vim", "colors/*.lua" }) do
    for _, path in ipairs(vim.api.nvim_get_runtime_file(pattern, true)) do
      local name = vim.fn.fnamemodify(path, ":t:r")
      if name ~= "" and name:lower() ~= "readme" and not found[name] then
        found[name] = path
        names[#names + 1] = name
      end
    end
  end
  table.sort(names)

  local entries = {}
  for _, name in ipairs(names) do
    local path = found[name]
    local source = source_of(path)
    entries[#entries + 1] = {
      name = name,
      path = path,
      source = source,
      origin = origin_of(source),
      light = is_light(name, path, source),
    }
  end
  return entries
end

return M
