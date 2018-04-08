local gui = require 'yue.gui'
local backend = require 'gui.backend'
local timer = require 'gui.timer'
require 'filesystem'

local worker
local view
local pb
local label
local lower
local report

local function getexe()
    local i = 0
    while arg[i] ~= nil do
        i = i - 1
    end
    return fs.path(arg[i + 1])
end

local function pack_arg()
    local buf = {}
    buf[1] = '"' .. window._filename .. '"'
    buf[2] = '-' .. window._mode
    return table.concat(buf, ' ')
end

local function update_progress(value)
    pb:setvalue(value)
    view:schedulepaint()
end

local function update()
    worker:update()
    message:settext(backend.message)
    update_progress(backend.progress)
    if #worker.error > 0 then
        messagebox('错误', worker.error)
        worker.error = ''
        return 0, 1
    end
    if worker.exited then
        if next(backend.report) then
            pb:setvisible(false)
            report:setvisible(true)
        else
            update_progress(100)
        end
        if worker.exit_code == 0 then
            return 1000, 0
        else
            return 0, worker.exit_code
        end
    end
end

local function delayedtask(t)
    local ok, r, code = xpcall(update, debug.traceback)
    if not ok then
        t:remove()
        messagebox('错误', r)
        mini:close()
        exitcode = -1
        return
    end
    if r then
        t:remove()
        if r > 0 then
            timer.wait(r, function()
                if code ~= 0 then
                    exitcode = code
                end
                mini:close()
            end)
        else
            if code ~= 0 then
                exitcode = code
            end
            mini:close()
        end
    end
end

view = gui.Container.create()
view:setstyle { FlexGrow = 1, AlignItems = 'center', JustifyContent = 'center', Padding = 2 }

local upper = gui.Container.create()
upper:setstyle { FlexGrow = 1, AlignItems = 'center', JustifyContent = 'flex-start' }
view:addchildview(upper)

lower = gui.Container.create()
lower:setstyle { FlexGrow = 1, AlignItems = 'center', JustifyContent = 'flex-end' }
view:addchildview(lower)

local filename = Button(window._filename:match '[^/\\]+$')
filename:setstyle { Width = 392, Height = 50, Margin = 2 }
filename:setfont(Font('黑体', 20))
upper:addchildview(filename)

message = gui.Label.create('')
message:setstyle { Width = 392, Height = 20, Margin = 2 }
message:setfont(Font('黑体', 20))
message:setcolor('#CCC')
lower:addchildview(message)

pb = gui.ProgressBar.create()
pb:setstyle { Width = 392, Height = 20, Margin = 10 }
lower:addchildview(pb)
pb:setvisible(false)

report = Button('详情')
report:setstyle { Width = 392, Height = 30, Margin = 10 }
report:setfont(Font('黑体', 24))
lower:addchildview(report)
report:setvisible(false)

local start = Button('开始')
start:setstyle { Width = 392, Height = 50, Margin = 2 }
start:setfont(Font('黑体', 24))
lower:addchildview(start)

function start:onclick()
    if worker and not worker.exited then
        return
    end
    pb:setvisible(true)
    report:setvisible(false)
    backend:init(getexe(), fs.current_path())
    worker = backend:open('map.lua', pack_arg())
    backend.message = '正在初始化...'
    backend.progress = 0
    timer.loop(100, delayedtask)
end

function report:onclick()
    window:show_page 'report'
    window:show_report()
end

return view