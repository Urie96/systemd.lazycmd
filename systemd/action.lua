local M = {}

-- 辅助函数：获取当前选中的单元信息
local function get_selected_unit()
  local entry = lc.api.page_get_hovered()
  if not entry or not entry.unit then return nil end
  return entry
end

-- 辅助函数：获取 unit 的活动状态和启用状态
local function get_unit_status(unit_info, callback)
  lc.system.exec(
    { 'systemctl', '--' .. unit_info.scope, 'is-enabled', unit_info.unit },
    function(enabled_output)
      callback {
        is_enabled = enabled_output.code == 0,
      }
    end
  )
end

local function do_unit_action(action_name)
  local unit_info = get_selected_unit()
  if not unit_info then
    lc.notify 'Please select a unit first'
    return
  end

  local cmd = {}
  if unit_info.scope == 'system' then cmd = { 'sudo' } end

  if action_name == 'follow' then
    cmd = lc.tbl_extend(cmd, { 'journalctl', '--' .. unit_info.scope, '-xef', '--unit=' .. unit_info.unit })
  else
    cmd = lc.tbl_extend(cmd, { 'systemctl', '--' .. unit_info.scope, action_name, unit_info.unit })
  end

  lc.interactive(cmd, { wait_confirm = function(exit_code) return exit_code ~= 0 end }, function(exit_code)
    if exit_code == 0 then
      lc.notify(action_name .. ' for ' .. unit_info.unit .. ' successfully')
      lc.cmd 'reload'
    else
      lc.notify(action_name .. ' for ' .. unit_info.unit .. ' failed')
    end
  end)
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
    lc.notify 'Please select a unit first'
    return
  end

  get_unit_status(unit_info, function(status)
    local options = {}

    table.insert(options, {
      value = 'follow',
      display = lc.style.line { ('📋 Follow'):fg 'cyan' },
    })

    if unit_info.active == 'active' then
      table.insert(options, {
        value = 'restart',
        display = lc.style.line { ('🔄 Restart'):fg 'red' },
      })
      table.insert(options, {
        value = 'stop',
        display = lc.style.line { ('⏹️ Stop'):fg 'red' },
      })
    else
      table.insert(options, {
        value = 'start',
        display = lc.style.line { ('▶️ Start'):fg 'green' },
      })
    end

    if status.is_enabled then
      table.insert(options, {
        value = 'disable',
        display = lc.style.line { ('🔓 Disable'):fg 'red' },
      })
    else
      table.insert(options, {
        value = 'enable',
        display = lc.style.line { ('🔒 Enable'):fg 'green' },
      })
    end

    -- reload 选项
    table.insert(options, {
      value = 'reload',
      display = lc.style.line { ('🔃 Reload'):fg 'blue' },
    })

    -- edit/show/cat 选项
    table.insert(options, {
      value = 'edit',
      display = lc.style.line { ('✏️ Edit'):fg 'yellow' },
    })
    table.insert(options, {
      value = 'show',
      display = lc.style.line { ('📄 Show'):fg 'yellow' },
    })
    table.insert(options, {
      value = 'cat',
      display = lc.style.line { ('📜 Cat'):fg 'yellow' },
    })

    lc.select({
      prompt = 'Select an action',
      options = options,
    }, function(choice)
      if choice then require('systemd.action')[choice]() end
    end)
  end)
end

return M
