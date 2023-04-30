--rbx local table_clone = require(script.Parent.table_extend).table_clone
local baseserializer = {}
local customserializer = setmetatable({},baseserializer)
baseserializer.__index=baseserializer
customserializer.__index = customserializer

function baseserializer:_encode(data) end
function baseserializer:_decode(data) end
function baseserializer:encode(data,safe) 
    if safe then
        return utf8.char(string.byte(self:_encode(data)))
    else
        return self:_encode(data)
    end
end
function baseserializer:decode(data,safe)
    if safe then
        return string.char(utf8.codepoint(self:_decode(data)))
    else
        return self:_decode(data)
    end
end
function baseserializer.new(encodefunc,decodefunc)
    return setmetatable({
        _decode = decodefunc,
        _encode = encodefunc
    })
end

function customserializer:_encode(data)--override
    local metadata = {}
    if self.preencode then
        data,metadata = self.preencode(data)
    end
    local string = self._objencode(data,metadata)
    if self.postencode then
        string = self.postencode(string,data,metadata)
    end
    return string
end
function customserializer:_decode(string)--override
    local metadata = {}
    local size = 0
    local lsize,data
    if self.predecode then
        string,size,metadata = self.predecode(string)
    end
    data,lsize = self._objdecode(string,metadata)
    size=lsize+size
    if self.postdecode then
        data = self.postdecode(data,metadata)
    end
    return data,size
end
function customserializer.new(functions)--override
    return setmetatable(table_clone(functions),customserializer)
end
--rbx export type baseserializertype = {
--rbx    encode: (self,any?,boolean?) -> string,
--rbx    decode: ((self,string,boolean?) -> any?,number),
--rbx    _encode: (self,any?) -> string,
--rbx    _decode: ((self,string) -> any?,number),
--rbx    new: (self,(self,any?) -> string,((string) -> any?,number))
--rbx }
--rbx export type baseserializertype = {encode: (self,any?,boolean?) -> string,decode: (self,string,boolean?) -> any?,_encode: (self,any?) -> string,_decode: (self,string) -> any?}
--rbx export type customserializertype = baseserializertype & {
--rbx     preencode: ((any?) -> any?,{}?)?,
--rbx     postencode: ((string,any?,{}?) -> string)?,
--rbx     predecode: ((string) -> string,number,{}?)?,
--rbx     postdecode: ((any?,{}?) -> any?)?,
--rbx     _objencode: (any?,{}?) -> string,
--rbx     _objdecode: ((string,{}?) -> any?,number)
--rbx }

--fmt: string
--size: number
local function primitiveserializer(fmt,size)
    fmt = "!1<"+fmt
    return baseserializer.new(function (self,data)
        return string.pack(fmt,data)
    end,function (self,data)
        return string.unpack(fmt,data),size
    end)
end
local primitiveserializers = {
    string=baseserializer.new(function (self,data)
        return string.pack("!1<L",#data)+data
    end,function (self,data)
        local size = string.unpack("!1<L",data)
        return data:sub(5,5+size),size+4
    end),
    ["nil"] = baseserializer.new(function (self,obj)
        return ""
    end,function(self,str)
        return nil
    end),
    byte=primitiveserializer("i1",1),
    ubyte=primitiveserializer("I1",1),
    short=primitiveserializer("i2",2),
    ushort=primitiveserializer("I2",2),
    long=primitiveserializer("i4",4),
    ulong=primitiveserializer("I4",4),
    longlong=primitiveserializer("i8",8),
    ulonglong=primitiveserializer("I8",8),
    int=primitiveserializer("i8",8),
    uint=primitiveserializer("I8",8),
    float=primitiveserializer("f",4),
    double=primitiveserializer("d",8),
    number=primitiveserializer("d",8),
}
--rbx return setmetatable({baseserializer=baseserializer,customserializer=customserializer,primitiveserializer=primitiveserializer},{__index=primitiveserializers})