local fileobjectmt = {}
local _foldercontent = setmetatable({},{__mode="k",__index=function(t,k) local tt = {} rawset(t,k,tt) return tt end})
local _objectowner = setmetatable({},weaktbl)
local _objectparent = setmetatable({},weaktbl)
local _objectname = setmetatable({},weaktbl)
local _objectpermission = setmetatable({},weaktbl)
local _objectprocesssystem = setmetatable({},{__mode="kv"})
local _filecontent = setmetatable({},weaktbl)
local _objectisFolder = setmetatable({},weaktbl)
fileobjectmt.__index = fileobjectmt
--[[
    File permissions:
    File permissions look something like
    "rwxr-xr-x"
    or
    "rwSr-S--t"

]]
local _strintsw = {
    ["0"]="0000",
    ["1"]="0001",
    ["2"]="0010",
    ["3"]="0011",
    ["4"]="0100",
    ["5"]="0101",
    ["6"]="0110",
    ["7"]="0111",
    ["8"]="1000",
    ["9"]="1001",
    ["a"]="1010",
    ["b"]="1011",
    ["c"]="1100",
    ["d"]="1101",
    ["e"]="1110",
    ["f"]="1111",
}
local function perminttostr(int)
    local _s = string.format("%.x3",int)
    local s = ""
    for i = 1,3 do
        s  = s .. _strintsw[_s:sub(i,i)]
    end
    _s = s
    s = ""
    local t = 0
    for i = 1,12 do
        if i % 4 == 3 then
            if _s:sub(i,i) == "1" then
                t = 1
            else
                t = 0
            end
        elseif i == 4 or i == 8 then
            if _s:sub(i,i) == "1" then
                if t then
                    s = s .. "s"
                else
                    s = s .. "S"
                end
            else
                if t then
                    s = s .. "x"
                else
                    s = s .. "-"
                end
            end
        elseif i == 12 then
            if _s:sub(i,i) == "1" then
                if t then
                    s = s .. "t"
                else
                    s = s .. "T"
                end
            else
                if t then
                    s = s .. "x"
                else
                    s = s .. "-"
                end
            end
        elseif i % 4 == 1 then
            if _s:sub(i,i) == "1" then
                s = s .. "r"
            else
                s = s .. "-"
            end
        elseif i % 4 == 2 then
            if _s:sub(i,i) == "1" then
                s = s .. "w"
            else
                s = s .. "-"
            end
        end
    end
    return s
end
local function permstrtoint(str)
    local int = 0
    for _,c in ipairs(into_chars(str)) do
        int = int * 2
        if c == "r" or c == "w" then
            int = int + 1
        elseif c == "x" then
            int = int + 1
            int = int * 2
        elseif c == "S" or c == "T" then
            int = int * 2
            int = int + 1
        elseif c == "s" or c == "t" then
            int = int + 1
            int = int * 2
            int = int + 1
        end
    end
    return int
end

function fileobjectmt:getWhereUserFitsPermission(user)
    local owner = _objectowner[self]
    local pr = _objectprocesssystem[self]
    if not pr then error("object became invalid",2) end
    if owner == user then return "+" 
    elseif pr.isInGroupWith(owner,user) then return "n"
    else return "-"
    end
end
function fileobjectmt:getWhereCurrentFitsPermission()
    local owner = _objectowner[self]
    local pr = _objectprocesssystem[self]
    if not pr then error("object became invalid",2) end
    local process = _objectprocesssystem[self].processthreads[coroutine.running()]
    if not process then error("not a process",2) end
    local g = process:getGroupUser()
    if g and not (owner == process.user) then
        local groups = pr.getGroupsOfUser(g)
        for _,group in ipairs(groups) do
            if group[owner] then
                return "n"
            end
        end
    end
    if owner == process.user then return "+" 
    elseif pr.isInGroupWith(owner,process:getUser()) then return "n"
    else return "-"
    end
end
function fileobjectmt:getPermissions(t)
    if not t then
        return perminttostr(_objectpermission[self] % 4096)
    elseif t == "+" then
        return perminttostr(_objectpermission[self] % 4096):sub(1,3)
    elseif t == "n" then
        return perminttostr(_objectpermission[self] % 4096):sub(4,6)
    elseif t == "-" then
        return perminttostr(_objectpermission[self] % 4096):sub(7,9)
    end
end
function fileobjectmt:permissionAsInteger()
    return _objectpermission[self]
end
function fileobjectmt:getFullPath()
    local buf = ""
    local c = self
    if _objectparent[self] then 
        while true do
            if _objectparent[c] then
                buf = "/" .. _objectname[c] .. buf
                c = _objectparent[c]
            else break end
        end
        return buf
    else
        return "/"
    end
end
function fileobjectmt:getName()
    return _objectname[self]
end
function fileobjectmt:getOwner()
    return _objectowner[self]
end
function fileobjectmt:getParent()
    return _objectparent[self]
end
function fileobjectmt:to(path,absoluteassert)
    path = path or "/"
    local isabsolute = path:sub(1,1) == "/"
    if absoluteassert then assert(isabsolute,"pathname must be absolute") end
    local dir = self
    if isabsolute then
        local parent = _objectparent[dir]
        while parent ~= nil do
            dir = parent
            parent = _objectparent[dir]
        end
        path = path:sub(2,-1)
    end
    if #path > 1 then
        if path:sub(-2,-1) == "/" then
            path = path:sub(1,-2)
        end
    end
    if path == "" then
        return dir
    end
    local buf = ""
    for _,c in ipairs(into_chars(path)) do
        if c == "/" then
            if buf == "." then

            elseif buf == ".." then
                local parent = _objectparent[dir]
                if parent ~= nil then dir = parent end
            else
                dir = dir:access(buf)
                if not dir then return end
            end
            buf = ""
        else
            buf = buf .. c
        end
    end
    if buf ~= "" then
        if buf == "." then

        elseif buf == ".." then
            local parent = _objectparent[dir]
            if parent ~= nil then dir = parent end
        else
            dir = dir:access(buf)
            if not dir then return end
        end
    end
    return dir
end
function fileobjectmt:canRead()
    local perms = self:getPermissions(self:getWhereCurrentFitsPermission())
    return perms:sub(1,1) == "r"
end
function fileobjectmt:canWrite()
    local perms = self:getPermissions(self:getWhereCurrentFitsPermission())
    return perms:sub(2,2) == "w"
end
function fileobjectmt:canExecute()
    local perms = self:getPermissions(self:getWhereCurrentFitsPermission())
    local s = perms:sub(3,3)
    return s == "x" or s == "s" or s == "t"
end
function fileobjectmt:isSuperBitSet()
    local perms = self:getPermissions(self:getWhereCurrentFitsPermission())
    local s = perms:sub(3,3)
    return s == "S" or s == "s"
end
function fileobjectmt:isStickySet()
    local perms = self:getPermissions(self:getWhereCurrentFitsPermission())
    local s = perms:sub(3,3)
    return s == "t"
end
function fileobjectmt:changeOwner(newowner)
    local owner = _objectowner[self]
    local pr = _objectprocesssystem[self]
    if not pr then error("object became invalid",2) end
    local process = _objectprocesssystem[self].processthreads[coroutine.running()]
    if not process then error("not a process",2) end
    if process.user == "root" or process.user == owner then
        _objectowner[self] = newowner
    end
end
function fileobjectmt:rename(newname)
    local parent = self:getParent()
    if parent then
        if not parent:canWrite() then error("access denied.",2) end
        local oldname = _objectname[self]
        _foldercontent[parent][oldname] = nil
        _foldercontent[parent][newname] = self
        _objectname[parent] = newname
    else
        error("cannot rename rootfs",2)
    end
end
function fileobjectmt:isDirectory()
    return _objectisFolder[self]
end
function fileobjectmt:read()
    if not self:canRead() then error("access denied",2) end
    if self:isDirectory() then
        local dir = {}
        for fname,f in pairs(_foldercontent[self]) do
            dir[#dir+1] = fname
        end
        return dir
    else
        return newStream(_filecontent[self])
    end
end
function fileobjectmt:write()
    if not self:canWrite() then error("access denied",2) end
    if self:isDirectory() then
        error("invalid function used",2)
    else
        return newStreamWithData(_filecontent,self)
    end
end
function fileobjectmt:execute(argv)
    if not self:canExecute() then error("access denied",2) end
    if self:isDirectory() then error("invalid function used",2)
    else
        local processtable = _objectprocesssystem[self]
        local process = processtable.processthreads[coroutine.running()]
        local func = _filecontent[self]
        assert(type(func)=="function","invalid file provided")
        local init,sigh = func()
        assert(type(init)=="function" and type(sigh) == "table","invalid file provided")
        local pdata = _processdata[process]
        local perms = self:getPermissions()
        local su,sg = perms:sub(3,3),perms:sub(6,6)
        su = su == "s" or su == "S"
        sg = sg == "s" or sg == "S"
        if su then
            pdata.user = self:getOwner()
        end
        if sg then
            pdata.groupuser = self:getOwner()
        end
        process:exec(_objectname[self],init,sigh,argv,self:getFullPath())
        -- thread killed
    end
end
function fileobjectmt:access(what)
    if not self:canExecute() then error("access denied",2) end
    if not self:isDirectory() then error("invalid function used",2) end
    return _foldercontent[self][what]
end
function fileobjectmt:delete()
    local parent = self:getParent()
    if parent then
        if not parent:canWrite() then error("access denied.",2) end
        local oldname = _objectname[self]
        _foldercontent[parent][oldname] = nil
        _objectprocesssystem[self] = nil --invalidate the object
        _foldercontent[self] = nil
        _filecontent[self] = nil
    else
        error("cannot delete rootfs",2)
    end
end
function fileobjectmt:setPermissions(int)
    assert(type(int) == "number","must be number")
    int = math.floor(int)
    local owner = _objectowner[self]
    local pr = _objectprocesssystem[self]
    if not pr then error("object became invalid",2) end
    local process = _objectprocesssystem[self].processthreads[coroutine.running()]
    if not process then error("not a process",2) end
    if process.user == "root" or process.user == owner then
        _objectpermission[self] = int % 4096
    end
end

local function goTo(path,rootfs)
    if path:sub(1,1) == "/" then
        return rootfs:to(path,true)
    else
        local processsystem = _objectprocesssystem[rootfs]
        if not processsystem then error("object is invalid",2) end
        local process = processsystem.processthreads[coroutine.running()]
        if not process then error("not a process",2) end
        local relPath = process:getEnv("workingDir")
        if relPath then
            local relative = rootfs:to(relPath,true)
            if not relative then return end
            return relative:to(path)
        else
            error("workingDir enviroment variable not found",2)
        end
    end
end

function fileobjectmt:move(topath)
    local newfolder = goTo(topath,self:to("/"))
    local oldfolder = _objectparent[self]
    local name = _objectname[self]
    if not oldfolder then error("cannot move rootfs",2) end
    if not newfolder then error("not found",2) end
    if not newfolder:canWrite() then error("access denied.",2) end
    if not _objectparent[self]:canWrite() then error("access denied.") end
    _foldercontent[oldfolder][name] = nil
    _foldercontent[newfolder][name] = self
end