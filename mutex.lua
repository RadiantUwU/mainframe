local function MutexModule()
    local MutexCls = {}
    local _private = setmetatable({},{__mode="k"})
    local weaktbl = {__mode="v"}
    local panicEnabled = false --If true, creates a new method :panic(), releases all threads

    MutexCls.__index = MutexCls
    function MutexCls:lock()
        local t = _private[self]
        local b = #t == 0
        table.insert(t,coroutine.running())
        if not b then
            local panic = coroutine.yield()
            if panic then
                error("InternalError: Mutex panic.",2)
            end
        end
    end
    function MutexCls:try_lock()
        local t = _private[self]
        local b = #t == 0
        if b then
            table.insert(t,coroutine.running())
        end
        return b
    end
    function MutexCls:locked()
        return _private[self] > 0
    end
    function MutexCls:unlock()
        local t = _private[self]
        if t[1] == coroutine.running() then
            table.remove(t,1)
            pcall(function() coroutine.resume(t[1],false) end)
        end
    end
    if panicEnabled then
        function MutexCls:panic()
            local t = _private[self]
            local nt = table.clone(t)
            table.clear(t)
            for _,thr in ipairs(nt) do
                coroutine.resume(thr,true)
            end
        end
    else
        function MutexCls:panic()
            error("Not enabled.")
        end
    end
    --Freeze all functions
    return function()
        local x = setmetatable({},MutexCls)
        table.freeze(x)
        _private[x] = setmetatable({},weaktbl)
        return x
    end
end
local newmutex = MutexModule()