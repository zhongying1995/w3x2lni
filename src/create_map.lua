local stormlib = require 'stormlib'

local table_insert = table.insert

local function dir_scan(dir, callback)
	for full_path in dir:list_directory() do
		if fs.is_directory(full_path) then
			-- 递归处理
			dir_scan(full_path, callback)
		else
			callback(full_path)
		end
	end
end

local mt = {}
mt.__index = mt

function mt:add(format, ...)
    self.hexs[#self.hexs+1] = (format):pack(...)
end

function mt:add_head()
    self:add('c4', 'HM3W')
    self:add('c4', '\0\0\0\0')
end

function mt:add_name()
    self:add('z', self.w3i.map_name)
end

function mt:add_flag()
    self:add('l', self.w3i.map_flag)
end

function mt:add_playercount()
    self:add('l', self.w3i.player_count)
end

function mt:add_input(input)
    if fs.is_directory(input) then
        if #self.w3xs > 0 then
            return false
        end
        table_insert(self.dirs, input)
    else
        if #self.dirs > 0 then
            return false
        end
        table_insert(self.w3xs, input)
    end
    return true
end

function mt:get_listfile()
    local files = {}
    local dirs = {}
    local listfile = {}
	local pack_ignore = {}
	for _, name in ipairs(self.config['pack']['packignore']) do
		pack_ignore[name:lower()] = true
	end
    
	local clock = os.clock()
	local success, failed = 0, 0
    for _, dir in ipairs(self.dirs) do
        local dir_len = #dir:string()
        dir_scan(dir, function(path)
            local name = path:string():sub(dir_len+2)
            if not pack_ignore[name:lower()] then
                listfile[#listfile+1] = name
                files[name] = io.load(path)
                dirs[name] = dir
                if files[name] then
                    success = success + 1
                else
                    failed = failed + 1
                    print('文件读取失败', name)
                end
                if os.clock() - clock >= 0.5 then
                    clock = os.clock()
                    if failed == 0 then
                        print('正在读取', '成功:', success)
                    else
                        print('正在读取', '成功:', success, '失败:', failed)
                    end
                end
            end
        end)
    end
    if failed == 0 then
        print('读取完毕', '成功:', success)
    else
	    print('读取完毕', '成功:', success, '失败:', failed)
    end
	return listfile, files, dirs
end

function mt:import_files(map, listfile, files, dirs, on_save)
	local clock = os.clock()
	local success, failed = 0, 0
	for i = 1, #listfile do
		local name = listfile[i]
        local name, content = on_save(name, files[name], dirs[name])
        if content then
            local name, content = self.w3x2txt:lni2w3x(name, content)
            if content then
                if map:save_file(name, content) then
                    success = success + 1
                else
                    failed = failed + 1
                    print('文件导入失败', name)
                end
                if os.clock() - clock >= 0.5 then
                    clock = os.clock()
                    if failed == 0 then
                        print('正在导入', '成功:', success)
                    else
                        print('正在导入', '成功:', success, '失败:', failed)
                    end
                end
            end
        end
	end
    if failed == 0 then
        print('导入完毕', '成功:', success)
    else
	    print('导入完毕', '成功:', success, '失败:', failed)
    end
end

function mt:import_imp(map, listfile)
	local imp_ignore = {}
	for _, name in ipairs(self.config['pack']['impignore']) do
		imp_ignore[name:lower()] = true
	end

	local imp = {}
	for _, name in ipairs(listfile) do
		if not imp_ignore[name:lower()] then
			imp[#imp+1] = ('z'):pack(name)
		end
	end
	table.insert(imp, 1, ('ll'):pack(1, #imp))
	if not map:save_file('war3map.imp', table.concat(imp, '\r')) then
		print('war3map.imp导入失败')
	end
end

function mt:save_map(map_path, on_save)
    local w3i = {
        map_name = '只是另一张魔兽争霸III地图',
        map_flag = 0,
        player_count = 2333,
    }
    for _, dir in ipairs(self.dirs) do
        if fs.exists(dir / 'war3map.w3i') then
            w3i = self.w3x2txt:read_w3i(io.load(dir / 'war3map.w3i'))
            break
        end
    end

    self.hexs = {}
    self.w3i  = w3i

    self:add_head()
    self:add_name()
    self:add_flag()
    self:add_playercount()

    local temp_path = fs.path 'temp'

    io.save(temp_path, table.concat(self.hexs))
    
    local listfile, files, dirs = self:get_listfile()
    local map = stormlib.create(temp_path, #listfile+8)
	if not map then
		print('地图创建失败,可能是文件被占用了')
		return nil
	end

	self:import_files(map, listfile, files, dirs, on_save)
	self:import_imp(map, listfile)

    map:close()
    fs.rename(temp_path, map_path)
    
    return true
end

function mt:unpack(on_save)
    local map_path = self.w3xs[1]
    -- 解压地图
	local map = stormlib.open(map_path)
	if not map then
		print('地图打开失败')
		return
	end

	if not map:has_file '(listfile)' then
		print('不支持没有文件列表(listfile)的地图')
		return
	end
	map:close()
	
	local files, paths = self.w3x2txt:extract_files(map_path, on_save)
	self.w3x2txt:w3x2lni(files, paths)
end

function mt:save(map_path, on_save)
    if #self.dirs > 0 then
        return self:save_map(map_path, on_save)
    elseif #self.w3xs > 0 then
        return self:unpack(on_save)
    end
    return false
end

return function (w3x2txt)
    local self = setmetatable({}, mt)
    self.dirs = {}
    self.w3xs = {}
    self.config = w3x2txt.config
    self.w3x2txt = w3x2txt
    return self
end
