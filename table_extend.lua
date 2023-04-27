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
if isRoblox then 
    table_clone = table.clone
else
    function table_clone(t)
        local nt = {}
        for k,v in pairs(t) do nt[k] = v end
        return nt
    end
end
--rbx return {table_extend=table_extend,table_clone=table_clone}