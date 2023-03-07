local function populateExecutables(kernelAPI)
    local du,pr,bindir,sbindir = kernelAPI.du,kernelAPI.pr,kernelAPI.bindir,kernelAPI.sbindir
    local newFile = du._newFile
    local EOF = string.char(0x04)
    local shinit
    local function shreadcmd(proc,getch)
        local c = getch()
        while c ~= "\n" then
            if c == "\b" then
                proc:setPrivEnv("cmdbuffer",proc:getPrivEnv("cmdbuffer"):sub(1,-2))
            else
                proc:setPrivEnv("cmdbuffer",proc:getPrivEnv("cmdbuffer")..c)
            end
        end
    end
    local function _octtn(s)
        assert(tonumber(s),"must be valid oct number")
        assert(s ~= "8" and s ~= "9","must be valid oct number")
        return tonumber(s)
    end
    local function _hextn(s)
        if s == "0" then return 0
        elseif s == "1" then return 1
        elseif s == "2" then return 2
        elseif s == "3" then return 3
        elseif s == "4" then return 4
        elseif s == "5" then return 5
        elseif s == "6" then return 6
        elseif s == "7" then return 7
        elseif s == "8" then return 8
        elseif s == "9" then return 9
        elseif s == "a" or s == "A" then return 10
        elseif s == "b" or s == "B" then return 11
        elseif s == "c" or s == "C" then return 12
        elseif s == "d" or s == "D" then return 13
        elseif s == "e" or s == "E" then return 14
        elseif s == "f" or s == "F" then return 15
        else error("must be valid hex number",2) end
    end
    local function octtochar(oct)
        local n = 0
        local s = #oct
        for i = 1,s do
            n = n + _octtn(oct:sub(i,i))*(8^(s-i))
        end
        return string.char(n)
    end
    local function hextochar(hex)
        local n = 0
        local s = #oct
        for i = 1,s do
            n = n + _hextn(hex:sub(i,i))*(16^(s-i))
        end
        return string.char(n)
    end
    local function strparse(strrep)
        local buffer1,buffer2,state,quotes = "","",0,""
        for i,c in ipairs(into_chars(strrep)) do
            if i == 1 then quotes = c
            elseif c == quotes and state == 0 then return buffer1,i
            elseif c == "\\" and state == 0 then state = 1
            elseif state == 1 then
                if c == "a" then buffer1 = buffer1 .. "\a" state = 0
                elseif c == "b" then buffer1 = buffer1 .. "\b" state = 0
                elseif c == "f" then buffer1 = buffer1 .. "\f" state = 0
                elseif c == "n" then buffer1 = buffer1 .. "\n" state = 0
                elseif c == "\n" then state = 0
                elseif c == "r" then buffer1 = buffer1 .. "\r" state = 0
                elseif c == "t" then buffer1 = buffer1 .. "\t" state = 0
                elseif c == "v" then buffer1 = buffer1 .. "\v" state = 0
                elseif c == "\\" then buffer1 = buffer1 .. "\\" state = 0
                elseif c == "\"" then buffer1 = buffer1 .. "\"" state = 0
                elseif c == "'" then buffer1 = buffer1 .. "'" state = 0
                elseif c == "[" then buffer1 = buffer1 .. "[" state = 0
                elseif c == "]" then buffer1 = buffer1 .. "]" state = 0
                elseif string.match(c,"%d") then
                    state = 2
                elseif c == "x" then
                    state = 5
                else state = 0
                end
            elseif state > 1 and state < 4 or state == 5 then
                buffer2 = buffer2 .. c
                state = state + 1
            elseif state == 4 then
                buffer1 = buffer1 .. octtochar(buffer2 .. c)
                buffer2 = ""
                state = 0
            elseif state == 6 then
                buffer1 = buffer1 .. hextochar(buffer2 .. c)
                buffer2 = ""
                state = 0
            else
                buffer1 = buffer1 .. c
            end
        end
    end
    local function shparsecmd(proc)
        local state,buffer1,buffer2,metadata,skip,cc,ca = "newcmd","","",{},0,0,0
        for ii,c in ipairs(into_chars(proc:getPrivEnv("cmdbuffer")..EOF)) do
            if skip > 0 then
                skip = skip - 1
            elseif state == "newcmd" and (c == "\"" or c == "'") then
                metadata['command'..tostring(cc)],skip,state = strparse(proc:getPrivEnv("cmdbuffer"):sub(ii,-1)),"newarg"
                skip = skip + 1
            elseif (state == "cmd" or state == "newcmd") and (c == " " or c == "\n" or c == EOF) then
                if #buffer1 > 0 then
                    metadata['command'..tostring(cc)] = buffer1
                    buffer1 = ""
                    state = "newarg"
                end
            elseif state == "cmd" or state == "newcmd" then
                buffer1 = buffer1 .. c
                state = "cmd"
            elseif (state == "newarg" or state == "arg") then
                if (c == " ") then
                    if #buffer1 > 0 then
                        metadata['arg'..tostring(cc).."_"..tostring(ca)] = buffer1
                        buffer1 = ""
                        ca = ca + 1
                        state = "newarg"
                    end
                elseif (c == "\n" or c == EOF) then
                    if #buffer1 > 0 then
                        metadata['arg'..tostring(cc).."_"..tostring(ca)] = buffer1
                        buffer1 = ""
                        ca = ca + 1
                        state = "newarg"
                    end

                elseif c == ">" then
                    --pipe to file
                    state = "outfilenew"
                    if #buffer1 > 0 then
                        metadata['arg'..tostring(cc).."_"..tostring(ca)] = buffer1
                        buffer1 = ""
                        ca = ca + 1
                    end
                elseif c == "<" then
                    --read from file
                    state = "infilenew"
                    if #buffer1 > 0 then
                        metadata['arg'..tostring(cc).."_"..tostring(ca)] = buffer1
                        buffer1 = ""
                        ca = ca + 1
                    end
                elseif c == "&" then
                    state = "expectnewcommandafter"
                    if #buffer1 > 0 then
                        metadata['arg'..tostring(cc).."_"..tostring(ca)] = buffer1
                        buffer1 = ""
                        ca = ca + 1
                    end
                elseif c == "|" then
                    if #buffer1 > 0 then
                        metadata['arg'..tostring(cc).."_"..tostring(ca)] = buffer1
                        buffer1 = ""
                        ca = ca + 1
                    end
                    state = "newcmd"
                    cc = cc +1
                    ca = 0
                elseif (c == "\"" or c == "'") then
                    if #buffer1 > 0 then
                        metadata['arg'..tostring(cc).."_"..tostring(ca)] = buffer1
                        buffer1 = ""
                        ca = ca + 1
                    end
                    local arg
                    arg,skip,state = strparse(proc:getPrivEnv("cmdbuffer"):sub(ii,-1)),"newarg"
                    metadata['arg'..tostring(cc).."_"..tostring(ca)] = arg
                    ca = ca + 1
                elseif (c=="$" and state == "newarg") then
                    state = "newvar"
                else
                    state = "arg"
                    buffer1 = c
                end
            elseif state == "expectnewcommandafter" then
                if c=="&" then
                    state = "newcmd"
                    metadata["cmdcond"..tostring(cc+1)] = "success"
                    cc = cc +1
                    ca = 0
                elseif c == EOF or c == "\n" then
                    state = "newcmd"
                    metadata["cmdtype"..tostring(cc+1)] = "job"
                    cc = cc +1
                    ca = 0
                else
                    error("failed parsing &"..c)
                end
            elseif state == "outfilenew" then
                if c == ">" then state = "appfilenew"
                elseif (c == "\"" or c == "'") then
                    local file
                    file,skip,state = strparse(proc:getPrivEnv("cmdbuffer"):sub(ii)),"newarg"
                    metadata["output_"..tostring(cc)] = file
                else
                    buffer1 = c
                    state = "outfile"
                end
            elseif state == "outfile" then
                if (c == " ") then
                    metadata["output_"..tostring(cc)] = buffer1
                    buffer1 = ""
                    state = "newarg"
                elseif (c == "\n" or c == EOF) then
                    metadata["output_"..tostring(cc)] = buffer1
                    buffer1 = ""
                    cc = cc + 1
                    state = "newcmd"
                else
                    buffer1 = buffer1 .. c
                end
            elseif state == "appfilenew" then
                if (c == "\"" or c == "'") then
                    local file
                    file,skip,state = strparse(proc:getPrivEnv("cmdbuffer"):sub(ii)),"newarg"
                    metadata["append_"..tostring(cc)] = file
                else
                    buffer1 = c
                    state = "appfile"
                end
            elseif state == "appfile" then
                if (c == " ") then
                    metadata["append_"..tostring(cc)] = buffer1
                    buffer1 = ""
                    state = "newarg"
                elseif (c == "\n" or c == EOF) then
                    metadata["append_"..tostring(cc)] = buffer1
                    buffer1 = ""
                    cc = cc + 1
                    state = "newcmd"
                else
                    buffer1 = buffer1 .. c
                end
            elseif state == "inpfilenew" then
                if (c == "\"" or c == "'") then
                    local file
                    file,skip,state = strparse(proc:getPrivEnv("cmdbuffer"):sub(ii)),"newarg"
                    metadata["input_"..tostring(cc)] = file
                else
                    buffer1 = c
                    state = "inpfile"
                end
            elseif state == "inpfile" then
                if (c == " ") then
                    metadata["input_"..tostring(cc)] = buffer1
                    buffer1 = ""
                    state = "newarg"
                elseif (c == "\n" or c == EOF) then
                    metadata["input_"..tostring(cc)] = buffer1
                    buffer1 = ""
                    cc = cc + 1
                    state = "newcmd"
                else
                    buffer1 = buffer1 .. c
                end
            end
        end
    end
    function shinit(proc,forked)
        if forked == true then
            proc:setPrivEnv("forked",true)
            -- busy is already set to true
            --get command
            local command = proc:getPrivEnv("cmd")
            local args = proc:getPrivEnv("args")
            local api = proc:getAPI()
            local exec,exit = api.exec,api.exit
            local success,err = pcall(exec,command,table.unpack(args))
            if not success then
                proc:getStdErr():write(err.."\n")
                exit(1)
            end
        elseif forked == nil then
            while true do 
                proc:setPrivEnv("busy",false)
                proc:setPrivEnv("cmdbuffer","")
                if proc:getUser() == "root" then
                    proc:getStdOut():write("# ")
                else
                    proc:getStdOut():write("$ ")
                end
                shreadcmd(proc,proc:getAPI().getch)

            end
        else
            proc:setPrivEnv("cmdproc",forked) -- PID
            -- await for it to return from function
        end
    end
    newFile("sh",bindir,"root","rwxr-xr-x",function()
        return shinit,{}
    end)
end