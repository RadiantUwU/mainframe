--rbx local primitiveserializers = require(script.Parent.primitiveserializers)
--rbx local baseserializer = primitiveserializers.baseserializer
--rbx local table_clone = require(script.Parent.table_extend).table_clone
--rbx local typef = typeof
--compat local typef = typeof or type
--lua local typef = type

local serializers = setmetatable({},{__index=primitiveserializers})
serializers.typefunc = typef
--objtype: string | baseserializer
--length: int
--return baseserializer
serializers.buildconstantlengtharray = function(objtype,length)
    local oserializer
    if type(oserializer) == "string" then
        oserializer = serializers[objtype]
    else
        oserializer = objtype
    end
    return baseserializer.new(function (self,objtoencode)
        local s = ""
        for o = 1,length do
            s = s .. oserializer:encode(objtoencode[o],false)
        end
        return s
    end,function (self,objtodecode)
        local t = {}
        local size = 1
        for i = 1,length do
            local lsize
            t[i],lsize = oserializer:decode(objtodecode:sub(size),false)
            size = size+lsize
        end
        return t
    end)
end
serializers.buildarray = function(objtype)
    local oserializer
    if type(oserializer) == "string" then
        oserializer = serializers[objtype]
    else
        oserializer = objtype
    end
    return baseserializer.new(function (self,objtoencode)
        local s = serializers.ulong:encode(#objtoencode,false)
        for o = 1,#objtoencode do
            s = s .. oserializer:encode(objtoencode[o],false)
        end
        return s
    end,function (self,objtodecode)
        local t = {}
        local arrsize,size = serializers.ulong:decode(objtodecode,false)
        for i = 1,arrsize do
            local lsize
            t[i],lsize = oserializer:decode(objtodecode:sub(size),false)
            size = size+lsize
        end
        return t
    end)
end
serializers.variant = baseserializer.new(function (self,obj)
    local typ = typef(obj)
    local serializer = serializers[typ]
    assert(serializer,"serializer not found for datatype "..typ)
    return serializers.string:encode(typ)..serializer:encode(obj)
end,function (self,str)
    local typ,size = serializers.string:decode(str)
    local serializer = serializers[typ]
    assert(serializer,"serializer not found for datatype "..typ)
    local obj,lsize = serializer:decode(str:sub(size+1))
    return obj,size+lsize
end)
local function struct_encode(self,data)
    local struct = self._struct
    local metadata = {}
    local str = ""
    if self._getstruct then
        struct = self._getstruct(data)
    end
    if self._preencode then
        data,metadata = self._preencode(data)
    end
    for k,typ in pairs(struct) do
        local serializer
        if type(typ) == "string" then
            serializer = serializers[typ]
            assert(serializer,"no serializer found for datatype "..typ)
        else
            serializer = typ
        end
        local object = data[k]
        str = str .. serializer:encode(object)
    end
    if self._postencode then
        str = self._postencode(str,data,metadata)
    end
    return str
end
local function struct_decode(self,string)
    local struct = self._struct
    local metadata = {}
    local size = 0
    local lsize,data
    if self._getstruct then
        struct = self._getstruct(string)
    end
    if self._predecode then
        string,size,metadata = self._predecode(string)
    end
    for k,typ in pairs(struct) do
        local serializer
        if type(typ) == "string" then
            serializer = serializers[typ]
            assert(serializer,"no serializer found for datatype "..typ)
        else
            serializer = typ
        end
        data[k],lsize = serializer:decode(string:sub(size+1))
        size = size + lsize
    end
    if self._postdecode then
        data = self._postdecode(data,metadata)
    end
    return data,size
end

--structobj: table
--return baseserializer
serializers.struct = function (structobj)
    structobj = structobj or {}
    structobj = table_clone(structobj)
    local funcs = {}
    funcs._struct = structobj
    if structobj._preencode then
        funcs.preencode = structobj._preencode 
        structobj._preencode = nil
    end
    if structobj._postencode then
        funcs.postencode = structobj._postencode 
        structobj._postencode = nil
    end
    if structobj._predecode then
        funcs.predecode = structobj._predecode 
        structobj._predecode = nil
    end
    if structobj._postdecode then
        funcs.postdecode = structobj._postdecode 
        structobj._postdecode = nil
    end
    if structobj._getstruct then
        funcs.getstruct = structobj._getstruct
        structobj._getstruct = nil
    end
    funcs._encode = struct_encode
    funcs._decode = struct_decode
    return setmetatable(funcs,serializers.baseserializer)
end

serializers.KVPair = serializers.struct({
    Key="variant",
    Value="variant"
})
serializers.KVPairs = serializers.buildarray(serializers.KVPair)

serializers.table = baseserializer.new(function (self,obj)
    local pairs_ = {}
    for k,v in pairs(obj) do
        pairs_[#pairs_+1] = {Key=k,Value=v}
    end
    return serializers.KVPairs:encode(pairs_)
end,function (self,obj)
    local pairs_,size = serializers.KVPairs:decode(obj)
    local tbl = {}
    for _,kv in ipairs(pairs_) do
        tbl[kv.Key] = kv.Value
    end
    return tbl,size
end)