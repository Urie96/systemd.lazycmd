local M = {}
local config = require 'systemd.config'

local function line(parts) return deck.style.line(parts) end
local function text(lines) return deck.style.text(lines) end
local function span(value, color)
  local s = deck.style.span(tostring(value or ''))
  if color and color ~= '' then s = s:fg(color) end
  return s
end

-- 辅助函数：获取当前选中的单元信息
local function get_selected_unit()
  local entry = deck.api.get_hovered()
  if not entry or entry.kind ~= 'unit' or not entry.unit then return nil end
  return entry
end

-- 辅助函数：获取 unit 的活动状态和启用状态
local function get_unit_status(unit_info, callback)
  deck.system.exec(
    { config.get().command, '--' .. unit_info.scope, 'is-enabled', unit_info.unit },
    function(enabled_output)
      callback {
        is_enabled = enabled_output.code == 0,
      }
    end
  )
end

-- 控制类动作：非交互执行，系统作用域通过 deck.system.exec 的 sudo 字段升级为 sudo
local CONTROL_ACTIONS = {
  start = true,
  stop = true,
  restart = true,
  enable = true,
  disable = true,
  reload = true,
}

local function do_unit_action(action_name)
  local unit_info = get_selected_unit()
  if not unit_info then
    deck.notify 'Please select a unit first'
    return
  end

  local needs_sudo = unit_info.scope == 'system'

  -- 交互式动作（follow/edit/show/cat 需要终端输出）：保持 interactive，
  -- 系统作用域仍用 sudo（走 tty 提示符）
  if not CONTROL_ACTIONS[action_name] then
    local cmd = {}
    if needs_sudo then cmd = { 'sudo' } end

    if action_name == 'follow' then
      cmd = deck.tbl_extend(
        'force',
        cmd,
        { config.get().journal_command, '--' .. unit_info.scope, '-xef', '--unit=' .. unit_info.unit }
      )
    else
      cmd = deck.tbl_extend('force', cmd, { config.get().command, '--' .. unit_info.scope, action_name, unit_info.unit })
    end

    deck.interactive(cmd, { wait_confirm = function(exit_code) return exit_code ~= 0 end }, function(exit_code)
      if exit_code == 0 then
        deck.notify(action_name .. ' for ' .. unit_info.unit .. ' successfully')
        deck.cmd 'reload'
      else
        deck.notify(action_name .. ' for ' .. unit_info.unit .. ' failed')
      end
    end)
    return
  end

  -- 控制类动作：非交互执行；系统作用域通过 sudo 字段（先探测免密，需要时弹输入框输入密码）
  deck.system.exec(
    { config.get().command, '--' .. unit_info.scope, action_name, unit_info.unit },
    { sudo = needs_sudo },
    function(out)
      if out.code == 0 then
        deck.notify(action_name .. ' for ' .. unit_info.unit .. ' successfully')
      else
        local detail = (out.stderr or ''):gsub('%s+$', '')
        if detail == '' then detail = (out.stdout or ''):gsub('%s+$', '') end
        deck.notify(action_name .. ' for ' .. unit_info.unit .. ' failed' .. (detail ~= '' and (': ' .. detail) or ''))
      end
      deck.cmd 'reload'
    end
  )
end

function M.restart() do_unit_action 'restart' end

function M.start() do_unit_action 'start' end

function M.stop() do_unit_action 'stop' end

function M.enable() do_unit_action 'enable' end
function M.disable() do_unit_action 'disable' end
function M.reload() do_unit_action 'reload' end

function M.follow() do_unit_action 'follow' end

function M.edit() do_unit_action 'edit' end

function M.show() do_unit_action 'show' end

function M.cat() do_unit_action 'cat' end

function M.select_action()
  local unit_info = get_selected_unit()
  if not unit_info then
    deck.notify 'Please select a unit first'
    return
  end

  get_unit_status(unit_info, function(status)
    local options = {}

    table.insert(options, {
      value = 'follow',
      display = deck.style.line { ('📋 Follow'):fg 'cyan' },
    })

    if unit_info.active == 'active' then
      table.insert(options, {
        value = 'restart',
        display = deck.style.line { ('🔄 Restart'):fg 'red' },
      })
      table.insert(options, {
        value = 'stop',
        display = deck.style.line { ('⏹️ Stop'):fg 'red' },
      })
    else
      table.insert(options, {
        value = 'start',
        display = deck.style.line { ('▶️ Start'):fg 'green' },
      })
    end

    if status.is_enabled then
      table.insert(options, {
        value = 'disable',
        display = deck.style.line { ('🔓 Disable'):fg 'red' },
      })
    else
      table.insert(options, {
        value = 'enable',
        display = deck.style.line { ('🔒 Enable'):fg 'green' },
      })
    end

    -- reload 选项
    table.insert(options, {
      value = 'reload',
      display = deck.style.line { ('🔃 Reload'):fg 'blue' },
    })

    -- edit/show/cat 选项
    table.insert(options, {
      value = 'edit',
      display = deck.style.line { ('✏️ Edit'):fg 'yellow' },
    })
    table.insert(options, {
      value = 'show',
      display = deck.style.line { ('📄 Show'):fg 'yellow' },
    })
    table.insert(options, {
      value = 'cat',
      display = deck.style.line { ('📜 Cat'):fg 'yellow' },
    })

    deck.select({
      prompt = 'Select an action',
      options = options,
    }, function(choice)
      if choice then require('systemd.action')[choice]() end
    end)
  end)
end

function M.scope_preview(entry)
  return text {
    line { span('Scope', 'cyan'), span(': ' .. tostring(entry.scope or ''), 'white') },
    line { '' },
    line { span('Enter to browse unit types in this scope.', 'darkgray') },
  }
end

function M.type_preview(entry)
  return text {
    line { span('Type', 'cyan'), span(': ' .. tostring(entry.unit_type or ''), 'white') },
    line { span('Scope', 'cyan'), span(': ' .. tostring(entry.scope or ''), 'white') },
    line { '' },
    line { span('Enter to list matching units.', 'darkgray') },
  }
end

function M.unit_preview(entry, cb)
  deck.system({ config.get().command, '--' .. entry.scope, 'status', '--no-pager', '--', entry.unit }, {
    env = {
      SYSTEMD_COLORS = '1',
    },
  }, function(out) cb((out.stdout .. out.stderr):ansi()) end)
end

function M.info_preview(entry)
  return text {
    line { span(entry.title or 'systemd', 'cyan') },
    line { span(entry.message or '', entry.color or 'darkgray') },
    line { span(entry.detail or '', 'darkgray') },
  }
end

return M
