local streammt = {}
local genstreammt = {}
local _streamdata = setmetatable({},{__mode="k"})
local _streamlock = setmetatable({}.{__mode="k"})
local _streamevent = setmetatable({},{__mode="k"})
local _streameventcall = setmetatable({},{__mode="k"})
local streamt:write(s,at)
    at = at or -1
    assert(type(s) == "string","s must be string")
    assert(type(at) == "number","at must be number")
    if _streamdata[self] == nil then error("stream is closed.",2) end
    _streamlock[self]:lock()
    local nerr,err = pcall(function()
        if at == -1 then _streamdata[self] = _streamdata[self] + s
        elseif at == 1 then _streamdata[self] = s + _streamdata[self]
        else
            _streamdata[self] = string.sub(_streamdata[self],1,at) + s + string.sub(_streamdata[self],at+1,-1)
        end
    end)
    -- dispatch event
    _streameventcall[self]()
    _streamlock[self]:unlock()
    if not nerr then
        error(err,2)
    end
end
local genstreamt:write(s,at)
    at = at or -1
    assert(type(s) == "string","s must be string")
    assert(type(at) == "number","at must be number")
    local r = {_streamdata[self]("w",s,at)}
    _streameventcall[self]()
    return table.unpack(r)
end
local streamt:writeAll(s)
    _streamlock[self]:lock()
    _streamdata[self] = s
    _streamlock[self]:unlock()
end
local genstreamt:writeAll(s)
    local r = {_streamdata[self]("wa",s)}
    _streameventcall[self]()
    return table.unpack(r)
end
local streamt:read(amount,at)
    at = at or 0
    amount = amount or -1
    assert(type(amount) == "number","amount must be number")
    assert(type(at) == "number","at must be number")
    if _streamdata[self] == nil then error("stream is closed.",2) end
    _streamlock[self]:lock()
    local nerr,err = pcall(function()
        local s
        if at == -1 then s = ""
        elseif at == 0 then
            s = string.sub(_streamdata[self],1,amount)
            _streamdata[self] = string.sub(_streamdata[self],amount+1,-1)
        else
            s = string.sub(_streamdata[self],at+1,at+1+amount)
            _streamdata[self] = string.sub(_streamdata[self],1,at) + string.sub(_streamdata[self],at+amount+1,-1)
        end
        return s
    end)
    _streamlock[self]:unlock()
    if nerr then return err end
    error(err,2)
end
local genstreamt:read(amount, at)
    at = at or 0
    amount = amount or -1
    assert(type(amount) == "number","amount must be number")
    assert(type(at) == "number","at must be number")
    return _streamdata[self]("r",amount,at)
end
local streamt:readAll()
    _streamlock[self]:lock()
    local s = _streamdata[self]
    _streamlock[self]:unlock()
    _streamdata[self] = ""
    return s
end
local genstreamt:readAll()
    return _streamdata[self]("ra")
end
local streamt:available()
    if _streamdata[self] == nil then return 0 end
    return #_streamdata[self]
end
local genstreamt:available()
    return _streamdata[self]("a")
end
local streamt:close()
    _streamdata[self] = nil
end
local genstreamt:close()
    return _streamdata[self]("c")
end
local streamt:seek(at)
    at = at or 0
    assert(type(at) == "number","at must be number")
    if _streamdata[self] == nil then error("stream is closed.",2) end
    _streamdata[self] = string.sub(_streamdata[self],1+at,-1)
end
local genstreamt:seek(at)
    at = at or 0
    assert(type(at) == "number","at must be number")
    return _streamdata[self]("s",at)
end

local streamt:getWriteEvent()
    return _streamevent[self]
end

local genstreamt:getWriteEvent()
    return _streamevent[self]
end

local function newStream(base)
    base = base or ""
    local obj = {}
    local ev,evcall = newPrivateEvent()
    _streamdata[obj] = ""
    _streamlock[obj] = newmutex()
    _streamevent[obj] = ev
    _streameventcall[obj] = evcall
    return setmetatable(obj,streamt)
end

local function newGenStream(func)
    local obj = {}
    local ev,evcall = newPrivateEvent()
    _streamdata[obj] = func
    _streamevent[obj] = ev
    _streameventcall[obj] = evcall
    return setmetatable(obj,genstreamt)
end

local function newBasicStdin(func,allowWrite)
    allowWrite = allowWrite or false
    --func must not yield!
    
    if allowWrite then
        local backendstream = newStream()
        local function updateBuf()
            if _streamdata[backendstream] == nil then return end
            backendstream:write(func())
        end
        return newGenStream(function(op,a1,a2)
            updateBuf()
            if op == "r" then
                if _streamdata[backendstream] == nil then error("stream is closed",3) end
                return backendstream:read(a1,a2)
            elseif op == "ra" then
                return backendstream:readAll()
            elseif op == "w" then
                if _streamdata[backendstream] == nil then error("stream is closed",3) end
                return backendstream:write(a1,a2)
            elseif op == "wa" then
                return backendstream:writeAll(a1)
            elseif op == "a" then
                if _streamdata[backendstream] == nil then return 0 end
                return backendstream:available()
            elseif op == "s" then
                if _streamdata[backendstream] == nil then error("stream is closed",3) end
                return backendstream:seek(a1)
            elseif op == "c" then
                return backendstream:close()
            end
        end)
    else
        local backendstream = newStream()
        local function updateBuf()
            if _streamdata[backendstream] == nil then return end
            backendstream:write(func())
        end
        return newGenStream(function(op,a1,a2)
            if op == "r" then
                if _streamdata[backendstream] == nil then error("stream is closed",3) end
                updateBuf()
                return backendstream:read(a1,a2)
            elseif op == "ra" then
                if _streamdata[backendstream] == nil then error("stream is closed",3) end
                updateBuf()
                return backendstream:readAll()
            elseif op == "a" then
                if _streamdata[backendstream] == nil then return 0 end
                updateBuf()
                return backendstream:available()
            elseif op == "s" then
                if _streamdata[backendstream] == nil then error("stream is closed",3) end
                updateBuf()
                return backendstream:seek(a1)
            elseif op == "c" then
                return backendstream:close()
            end
        end)
    end
end

local function newBasicStdout(func)
    return newGenStream(function(op,a1,a2)
        if op == "r" then
            return ""
        elseif op == "ra" then
            return ""
        elseif op == "w" then
            return func(a1,a2)
        elseif op == "wa" then
            return func(a1,1)
        elseif op == "a" then
            return 0
        end
    end)
end

local function newBasicStderr(func)
    return newBasicStdout(function(a1,a2)
        func(string.char(18).."2"..a1..string.char(18).."1",a2)
    end)
end