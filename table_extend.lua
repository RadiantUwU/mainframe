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