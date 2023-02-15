local function newPipe()
    local closedp1,closedp2 = false,false
    local interpipe1 = newStream()
    local interpipe2 = newStream()
    local pipe1 = newGenStream(function(op,a1,a2)
        if op == "r" then
            return interpipe1:read(a1,a2)
        elseif op == "ra" then
            return interpipe1:readAll()
        elseif op == "w" then
            if closedp2 then return end
            return interpipe2:write(a1,a2)
        elseif op == "wa" then
            if closedp2 then return end
            return interpipe2:write(a1)
        elseif op == "a" then
            return interpipe1:available()
        elseif op == "c" then
            closedp1 = true
        elseif op == "t" then
            return "string"
        end
    end)
    local pipe2 = newGenStream(function(op,a1,a2)
        if op == "r" then
            return interpipe2:read(a1,a2)
        elseif op == "ra" then
            return interpipe2:readAll()
        elseif op == "w" then
            if closedp1 then return end
            return interpipe1:write(a1,a2)
        elseif op == "wa" then
            if closedp1 then return end
            return interpipe1:write(a1)
        elseif op == "a" then
            return interpipe2:available()
        elseif op == "c" then
            closedp2 = true
        elseif op == "t" then
            return "string"
        end
    end)
    return pipe1,pipe2
end