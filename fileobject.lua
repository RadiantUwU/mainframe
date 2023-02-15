local fileobjectmt = {}
local _foldercontent = setmetatable({},{__mode="k",__index=function(t,k) local tt = {} rawset(t,k,tt) return tt end})
local _objectowner = setmetatable({},weaktbl)
local _objectparent = setmetatable({},weaktbl)
local _objectname = setmetatable({},weaktbl)
local _objectpermission = setmetatable({},weaktbl)
local _objectprocesssystem = setmetatable({},{__mode="kv"})
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