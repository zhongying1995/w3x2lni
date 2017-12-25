local w2l
local wtg
local state
local chunk
local unpack_index
local read_eca
local fix
local fix_step
local retry_point
local abort

local function fix_arg(n)
    n = n or #fix_step
    if n <= 0 then
        abort = true
        if #fix_step > 0 then
            error '未知UI参数超过100个，放弃修复。'
        else
            error '触发器文件错误。'
        end
    end
    local step = fix_step[n]
    if #step.args >= 100 then
        step.args = {}
        w2l.message(('猜测[%s]的参数数量为[0]'):format(step.name))
        return fix_arg(n-1)
    end
    table.insert(step.args, {})
    w2l.message(('猜测[%s]的参数数量为[%d]'):format(step.name, #step.args))
    return step.save_point
end

local function try_fix(tp, name)
    if not fix.ui[tp] then
        fix.ui[tp] = {}
    end
    if not fix.ui[tp][name] then
        w2l.message(('触发器UI[%s]不存在'):format(name))
        fix.ui[tp][name] = {
            name = name,
            fix = true,
            args = {},
            category = 'TC_UNKNOWUI',
            save_point = save_point,
        }
        table.insert(fix_step, fix.ui[tp][name])
        
        if not fix.categories[tp] then
            fix.categories[tp] = {}
            fix.categories[tp]['TC_UNKNOWUI'] = {}
            table.insert(fix.categories[tp], 'TC_UNKNOWUI')
        end
        table.insert(fix.categories[tp]['TC_UNKNOWUI'], fix.ui[tp][name])
        w2l.message(('猜测[%s]的参数数量为[0]'):format(name))
        try_count = 0
    end
    return fix.ui[tp][name]
end

local type_map = {
    [0] = 'event',
    [1] = 'condition',
    [2] = 'action',
    [3] = 'call',
}

local function get_ui_define(type, name)
    return state.ui[type][name] or try_fix(type, name)
end

local function unpack(fmt)
    local result
    result, unpack_index = fmt:unpack(wtg, unpack_index)
    return result
end

local function read_head()
    chunk.file_id  = unpack 'c4'
    chunk.file_ver = unpack 'l'
end

local function read_category()
    local category = {}
    category.id      = unpack 'l'
    category.name    = unpack 'z'
    category.comment = unpack 'l'
    return category
end

local function read_categories()
    local count = unpack 'l'
    chunk.categories = {}
    for i = 1, count do
        table.insert(chunk.categories, read_category())
    end
end

local function read_var()
    local var = {}
    var.name         = unpack 'z'
    var.type         = unpack 'z'
    var.int_unknow_1 = unpack 'l'
    var.is_arry      = unpack 'l'
    var.array_size   = unpack 'l'
    var.is_default   = unpack 'l'
    var.value        = unpack 'z'
    return var
end

local function read_vars()
    chunk.int_unknow_1 = unpack 'l'
    local count = unpack 'l'
    chunk.vars = {}
    for i = 1, count do
        table.insert(chunk.vars, read_var())
    end
end

local arg_type_map = {
    [-1] = 'disabled',
    [0]  = 'preset',
    [1]  = 'var',
    [2]  = 'call',
    [3]  = 'constant',
}

local preset_map
local function get_preset_type(name)
    if not preset_map then
        preset_map = {}
        for _, line in ipairs(state.ui.define.TriggerParams) do
            local key = line[1]
            local type = line[2]:match '%d+%,([%w_]+)%,'
            if type == 'typename' then
                preset_map[key] = key:match '^.-_(.+)$'
            else
                preset_map[key] = type
            end
        end
    end
    if preset_map[name] then
        return preset_map[name], 1.0
    else
        return 'unknowtype', 0.0
    end
end

local var_map
local function get_var_type(name)
    if not var_map then
        var_map = {}
        for _, var in ipairs(chunk.vars) do
            var_map[var.name] = var.type
        end
    end
    if var_map[name] then
        return var_map[name], 1.0
    else
        return 'unknowtype', 0.0
    end
end

local function get_ui_returns(ui, ui_type, ui_guess_level)
    if not ui.fix then
        if ui.returns == 'AnyReturnType' then
            return 'unknow', 0.0
        else
            return ui.returns, 1.0
        end
    end
    if not ui.returns_guess_level then
        ui.returns = ui_type
        ui.returns_guess_level = ui_guess_level
    end
    if ui.returns ~= ui_type and ui.returns_guess_level < ui_guess_level then
        ui.returns = ui_type
        ui.returns_guess_level = ui_guess_level
        retry_point = ui.save_point
        error(('重新计算[%s]的参数类型。'):format(ui.name))
    end
    return ui.returns, ui.returns_guess_level
end

local function get_call_type(name, ui_type, ui_guess_level)
    local ui = get_ui_define('call', name)
    if ui then
        return get_ui_returns(ui, ui_type, ui_guess_level)
    else
        return 'unknowtype', 0.0
    end
end

local function get_constant_type(value)
    if value == 'true' or value == 'false' then
        return 'boolean', 0.1
    elseif value:match '^[%-]?[1-9][%d]*$' then
        return 'integer', 0.2
    elseif value:match '^[%-]?[1-9][%d]*[%.][%d]*$' then
        return 'real', 0.3
    else
        return 'string', 0.4
    end
end

local function get_arg_type(arg, ui_type, ui_guess_level)
    local atp = arg_type_map[arg.type]
    if atp == 'disabled' then
        return 'unknowtype', 0.0
    elseif atp == 'preset' then
        return get_preset_type(arg.value)
    elseif atp == 'var' then
        return get_var_type(arg.value)
    elseif atp == 'call' then
        return get_call_type(arg.value, ui_type, ui_guess_level)
    else
        return get_constant_type(arg.value)
    end
end

local function fix_arg_type(ui, ui_arg, arg, args)
    local ui_arg_type
    local ui_guess_level
    if ui.fix then
        ui_arg_type = ui_arg.type or 'unknowtype'
        ui_guess_level = ui_arg.guess_level or 0.0
    else
        ui_arg_type = ui_arg.type
        ui_guess_level = 1.0
    end
    if ui_arg_type == 'AnyGlobal' then
        ui_arg_type = 'unknowtype'
        ui_guess_level = 0.0
    elseif ui_arg_type == 'Null' then
        ui_arg_type = 'unknowtype'
        ui_guess_level = 0.0
        local ok
        for i = #args, 1, -1 do
            if ok then
                if ui.args[i].type == 'AnyGlobal' or ui.args[i].type == 'typename' then
                    if args[i].arg_type then
                        ui_arg_type = args[i].arg_type
                        ui_guess_level = 1.0
                    end
                    break
                end
            elseif args[i] == arg then
                ok = true
            end
        end
    end
    local tp, arg_guess_level = get_arg_type(arg, ui_arg_type, ui_guess_level)
    if ui.fix and arg_guess_level > ui_guess_level and ui_arg_type ~= 'AnyGlobal' and ui_arg_type ~= 'Null' then
        ui_arg.type = tp
        ui_arg.guess_level = arg_guess_level
    end
    if arg_guess_level == 1.0 then
        arg.arg_type = tp
    end
end

local function read_arg()
    local arg = {}
    arg.type        = unpack 'l'
    arg.value       = unpack 'z'
    arg.insert_call = unpack 'l'
    assert(arg_type_map[arg.type], 'arg.type 错误')
    assert(arg.insert_call == 0 or arg.insert_call == 1, 'arg.insert_call 错误')

    if arg.insert_call == 1 then
        arg.eca = read_eca(false)
    end

    arg.insert_index = unpack 'l'
    assert(arg.insert_index == 0 or arg.insert_index == 1, 'arg.insert_index 错误')
    if arg.insert_index == 1 then
        arg.index = read_arg()
    end
    return arg
end

function read_eca(is_child)
    local eca = {}
    eca.type = unpack 'l'
    if is_child then
        eca.child_id = unpack 'l'
    end
    eca.name   = unpack 'z'
    eca.enable = unpack 'l'

    assert(type_map[eca.type], 'eca.type 错误')
    assert(eca.name:match '^[%g%s]+$', ('eca.name 错误：[%s]'):format(eca.name))
    assert(eca.enable == 0 or eca.enable == 1, 'eca.enable 错误')

    eca.args = {}
    local ui = get_ui_define(type_map[eca.type], eca.name)
    if ui.args then
        for _, arg in ipairs(ui.args) do
            if arg.type ~= 'nothing' then
                local arg = read_arg(ui)
                table.insert(eca.args, arg)
                fix_arg_type(ui, ui.args[#eca.args], arg, eca.args)
            end
        end
    end
    eca.child_count = unpack 'l'
    return eca
end

local function read_ecas(ecas, count, is_child)
    for i = 1, count do
        local eca = read_eca(is_child)
        table.insert(ecas, eca)
        read_ecas(ecas, eca.child_count, true)
    end
end

local function read_trigger()
    local trigger = {}
    trigger.name     = unpack 'z'
    trigger.des      = unpack 'z'
    trigger.type     = unpack 'l'
    trigger.enable   = unpack 'l'
    trigger.wct      = unpack 'l'
    trigger.init     = unpack 'l'
    trigger.run_init = unpack 'l'
    trigger.category = unpack 'l'

    assert(trigger.type == 0 or trigger.type == 1, 'trigger.type 错误')
    assert(trigger.enable == 0 or trigger.enable == 1, 'trigger.enable 错误')
    assert(trigger.wct == 0 or trigger.wct == 1, 'trigger.wct 错误')
    assert(trigger.init == 0 or trigger.init == 1, 'trigger.init 错误')
    assert(trigger.run_init == 0 or trigger.run_init == 1, 'trigger.run_init 错误')

    trigger.ecas = {}
    local count = unpack 'l'
    read_ecas(trigger.ecas, count, false)

    return trigger
end

local function read_triggers()
    local count = unpack 'l'
    chunk.triggers = {}
    local pos = 1
    while true do
        local suc, err = pcall(function()
            for i = pos, count do
                save_point = { i, unpack_index }
                chunk.triggers[i] = read_trigger()
            end
        end)
        if suc then
            break
        else
            try_count = try_count + 1
            assert(not abort, err)
            assert(try_count < 1000, '在大量尝试后放弃修复。')
            --w2l.message(err)
            if retry_point then
                pos, unpack_index = retry_point[1], retry_point[2]
                retry_point = false
            else
                local load_point = fix_arg()
                pos, unpack_index = load_point[1], load_point[2]
            end
        end
    end
end

local function fill_fix()
    if not next(fix.ui) then
        return nil
    end
    fix.ui.define = {
        TriggerCategories = {
            { 'TC_UNKNOWUI', '未知UI,ReplaceableTextures\\CommandButtons\\BTNInfernal.blp' },
        },
        TriggerType = {
            { 'unknowtype', '1,0,0,未知参数类型,string'},
        },
    }
    for _, type in pairs(type_map) do
        if not fix.ui[type] then
            fix.ui[type] = {}
        end
        if not fix.categories[type] then
            fix.categories[type] = {}
        end
        for _, ui in pairs(fix.ui[type]) do
            local arg_types = {}
            local comment = {}
            for i, arg in ipairs(ui.args) do
                if not arg.type then
                    arg.type = 'unknowtype'
                    arg.guess_level = 0
                end
                table.insert(arg_types, (' ${%s} '):format(arg.type))
                if arg.guess_level == 0 then
                    table.insert(comment, ('第 %d 个参数类型未知。'):format(i))
                elseif arg.guess_level < 1 then
                    table.insert(comment, ('第 %d 个参数类型可能不正确。'):format(i))
                end
            end
            if ui.returns then
                if ui.returns_guess_level == 0 then
                    table.insert(comment, ('返回类型未知。'):format(i))
                elseif ui.returns_guess_level < 1 then
                    table.insert(comment, ('返回类型不确定。'):format(i))
                end
            end
            ui.title = ('%s'):format(ui.name)
            ui.description = ('%s(%s)'):format(ui.name, table.concat(arg_types, ','))
            ui.comment = table.concat(comment, '\n')
        end
    end
end

return function (w2l_, wtg_, state_)
    w2l = w2l_
    wtg = wtg_
    state = state_
    unpack_index = 1
    try_count = 0
    fix = { ui = {} , categories = {} }
    fix_step = {}
    chunk = {}

    read_head()
    read_categories()
    read_vars()
    read_triggers()
    
    fill_fix()
    
    return chunk, fix
end
