local color = require("csoul.color")
local discover = require("csoul.discover")
local palette = require("csoul.palette")
local render = require("csoul.render")

local M = {}

local ns = vim.api.nvim_create_namespace("csoul")
local FILTERS = { "all", "dark", "light" }
local cell_groups = {}
local cell_count = 0
local state = nil

local function notify(message, level)
  vim.notify("csoul: " .. message, level or vim.log.levels.INFO)
end

local function version()
  local v = vim.version()
  return string.format("%d.%d.%d", v.major, v.minor, v.patch)
end

local function group_for(style, defined)
  local key = table.concat({ style.fg, style.bg, style.bold and "b" or "", style.italic and "i" or "" }, "|")
  local name = cell_groups[key]
  if not name then
    cell_count = cell_count + 1
    name = "CsoulCell" .. cell_count
    cell_groups[key] = name
  end
  if not defined[name] then
    defined[name] = true
    vim.api.nvim_set_hl(0, name, {
      fg = style.fg,
      bg = style.bg,
      bold = style.bold,
      italic = style.italic,
    })
  end
  return name
end

local function paint(buf, lines, runs)
  local defined = {}
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, run in ipairs(runs) do
    if run.stop > run.start then
      vim.api.nvim_buf_set_extmark(buf, ns, run.row, run.start, {
        end_row = run.row,
        end_col = run.stop,
        hl_group = group_for(run.style, defined),
      })
    end
  end
end

local function selected_entry()
  return state.filtered[state.selected]
end

local function scroll()
  if state.selected == 0 then
    state.top = 0
  elseif state.selected <= state.top then
    state.top = state.selected - 1
  elseif state.selected > state.top + render.LIST_ROWS then
    state.top = state.selected - render.LIST_ROWS
  end
end

local function refilter(keep)
  local needle = state.query:lower()
  local filtered = {}
  for _, entry in ipairs(state.entries) do
    local kind_ok = state.filter == "all" or (state.filter == "light") == entry.light
    if kind_ok and (needle == "" or entry.name:lower():find(needle, 1, true)) then
      filtered[#filtered + 1] = entry
    end
  end
  state.filtered = filtered
  state.selected = #filtered > 0 and 1 or 0
  for i, entry in ipairs(filtered) do
    if entry.name == keep then
      state.selected = i
      break
    end
  end
  state.top = 0
  scroll()
end

local function refresh_input()
  local buf = state.input_buf
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if state.query == "" then
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
      virt_text = { { "Search schemes...", "CsoulPlaceholder" } },
      virt_text_pos = "overlay",
    })
  end
end

local function refresh()
  local entry = selected_entry()
  local rows = {}
  for i = state.top + 1, math.min(#state.filtered, state.top + render.LIST_ROWS) do
    local item = state.filtered[i]
    rows[#rows + 1] = { index = i, entry = item, palette = palette.get(item) }
  end

  local light = vim.o.background == "light"
  local p = entry and palette.show(entry)
  if not p then
    p = palette.live(light)
  end

  local field_bg = color.mix(p.bg, p.surface, 0.38)
  vim.api.nvim_set_hl(0, "CsoulBase", { fg = p.fg, bg = p.bg })
  vim.api.nvim_set_hl(0, "CsoulField", { fg = p.fg, bg = field_bg })
  vim.api.nvim_set_hl(0, "CsoulPlaceholder", { fg = color.mix(p.fg, field_bg, 0.52), bg = field_bg })

  local lines, runs = render.build({
    palette = p,
    entry = entry,
    rows = rows,
    selected = state.selected,
    shown = #state.filtered,
    total = #state.entries,
    counts = state.counts,
    filter = state.filter,
    detected = #state.entries,
    version = version(),
  })
  paint(state.list_buf, lines, runs)
  refresh_input()

  if state.selected > 0 and vim.api.nvim_win_is_valid(state.list_win) then
    local row = render.LIST_Y + state.selected - state.top
    pcall(vim.api.nvim_win_set_cursor, state.list_win, { row, 0 })
  end
end

local function move(delta)
  if #state.filtered == 0 then
    return
  end
  state.selected = math.max(1, math.min(#state.filtered, state.selected + delta))
  scroll()
  refresh()
end

local function cycle(delta)
  local index = 1
  for i, name in ipairs(FILTERS) do
    if name == state.filter then
      index = i
    end
  end
  state.filter = FILTERS[(index - 1 + delta) % #FILTERS + 1]
  local entry = selected_entry()
  refilter(entry and entry.name)
  refresh()
end

local function focus_input()
  if state and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_set_current_win(state.input_win)
    vim.cmd("startinsert!")
  end
end

local function focus_list()
  if state and vim.api.nvim_win_is_valid(state.list_win) then
    vim.cmd("stopinsert")
    vim.api.nvim_set_current_win(state.list_win)
  end
end

local function close(restore)
  local s = state
  if not s then
    return
  end
  state = nil
  pcall(vim.api.nvim_del_augroup_by_id, s.augroup)
  for _, win in ipairs({ s.input_win, s.list_win }) do
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  if restore then
    palette.restore(s.original)
  end
  if vim.api.nvim_win_is_valid(s.prev_win) then
    pcall(vim.api.nvim_set_current_win, s.prev_win)
  end
end

local function accept()
  close(false)
end

local function cancel()
  close(true)
end

local function map(buf, mode, lhs, fn)
  vim.keymap.set(mode, lhs, fn, { buffer = buf, nowait = true, silent = true })
end

local function create_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  return buf
end

local function float_config(row, col, width, height, zindex)
  return {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "none",
    zindex = zindex,
  }
end

local function map_keys()
  local list, input = state.list_buf, state.input_buf

  map(list, "n", "j", function() move(1) end)
  map(list, "n", "<Down>", function() move(1) end)
  map(list, "n", "k", function() move(-1) end)
  map(list, "n", "<Up>", function() move(-1) end)
  map(list, "n", "/", focus_input)
  map(list, "n", "<Tab>", function() cycle(1) end)
  map(list, "n", "<S-Tab>", function() cycle(-1) end)
  map(list, "n", "<CR>", accept)
  map(list, "n", "q", cancel)
  map(list, "n", "<Esc>", cancel)

  map(input, "i", "<Esc>", focus_list)
  map(input, "i", "<CR>", focus_list)
  map(input, "i", "<Down>", function() move(1) end)
  map(input, "i", "<C-n>", function() move(1) end)
  map(input, "i", "<Up>", function() move(-1) end)
  map(input, "i", "<C-p>", function() move(-1) end)
  map(input, "i", "<Tab>", function() cycle(1) end)
end

local function watch_windows()
  local augroup = vim.api.nvim_create_augroup("csoul", { clear = true })
  state.augroup = augroup

  for _, win in ipairs({ state.list_win, state.input_win }) do
    vim.api.nvim_create_autocmd("WinClosed", {
      group = augroup,
      pattern = tostring(win),
      once = true,
      callback = function()
        vim.schedule(function()
          close(true)
        end)
      end,
    })
  end

  vim.api.nvim_create_autocmd("TextChangedI", {
    group = augroup,
    buffer = state.input_buf,
    callback = function()
      if not state then
        return
      end
      local query = vim.api.nvim_buf_get_lines(state.input_buf, 0, 1, false)[1] or ""
      if query ~= state.query then
        state.query = query
        local entry = selected_entry()
        refilter(entry and entry.name)
        refresh()
      end
    end,
  })
end

function M.open()
  if state then
    focus_list()
    return
  end

  if not vim.o.termguicolors then
    notify("requires 'termguicolors'", vim.log.levels.WARN)
    return
  end

  local available_rows = vim.o.lines - vim.o.cmdheight
  if vim.o.columns < render.W + 2 or available_rows < render.H + 2 then
    notify(string.format("needs at least %dx%d cells", render.W + 2, render.H + 2), vim.log.levels.WARN)
    return
  end

  local entries = discover.schemes()
  if #entries == 0 then
    notify("no colorschemes found in runtimepath", vim.log.levels.WARN)
    return
  end

  local light = 0
  for _, entry in ipairs(entries) do
    if entry.light then
      light = light + 1
    end
  end

  local original = { colors_name = vim.g.colors_name, background = vim.o.background }
  palette.reset(original.background)
  local prev_win = vim.api.nvim_get_current_win()

  state = {
    entries = entries,
    counts = { all = #entries, dark = #entries - light, light = light },
    query = "",
    filter = "all",
    filtered = {},
    selected = 0,
    top = 0,
    original = original,
    prev_win = prev_win,
  }

  local row = math.floor((available_rows - render.H) / 2)
  local col = math.floor((vim.o.columns - render.W) / 2)

  state.list_buf = create_buffer()
  state.list_win = vim.api.nvim_open_win(state.list_buf, true, float_config(row, col, render.W, render.H, 50))
  vim.wo[state.list_win].winhighlight = "Normal:CsoulBase,EndOfBuffer:CsoulBase"
  vim.wo[state.list_win].wrap = false
  vim.wo[state.list_win].cursorline = false
  vim.wo[state.list_win].signcolumn = "no"

  local field = render.field(state.counts)
  state.input_buf = create_buffer()
  state.input_win = vim.api.nvim_open_win(
    state.input_buf,
    false,
    float_config(row + field.y, col + field.x, field.width, 1, 51)
  )
  vim.wo[state.input_win].winhighlight = "Normal:CsoulField,EndOfBuffer:CsoulField"
  vim.wo[state.input_win].wrap = false

  map_keys()
  watch_windows()

  refilter(original.colors_name)
  refresh()
end

return M
