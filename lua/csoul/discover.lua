local M = {}

local CORE_LIGHT = { morning = true, peachpuff = true, zellner = true, delek = true, shine = true }
local KNOWN_LIGHT = vim.tbl_extend("force", CORE_LIGHT, {
  ["kanagawa-lotus"] = true,
  ["catppuccin-latte"] = true,
  ["modus_operandi"] = true,
})

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

local function opt_package_of(path)
  return path:match("/pack/[^/]+/opt/([^/]+)/colors/")
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

local PACK_PATTERNS = {
  "pack/*/start/*/colors/*.vim",
  "pack/*/start/*/colors/*.lua",
  "pack/*/opt/*/colors/*.vim",
  "pack/*/opt/*/colors/*.lua",
}

local function runtime_scheme_files()
  local dirs, by_dir = {}, {}
  for _, path in ipairs(vim.api.nvim_get_runtime_file("colors/*", true)) do
    local ext = path:match("%.(%a+)$")
    if ext == "vim" or ext == "lua" then
      local dir = vim.fs.dirname(path)
      if not by_dir[dir] then
        by_dir[dir] = { vim = {}, lua = {} }
        dirs[#dirs + 1] = dir
      end
      table.insert(by_dir[dir][ext], path)
    end
  end
  local files = {}
  for _, dir in ipairs(dirs) do
    vim.list_extend(files, by_dir[dir].vim)
    vim.list_extend(files, by_dir[dir].lua)
  end
  return files
end

local function scheme_files()
  local files = runtime_scheme_files()
  for _, packpath in ipairs(vim.opt.packpath:get()) do
    for _, pattern in ipairs(PACK_PATTERNS) do
      vim.list_extend(files, vim.fn.globpath(packpath, pattern, false, true))
    end
  end
  return files
end

function M.schemes()
  local found, names = {}, {}
  for _, path in ipairs(scheme_files()) do
    local name = vim.fn.fnamemodify(path, ":t:r")
    if name ~= "" and name:lower() ~= "readme" and not found[name] then
      found[name] = path
      names[#names + 1] = name
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
      package = opt_package_of(path),
      origin = origin_of(source),
      light = is_light(name, path, source),
    }
  end
  return entries
end

return M
