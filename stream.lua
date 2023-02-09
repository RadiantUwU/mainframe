local streammt = {}
local genstreammt = {}
local _streamdata = setmetatable({},{__mode="k"})
local streamt:write(s,at)
    at = at or -1
    assert(type(s) == "string","s must be string")
    assert(type(at) == "number","a must be number")
    if at == -1 then _streamdata[self] = _streamdata[self] + s
    elseif at == 1 then _streamdata[self] = s + _streamdata[self]
    else
        _streamdata[self] = string.sub(_streamdata[self],1,at) + s + string.sub(_streamdata[self],at+1,-1)
    end
end