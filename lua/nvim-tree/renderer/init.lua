local log = require("nvim-tree.log")
local view = require("nvim-tree.view")
local events = require("nvim-tree.events")

local Class = require("nvim-tree.classic")
local Builder = require("nvim-tree.renderer.builder")

local SIGN_GROUP = "NvimTreeRendererSigns"

local namespace_highlights_id = vim.api.nvim_create_namespace("NvimTreeHighlights")
local namespace_extmarks_id = vim.api.nvim_create_namespace("NvimTreeExtmarks")
local namespace_virtual_lines_id = vim.api.nvim_create_namespace("NvimTreeVirtualLines")

---@alias HighlightRangeArgs { higroup:string, start:integer[], finish:integer[] } named arguments for vim.hl.range

---@class (exact) Renderer: nvim_tree.Class
---@field explorer Explorer
local Renderer = Class:extend()

---@class Renderer
---@overload fun(args: RendererArgs): Renderer

---@class (exact) RendererArgs
---@field explorer Explorer

---@protected
---@param args RendererArgs
function Renderer:new(args)
  self.explorer = args.explorer
end

---@private
---@param bufnr number
---@param lines string[]
---@param hl_range_args HighlightRangeArgs[]
---@param signs string[]
---@param extmarks table[] extra marks for right icon placement
---@param virtual_lines table[] virtual lines for hidden count display
function Renderer:_draw(bufnr, lines, hl_range_args, signs, extmarks, virtual_lines)
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  self:render_hl(bufnr, hl_range_args)

  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

  vim.fn.sign_unplace(SIGN_GROUP)
  for i, sign_name in pairs(signs) do
    vim.fn.sign_place(0, SIGN_GROUP, sign_name, bufnr, { lnum = i + 1 })
  end

  vim.api.nvim_buf_clear_namespace(bufnr, namespace_extmarks_id, 0, -1)
  for i, extname in pairs(extmarks) do
    for _, mark in ipairs(extname) do
      vim.api.nvim_buf_set_extmark(bufnr, namespace_extmarks_id, i, -1, {
        virt_text     = { { mark.str, mark.hl } },
        virt_text_pos = "right_align",
        hl_mode       = "combine",
      })
    end
  end

  vim.api.nvim_buf_clear_namespace(bufnr, namespace_virtual_lines_id, 0, -1)
  for line_nr, vlines in pairs(virtual_lines) do
    vim.api.nvim_buf_set_extmark(bufnr, namespace_virtual_lines_id, line_nr, 0, {
      virt_lines         = vlines,
      virt_lines_above   = false,
      virt_lines_leftcol = true,
    })
  end
end

---@private
---@param bufnr integer
---@param hl_range_args HighlightRangeArgs[]
function Renderer:render_hl(bufnr, hl_range_args)
  if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, namespace_highlights_id, 0, -1)

  -- Set the extmarks directly, as vim.hl.range would, for every highlight of every line.
  -- vim.hl.range is generic: per call it switches buffer context, calls col('$') twice and getregionpos.
  -- Our ranges are always single line byte ranges, so none of that is needed.
  -- same priority as vim.hl.range; nil (extmark default) matches the nvim_buf_add_highlight previously used for nvim < 0.11
  local priority = vim.hl and vim.hl.priorities and vim.hl.priorities.user or nil
  local set_extmark = vim.api.nvim_buf_set_extmark
  local opts = { strict = false, priority = priority }
  for _, args in ipairs(hl_range_args) do
    local row, end_col = args.start[1], args.finish[2]
    opts.hl_group = args.higroup
    if end_col == -1 then
      -- to end of line, as vim.hl.range does for -1
      opts.end_row, opts.end_col = row + 1, 0
    else
      opts.end_row, opts.end_col = row, end_col
    end
    set_extmark(bufnr, namespace_highlights_id, row, args.start[2], opts)
  end
end

function Renderer:draw()
  local bufnr = view.get_bufnr()
  if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  local profile = log.profile_start("draw")

  local cursor = vim.api.nvim_win_get_cursor(view.get_winnr() or 0)

  local builder = Builder(self.explorer):build()

  self:_draw(bufnr, builder.lines, builder.hl_range_args, builder.signs, builder.extmarks, builder.virtual_lines)

  if cursor and #builder.lines >= cursor[1] then
    vim.api.nvim_win_set_cursor(view.get_winnr() or 0, cursor)
  end

  view.grow_from_content()

  log.profile_end(profile)

  events._dispatch_on_tree_rendered(bufnr, view.get_winnr())
end

return Renderer
