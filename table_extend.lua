--rbx local isRoblox = true
--compat local isRoblox = game and workspace and Vector3 and UDim2
--compat if isRoblox then isRoblox = true else isRoblox = false end
--lua local isRoblox = false
local function table_extend(t,tapp,overwrite)
    overwrite = overwrite or false
    for k,v in pairs(tapp) do
        if not overwrite then
            if not rawequal(t[k],nil) then
                error("cannot overwrite on table",2)
            end
        end
        t[k] = v
    end
    return t
end
local table_clone
local table_clear
local table_reverse
if isRoblox then 
    table_clone = table.clone
else
    function table_clone(t)
        local nt = {}
        for k,v in pairs(t) do nt[k] = v end
        return nt
    end
end
if isRoblox then
    table_clear = table.clear
else
    function table_clear(t)
        for k,v in pairs(table_clone(t)) do t[k] = nil end
        return t
    end
end
if isRoblox then
    table_reverse = table.reverse
else
    function table_reverse(t)
        local table_indexes = {}
        local i = #t
        while i > 0 do
            table_indexes[#table_indexes+1] = i
            i = i - 1
        end
        local clone = table_clone(t)
        for toind,fromind in ipairs(table_indexes) do
            t[toind] = clone[fromind]
        end
    end
end
--rbx return {table_extend=table_extend,table_clone=table_clone,table_clear=table_clear,table_reverse=table_reverse}