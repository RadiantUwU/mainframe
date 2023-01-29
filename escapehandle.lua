local DC1 = string.char(17)
local DC2 = string.char(18)
local FF = string.char(12)
local colors = {
    ["c$n"]=Color3.new(0,0,0),
    ["c$b"]=Color3.new(0,0,0.6),
    ["c$g"]=Color3.new(0,0.6,0),
    ["c$c"]=Color3.new(0,0.6,0.6),
    ["c$r"]=Color3.new(0.6,0,0),
    ["c$m"]=Color3.new(0.6,0,0.6),
    ["c$y"]=Color3.new(0.6,0.6,0),
    ["c$w"]=Color3.new(0.6,0.6,0.6),
    ["c$N"]=Color3.new(0.4,0.4,0.4),
    ["c$B"]=Color3.new(0,0,1),
    ["c$G"]=Color3.new(0,1,0),
    ["c$C"]=Color3.new(0,1,1),
    ["c$R"]=Color3.new(1,0,0),
    ["c$M"]=Color3.new(1,0,1),
    ["c$Y"]=Color3.new(1,1,0),
    ["c$W"]=Color3.new(1,1,1),
}
return function (terminal,poweroffhookadd,stdinf)
    local state = 0
    local echo = false
    local blinkdt = 0
    local blink = false
    local blinking = false
    local fgc = true
    local profile = false -- 1st or 2nd of vvvv
    local fc = {{"c$n","c$w"},{"c$n","c$r"}}
    local function changecolor(c,oc)
        local cv = "c$"..c
        local cc = colors[cv]
        if cc == nil then
            return oc
        end
        return cv,cc
    end
    local function getProfile()
        if profile then
            return fc[2]
        else
            return fc[1]
        end
    end
    local function stdoutf(str)
        if blink then
            terminal:write("\b")
        end
        for _,c in ipairs(into_chars(str)) do
            if state == 0 then
                if c == DC1 then
                    state = 1
                elseif c == DC2 then
                    state = 2
                else
                    terminal:write(c)
                end
            elseif state == 1 then
                local profile = getProfile()
                local color
                if fgc then
                    profile[2],color = changecolor(c,profile[2])
                    terminal:setColor(color)
                else
                    profile[1],color = changecolor(c,profile[1])
                    terminal:setBGColor(color)
                end
                state = 0
            else
                if c == "b" then
                    blink = false
                    blinkdt = 0
                    blinking = false
                elseif c == "B" then
                    blinking = true
                elseif c == "f" then
                    fgc = true
                elseif c == "F" then
                    fgc = false
                elseif c == "e" then
                    echo = false
                elseif c == "E" then
                    echo = true
                elseif c == "1" then
                    profile = false
                    local p = getProfile()
                    terminal:setColor(colors[p[2]])
                    terminal:setBGColor(colors[p[1]])
                elseif c == "2" then
                    profile = true
                    local p = getProfile()
                    terminal:setColor(colors[p[2]])
                    terminal:setBGColor(colors[p[1]])
                elseif c == "c" or c == FF then
                    terminal:clear()
                elseif c == "r" then
                    terminal:clear()
                    blink = false
                    blinkdt = 0
                    blinking = false
                    fgc = true
                    profile = false
                    fc = {{"c$n","c$w"},{"c$n","c$r"}}
                elseif c == "u" then
                    terminal:flush()
                end
                state = 0
            end
        end
        if blink then
            terminal:write("_")
        end
    end
    local function stdinff()
        local str = stdinf()
        if echo then
            coroutine.wrap(stdoutf)(str)
        end
        return str
    end
    local function stderrf(str)
        stdoutf(DC2 .. "2" .. str .. DC2 .. "1")
    end
    local hook = game:GetService("RunService").Heartbeat:Connect(function(dt)
        if blinking then
            blinkdt += dt
            if blinkdt >= 1 then
                blinkdt = 0
                blink = not blink
                if blink then
                    terminal:write("_")
                else
                    terminal:write("\b")
                end
                terminal:flush()
            end
        end
    end)
end