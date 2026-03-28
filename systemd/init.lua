-- systemd.lazycmd - Systemd service manager

local M = {}

-- systemd 单元类型列表（带图标）
local unit_types = {
  { name = 'service', icon = '⚙️' },
  { name = 'mount', icon = '💾' },
  { name = 'swap', icon = '🔄' },
  { name = 'socket', icon = '🔌' },
  { name = 'target', icon = '🎯' },
  { name = 'device', icon = '💻' },
  { name = 'automount', icon = '📂' },
  { name = 'timer', icon = '⏰' },
  { name = 'path', icon = '📁' },
  { name = 'slice', icon = '📊' },
  { name = 'scope', icon = '📦' },
}

function M.setup()
  lc.keymap.set('main', '<enter>', function()
    local path = lc.api.get_current_path()
    if #path < 3 then
      lc.cmd 'enter'
    else
      require('systemd.action').select_action()
    end
  end)
end

-- 第1级：显示 system 和 user 两个选项
local function list_level_1(cb)
  local entries = {
    {
      key = 'system',
      display = ('🖥️ system'):fg 'cyan',
      scope = 'system',
    },
    {
      key = 'user',
      display = ('👤 user'):fg 'cyan',
      scope = 'user',
    },
  }
  cb(entries)
end

-- 第2级：显示所有单元类型
local function list_level_2(path, cb)
  local entries = {}
  for _, unit_type in ipairs(unit_types) do
    table.insert(entries, {
      key = unit_type.name,
      display = lc.style.line({ (unit_type.icon .. ' ' .. unit_type.name):fg 'yellow' }),
      unit_type = unit_type.name,
      scope = path[2],
    })
  end
  cb(entries)
end

-- 第3级：显示指定类型和作用域的所有单元
local function list_level_3(path, cb)
  local scope = path[2] -- system 或 user
  local unit_type = path[3] -- service, mount 等

  -- 使用 JSON 输出获取单元列表
  local cmd =
    { 'systemctl', '--' .. scope, 'list-units', '--type=' .. unit_type, '--all', '--output=json', '--no-pager' }

  lc.system(cmd, function(out)
    if out.code ~= 0 then
      lc.log('error', 'Failed to list units: {}', out.stderr or 'Unknown error')
      cb {}
      return
    end

    -- 解析 JSON 输出
    local success, data = pcall(lc.json.decode, out.stdout)
    if not success or type(data) ~= 'table' then
      lc.log('error', 'Failed to parse JSON output: {}', data or 'Unknown error')
      cb {}
      return
    end

    -- 构建条目列表
    local entries = {}
    for _, unit in ipairs(data) do
      local unit_name = unit.unit
      local load_state = unit.load or ''
      local active_state = unit.active or ''
      local sub_state = unit.sub or ''
      local description = unit.description or ''

      -- 根据 load_state 和 active_state 选择颜色
      local display = unit_name
      if load_state == 'not-found' then
        display = display:fg 'yellow'
      elseif active_state == 'active' then
        display = display:fg 'green'
      elseif active_state == 'failed' then
        display = display:fg 'red'
      elseif active_state == 'inactive' then
        display = display
      elseif active_state == 'activating' or active_state == 'deactivating' then
        display = display:fg 'yellow'
      else
        display = display
      end

      table.insert(entries, {
        key = unit_name,
        unit = unit_name,
        load = load_state,
        active = active_state,
        sub = sub_state,
        description = description,
        display = display,
        scope = scope,
        type = unit_type,
      })
    end

    cb(entries)
  end)
end

function M.list(path, cb)
  if #path == 1 then
    -- 第1级：system / user
    list_level_1(cb)
  elseif #path == 2 then
    -- 第2级：单元类型
    list_level_2(path, cb)
  elseif #path == 3 then
    -- 第3级：具体单元
    list_level_3(path, cb)
  else
    cb {}
  end
end

function M.preview(entry, cb)
  local path = lc.api.get_current_path()

  -- 第1级：显示提示信息
  if #path == 1 then
    cb 'Select system or user scope'
    return
  end

  -- 第2级：显示类型描述
  if #path == 2 then
    local scope = path[2]
    local lines = {
      'Scope: ' .. scope,
      '',
      'Select a unit type to view units:',
    }
    for _, unit_type in ipairs(unit_types) do
      table.insert(lines, '  • ' .. unit_type.icon .. ' ' .. unit_type.name)
    end
    cb(table.concat(lines, '\n'))
    return
  end

  -- 第3级：显示单元详细状态
  if #path == 3 and entry and entry.unit then
    local scope = path[2]
    lc.system({ 'systemctl', '--' .. scope, 'status', '--no-pager', '--', entry.unit }, {
      env = {
        SYSTEMD_COLORS = '1',
      },
    }, function(out) cb((out.stdout .. out.stderr):ansi()) end)
    return
  end

  cb 'No preview available'
end

return M
