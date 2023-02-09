local frozenMetaTable = {
    __newindex=function(t,k,v)
        error("frozen table")
    end,
    __metatable=false
}
local function rawFind(t,v)
    for k,vv in pairs(t) do
        if rawget(v,vv) then return k end
    end
end
local function newPrivateEvent()
    local hooks = {}
    return setmetatable({
        Connect=function(f)
            table.insert(hooks,f)
            return setmetatable({
                Disconnect=function()
                    pcall(function()
                        table.remove(hooks,rawFind(hooks,f))
                    end)
                end
            },frozenMetaTable)
        end,
        Wait=function()
            local currentThread = coroutine.running()
            local function f(...)
                coroutine.resume(currentThread,...)
            end
            table.insert(hooks,f)
            local args = table.pack(coroutine.yield())
            pcall(function()
                table.remove(hooks,rawFind(hooks,f))
            end)
            return table.unpack(args)
        end
    },frozenMetaTable),function(...)
        for _,f in ipairs(hooks) do
            coroutine.wrap(f)(...)
        end
    end
end