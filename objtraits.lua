local objtraits = {}
local __exobj = setmetatable({},{__mode="k"})
local exmt
exmt = {
    __newindex=function(t,k,v) error("frozen object") end,
    __metatable=false,
    __call=function(t,func)
        local tt = setmetatable({},exmt)
        __exobj[tt] = func
        return tt
    end,
    __tostring=function(t)
        return "executableobject"..tostring(__exobj[t]):sub(8,-1)
    end,

}
exmt.__index = exmt
local executableobject = setmetatable({},exmt)
objtraits.__index = objtraits
local function rawIsIn(tbl,v)
    for k,vv in pairs(tbl) do
        if rawequal(v,vv) then return k end
    end
    return nil
end
local function isExecutableObject(obj)
    return not rawequal(__exobj[obj],nil)
end
function objtraits:isADirectory()
    error("unimplemented")
end
function objtraits:getFullPath()
    local buf = ""
    local c = self
    if self.parent then 
        while true do
            if c.parent then
                buf = "/" .. c.name
                c = c.parent
            else break end
        end
        return buf
    else
        return "/"
    end
end
function objtraits:to(path,absoluteassert)
    path = path or "/"
    local isabsolute = path:sub(1,1) == "/"
    if absoluteassert then assert(isabsolute,"pathname must be absolute") end
    local dir = self
    if isabsolute then
        while dir.parent ~= nil do
            dir = dir.parent
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
                if dir.parent ~= nil then dir = dir.parent end
            else
                dir = dir:subread(buf)
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
            if dir.parent ~= nil then dir = dir.parent end
        else
            dir = dir:subread(buf)
            if not dir then return end
        end
    end
    return dir
end
function objtraits:getPerms()
    return self.perms,self.owner
end
function objtraits:rename(name)
    error("unimplemented")
end
function objtraits:read(at,amount)
    error("unimplemented")
end
function objtraits:subread(name)
    error("unimplemented")
end
function objtraits:write(obj)
    error("unimplemented")
end
function objtraits:subwrite(name,obj)
    error("unimplemented")
end
function objtraits:append(obj,at)
    error("unimplemented")
end
function objtraits:access() --list dir
    error("unimplemented")
end
function objtraits:execute(args)
    error("unimplemented")
end
function objtraits:changeOwner(proc,newuser)
    if self.owner == proc.user or proc.user == "root" then
        self.owner = newuser
    end
end
function objtraits:changePerms(proc,newperms)
    if self.owner == proc.user or proc.user == "root" then
        self.perms = newperms
    end
end
function objtraits:canRead(proc,grouptbl)
    if proc.user == self.owner or proc.user == "root" then
        return self.perms:sub(1,1) == "r"
    else
        local t = false
        for groupname,group in pairs(grouptbl) do
            if rawIsIn(group,self.owner) then 
                if rawIsIn(group,proc.user) then
                    t = true
                    break;
                end
            end
        end
        if t then
            return self.perms:sub(4,4) == "r"
        else
            return self.perms:sub(7,7) == "r"
        end
    end
end
function objtraits:canWrite(proc,grouptbl)
    if proc.user == self.owner or proc.user == "root" then
        return self.perms:sub(2,2) == "w"
    else
        local t = false
        for groupname,group in pairs(grouptbl) do
            if rawIsIn(group,self.owner) then 
                if rawIsIn(group,proc.user) then
                    t = true
                    break;
                end
            end
        end
        if t then
            return self.perms:sub(5,5) == "w"
        else
            return self.perms:sub(8,8) == "w"
        end
    end
end
function objtraits:canExecute(proc,grouptbl)
    if proc.user == self.owner or proc.user == "root" then
        return self.perms:sub(3,3) == "x"
    else
        local t = false
        for groupname,group in pairs(grouptbl) do
            if rawIsIn(group,self.owner) then 
                if rawIsIn(group,proc.user) then
                    t = true
                    break;
                end
            end
        end
        if t then
            return self.perms:sub(6,6) == "x"
        else
            return self.perms:sub(9,9) == "x"
        end
    end
end
function objtraits:canAccess(proc,grouptbl)
    if proc.user == self.owner or proc.user == "root" then
        return self.perms:sub(3,3) == "a"
    else
        local t = false
        for groupname,group in pairs(grouptbl) do
            if rawIsIn(group,self.owner) then 
                if rawIsIn(group,proc.user) then
                    t = true
                    break;
                end
            end
        end
        if t then
            return self.perms:sub(6,6) == "a"
        else
            return self.perms:sub(9,9) == "a"
        end
    end
end
function objtraits:delete()
    error("unimplemented")
end