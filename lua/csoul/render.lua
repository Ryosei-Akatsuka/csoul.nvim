local color = require("csoul.color")

local M = {}

local W, H = 104, 28
local LEFT_X, LEFT_W = 3, 40
local RIGHT_X, RIGHT_W = 47, 54
local RIGHT_END = RIGHT_X + RIGHT_W - 1
local HEADER_Y, SEARCH_Y, HEADS_Y = 2, 4, 6
local LIST_Y, LIST_ROWS = 8, 15
local FOOTER_Y = 26
local GLYPH = "󱓻"

M.W, M.H = W, H
M.LEFT_X, M.SEARCH_Y, M.LIST_Y, M.LIST_ROWS = LEFT_X, SEARCH_Y, LIST_Y, LIST_ROWS

local function width(text)
  local plain = text:gsub("[\128-\191]", "")
  return #plain
end

local function fit(text, limit)
  if width(text) <= limit then
    return text
  end
  return text:sub(1, math.max(0, limit - 2)) .. ".."
end

local function filter_chips(counts)
  return {
    { key = "all", text = " ALL " .. counts.all .. " " },
    { key = "dark", text = " DARK " .. counts.dark .. " " },
    { key = "light", text = " LIGHT " .. counts.light .. " " },
  }
end

local function chip_start(counts)
  local total = 2
  for _, chip in ipairs(filter_chips(counts)) do
    total = total + width(chip.text)
  end
  return RIGHT_END - total + 1
end

function M.field(counts)
  local x = LEFT_X + 3
  return { x = x, y = SEARCH_Y, width = (chip_start(counts) - 2) - x + 1 }
end

local Canvas = {}
Canvas.__index = Canvas

local function new_canvas(fg, bg)
  local cells = {}
  for y = 1, H do
    cells[y] = {}
    for x = 1, W do
      cells[y][x] = { ch = " ", fg = fg, bg = bg, bold = false, italic = false }
    end
  end
  return setmetatable({ cells = cells }, Canvas)
end

function Canvas:put(x, y, text, style)
  style = style or {}
  if y < 0 or y >= H then
    return
  end
  local i = 0
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local xx = x + i
    if xx >= 0 and xx < W then
      local cell = self.cells[y + 1][xx + 1]
      cell.ch = ch
      if style.fg then
        cell.fg = style.fg
      end
      if style.bg then
        cell.bg = style.bg
      end
      cell.bold = style.bold or false
      cell.italic = style.italic or false
    end
    i = i + 1
  end
end

function Canvas:fill(x, y, w, h, bg)
  for yy = y, y + h - 1 do
    if yy >= 0 and yy < H then
      for xx = x, x + w - 1 do
        if xx >= 0 and xx < W then
          local cell = self.cells[yy + 1][xx + 1]
          cell.ch = " "
          cell.bg = bg
        end
      end
    end
  end
end

function Canvas:flatten()
  local lines, runs = {}, {}
  for y = 1, H do
    local parts, byte, run = {}, 0, nil
    for x = 1, W do
      local cell = self.cells[y][x]
      local key = table.concat({ cell.fg, cell.bg, cell.bold and "b" or "", cell.italic and "i" or "" }, "|")
      if not run or run.key ~= key then
        if run then
          run.stop = byte
          runs[#runs + 1] = run
        end
        run = {
          key = key,
          row = y - 1,
          start = byte,
          style = { fg = cell.fg, bg = cell.bg, bold = cell.bold, italic = cell.italic },
        }
      end
      parts[#parts + 1] = cell.ch
      byte = byte + #cell.ch
    end
    run.stop = byte
    runs[#runs + 1] = run
    lines[y] = table.concat(parts)
  end
  return lines, runs
end

local function hint(c, x, y, key, label, p)
  c:put(x, y, key, { fg = p.fg })
  c:put(x + #key + 1, y, label, { fg = color.mix(p.fg, p.bg, 0.54) })
  return #key + 1 + #label
end

local function draw_header(c, p, view)
  local rest
  if view.detected > 0 then
    rest = string.format("%d detected · nvim %s", view.detected, view.version)
  else
    rest = "no colorschemes found"
  end
  c:put(RIGHT_END - width(rest) + 1, HEADER_Y, rest, { fg = color.mix(p.fg, p.bg, 0.52) })
end

local function draw_search(c, p, view)
  local chips = filter_chips(view.counts)
  local x0 = chip_start(view.counts)
  local field_bg = color.mix(p.bg, p.surface, 0.38)
  c:fill(LEFT_X, SEARCH_Y, x0 - 2 - LEFT_X + 1, 1, field_bg)
  c:put(LEFT_X + 1, SEARCH_Y, "/", { fg = p.accent, bg = field_bg })

  local x = x0
  for _, chip in ipairs(chips) do
    local active = chip.key == view.filter
    local bg = active and p.accent or color.mix(p.bg, p.surface, 0.28)
    local fg = active and color.ink_on(p.accent) or color.mix(p.fg, p.bg, 0.48)
    c:put(x, SEARCH_Y, chip.text, { fg = fg, bg = bg, bold = active })
    x = x + width(chip.text) + 1
  end
end

local function draw_headers(c, p, view)
  c:put(LEFT_X, HEADS_Y, "Schemes", { fg = color.mix(p.fg, p.bg, 0.46) })
  c:put(LEFT_X + 9, HEADS_Y, string.format("%d / %d", view.shown, view.total), { fg = color.mix(p.fg, p.bg, 0.68) })
  c:put(RIGHT_X, HEADS_Y, "Preview", { fg = color.mix(p.fg, p.bg, 0.46) })
end

local function draw_list(c, p, view)
  if #view.rows == 0 then
    c:put(LEFT_X, LIST_Y, "No colorscheme matches.", { fg = color.mix(p.fg, p.bg, 0.52) })
    return
  end

  local muted = {}
  for j = 1, 10 do
    muted[j] = p.muted
  end

  for i, row in ipairs(view.rows) do
    local y = LIST_Y + i - 1
    local selected = row.index == view.selected

    if selected then
      c:fill(LEFT_X, y, LEFT_W, 1, color.mix(p.bg, p.accent, 0.10))
      c:put(LEFT_X, y, " ", { bg = p.accent })
    end

    c:put(LEFT_X + 2, y, string.format("%02d", row.index), {
      fg = selected and p.accent or color.mix(p.fg, p.bg, 0.65),
      bold = selected,
    })
    c:put(LEFT_X + 5, y, fit(row.entry.name, 16), {
      fg = selected and color.mix(p.fg, "#ffffff", 0.20) or color.mix(p.fg, p.bg, 0.05),
      bold = selected,
    })

    for j, colour in ipairs(row.palette and row.palette.mini or muted) do
      c:put(LEFT_X + 21 + j, y, GLYPH, { fg = colour })
    end

    local tag, tag_fg
    if selected then
      tag, tag_fg = "current", p.green
    elseif row.entry.light then
      tag, tag_fg = "light", p.amber
    else
      tag, tag_fg = "dark", color.mix(p.fg, p.bg, 0.52)
    end
    c:put(LEFT_X + LEFT_W - #tag, y, tag, { fg = tag_fg, bold = selected })
  end
end

local function draw_preview(c, p, entry)
  local section = color.mix(p.fg, p.bg, 0.46)

  c:put(RIGHT_X + 1, LIST_Y, fit(entry.name, RIGHT_W - 1), { fg = p.fg, bold = true })

  local ratio = color.contrast(p.fg, p.bg)
  local grade = ratio >= 7.0 and "AAA" or ratio >= 4.5 and "AA" or "A"
  local kind = entry.light and "LIGHT" or "DARK"
  local meta = table.concat({ fit(entry.source, 24), kind, entry.origin, string.format("%s %.1f", grade, ratio) }, "  ")
  c:put(RIGHT_X + 1, LIST_Y + 1, meta, { fg = color.mix(p.fg, p.bg, 0.55) })

  local palette_y = LIST_Y + 3
  for i, colour in ipairs(p.swatches) do
    local x = RIGHT_X + 1 + (i - 1) * 9
    c:fill(x, palette_y, 8, 1, colour)
    c:put(x, palette_y, " " .. colour, { fg = color.ink_on(colour) })
  end

  local label_y = LIST_Y + 6
  c:put(RIGHT_X + 1, label_y, "Syntax", { fg = section })
  c:put(RIGHT_END - 8 + 1, label_y, "init.lua", { fg = color.mix(p.fg, p.bg, 0.70) })

  local panel_bg = color.mix(p.bg, "#000000", 0.30)
  local panel_y = LIST_Y + 7
  local punct = color.mix(p.fg, panel_bg, 0.25)
  c:fill(RIGHT_X, panel_y, RIGHT_W, 5, panel_bg)
  c:fill(RIGHT_X, panel_y + 3, RIGHT_W, 1, color.mix(panel_bg, p.accent, 0.065))

  for i = 0, 4 do
    c:put(RIGHT_X + 2, panel_y + i, string.format("%2d", i + 1), {
      fg = i == 3 and p.amber or color.mix(p.fg, panel_bg, 0.62),
      bold = i == 3,
    })
  end

  local code = {
    { { "-- ~/.config/nvim/init.lua", p.muted, true } },
    { { "local", p.violet, true }, { " M", p.fg, false }, { " = {}", punct, false } },
    {
      { "function", p.violet, true },
      { " M.setup", p.accent, false },
      { "(", punct, false },
      { "opts", p.amber, false },
      { ")", punct, false },
    },
    {
      { "  vim", p.cyan, false },
      { ".cmd.colorscheme", p.accent, false },
      { "(", punct, false },
      { '"' .. entry.name .. '"', p.green, false },
      { ")", punct, false },
    },
    { { "end", p.violet, true } },
  }
  for i, segments in ipairs(code) do
    local x = RIGHT_X + 5
    for _, segment in ipairs(segments) do
      c:put(x, panel_y + i - 1, segment[1], { fg = segment[2], italic = segment[3] })
      x = x + width(segment[1])
    end
  end

  local chips_y = LIST_Y + 13
  c:put(RIGHT_X + 1, chips_y, "UI", { fg = section })
  local x = RIGHT_X + 12
  local error_bg = color.mix(p.surface, p.bg, 0.16)
  local ui_chips = {
    { "Normal", p.bg, p.fg },
    { "Visual", p.selection, p.fg },
    { "Search", p.search, p.fg },
    { "Error", error_bg, p.red },
    { "Hint", error_bg, p.cyan },
  }
  for _, chip in ipairs(ui_chips) do
    local text = " " .. chip[1] .. " "
    c:put(x, chips_y, text, { fg = chip[3], bg = chip[2] })
    x = x + width(text) + 1
  end
end

local function draw_footer(c, p)
  local x = LEFT_X
  for _, pair in ipairs({
    { "j/k", "move" },
    { "/", "search" },
    { "tab", "filter" },
    { "enter", "apply" },
    { "esc", "close" },
  }) do
    x = x + hint(c, x, FOOTER_Y, pair[1], pair[2], p) + 3
  end
end

function M.build(view)
  local p = view.palette
  local c = new_canvas(p.fg, p.bg)
  draw_header(c, p, view)
  draw_search(c, p, view)
  draw_headers(c, p, view)
  draw_list(c, p, view)
  if view.entry then
    draw_preview(c, p, view.entry)
  end
  draw_footer(c, p)
  return c:flatten()
end

return M
