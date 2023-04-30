--rbx local thread = require(script.Parent.thread)
--rbx local newThread = thread.newThread
--rbx local dispatchThread = thread.dispatchThread
--rbx local deleteThread = thread.deleteThread
--rbx local serializers = require(script.Parent.serializers)
--rbx local table_reverse = require(script.Parent.table_extend).table_reverse
local frozen_serializers = setmetatable({},{
    __mode="kv",
    __newindex=function (t,k,v)
        error("library table is frozen",2)
    end,
    __index=serializers,
    __metatable=false
})
local _cputhreads=setmetatable({},{__mode="k"})
local nilobj = setmetatable({},{
    __mode="kv",
    __tostring=function (t)
        return "nil"
    end,
    __eq=function (t,o)
        return rawequal(o,nil)
    end,
    __metatable = false
})
local relaaddress = serializers.struct({
    type="ubyte",
    addr="uint",
    _getstruct=function (obj)
        if type(obj) == "table" then
            if obj.type == 2 or obj.type == 8 or obj.type == 9 then
                return {
                    type="ubyte",
                    addr="variant",
                }
            else
                return {
                    type="ubyte",
                    addr="uint",
                }
            end
        else
            local otype = serializers.ubyte:decode(obj)
            if otype == 2 or otype == 8 or otype == 9 then
                return {
                    type="ubyte",
                    addr="variant",
                }
            else
                return {
                    type="ubyte",
                    addr="uint",
                }
            end
        end
    end,
})
local adrtypeReversed = {
    [0]="absolute",
    "relative",
    "variant",

    [4]="Pabsoluteabsolute", -- last absolute can be either a number or a variant
    [5]="Prelativeabsolute",
    [6]="Pabsoluterelative",
    [7]="Prelativerelative",
    [8]="Pvariantabsolute",
    [9]="Pvariantrelative",
    
}
local adrtype = {}
for num,name in pairs(adrtypeReversed) do
    adrtype[name] = num
end
local InstructionsReserved={
    "LOAD_OBJ",

    "LOAD_LOCAL",
    "LOAD_MEMORY", -- basically same as deref but does not throw an exception, also uses it from memory

    "DROP_ONE",
    "DROP_ALL",
    "DROP_AT",
    "DUPLICATE_ONCE",
    "DUPLICATE_ONCE_TO",

    "REF", -- get a pointer to that object, puts it in memory if it doesnt exist
    "DEREF", -- gets object from pointer

    "SYSCALL",
    "YIELD", --puts thread in suspended state, requires something to trigger it back

    "SET_MEMORY", --sets in memory at pointer
    "SET_LOCAL",

    "ADD",
    "SUB",
    "MUL",
    "DIV",
    "POW",
    "NEGATE",
    "INT",

    "CONCAT",

    "INDEX",
    "NEWINDEX",
    "LEN",
    "NEXT",

    "CALL", -- Call, an object, a function, an address

    "LOAD_LIB", -- math,string,table,utf8,os,etc. just no threading
    "DUMP", -- Dumps the latest object on the stack to a string (from object stack)
    "LOAD", -- Load a string to an object (from object stack)

    "SETMT",
    "GETMT",

    "JUMP",
    "TESTJUMP",
    "STACKJUMP",
    "RETURN",
    "PJUMP",

    "ASSERT",
    "THROW",
}
local Instructions={}
for num,name in ipairs(InstructionsReserved) do
    Instructions[name] = num
end
local cpuinterpreter
local instruction_switch={
    [Instructions.LOAD_OBJ]=function (system)
        local obj,size = serializers.variant:decode(system:getcode())
        system:incpc(size)
        if rawequal(obj,nil) then
            obj = nilobj
        end
        system:addstack(obj)
    end,
    [Instructions.LOAD_LOCAL]=function (system)
        local name,size = serializers.string:decode(system:getcode())
        system:incpc(size)
        local obj = system:fetchlocals()[name]
        if rawequal(obj,nil) then
            obj = nilobj
        end
        system:addstack(obj)
    end,
    [Instructions.LOAD_MEMORY]=function (system)
        local adr,size = relaaddress:decode(system:getcode())
        system:incpc(size)
        local atype = adr.type
        local obj
        assert(atype <= 9,"invalid address type")
        if atype == adrtype.relative then
            obj=system.memory[system:getrelativeaddress()+adr]
        elseif atype == adrtype.absolute or atype == adrtype.variant then
            obj=system.memory[adr]
        elseif atype == adrtype.Pabsoluteabsolute or atype == adrtype.Pabsoluterelative or atype == adrtype.Pvariantabsolute or atype == adrtype.Pvariantrelative then
            adr = system.memory[adr]
            assert(not (rawequal(adr,nil) or rawequal(adr,nilobj)),"null dereference exception")
            if atype == adrtype.Pabsoluterelative then
                obj=system.memory[system:getrelativeaddress()+adr]
            else
                obj=system.memory[adr]
            end
        elseif atype == adrtype.Prelativeabsolute or atype == adrtype.Prelativerelative then
            adr = system.memory[system:getrelativeaddress()+adr]
            assert(not (rawequal(adr,nil) or rawequal(adr,nilobj)),"null dereference exception")
            if atype == adrtype.Pabsoluterelative then
                obj=system.memory[system:getrelativeaddress()+adr]
            else
                obj=system.memory[adr]
            end
        end
        if rawequal(obj,nil) then
            obj = nilobj
        end
        system:addstack(obj)
    end,
    [Instructions.DROP_ONE]=function (system)
        local ostack =system.object_stack[system:fetchstackindex()]
        ostack[#ostack] = nil
    end,
    [Instructions.DROP_AT]=function (system)
        local ostack = system.object_stack[system:fetchstackindex()]
        local pos,size = serializers.ulong:decode(system:getcode())
        system:pcinc(size)
        table.remove(ostack,#ostack-pos)
    end,
    [Instructions.DROP_ALL]=function (system)
        system.object_stack[system:fetchstackindex()] = {}
    end,
    [Instructions.DUPLICATE_ONCE]=function (system)
        system:addstack(system:getlaststack())
    end,
    [Instructions.DUPLICATE_ONCE_FROM]=function (system)
        local ostack =system.object_stack[system:fetchstackindex()]
        local pos,size = serializers.ulong:decode(system:getcode())
        system:pcinc(size)
        system:addstack(ostack[#ostack-pos])
    end,
    [Instructions.REF]=function (system)
        local obj = system:popstack()
        if rawequal(obj,nilobj) or rawequal(obj,nil) then
            system:addstack(nilobj)
        elseif system.reversed_memory[obj] then
            system:addstack(system.reversed_memory[obj])
        else
            local adr = math.random(1,0xFFFFFFFF)
            system.reversed_memory[obj] = adr
            system.memory[adr] = obj
            system:addstack(adr)
        end
    end,
    [Instructions.DEREF]=function (system)
        local adr = system:popstack()
        if rawequal(adr,nilobj) or rawequal(adr,nil) then
            error("null dereference exception")
        elseif system.memory[adr] then
            system:addstack(system.memory[adr])
        else
            error("null dereference exception")
        end
    end,
    [Instructions.SYSCALL]=function (system)
        local i,size = serializers.ulong:decode(system:getcode())
        system:incpc(size)
        system._insyscall = true
        system.syscallf(i)
    end,
    [Instructions.YIELD]=function (system)
        system._yielding = true
        system.state = "suspending"
    end,
    [Instructions.SET_MEMORY]=function (system)
        local adr,size = relaaddress:decode(system:getcode())
        system:incpc(size)
        local atype = adr.type
        local obj = system:popstack()
        if rawequal(obj,nilobj) then
            obj = nil
        end
        assert(atype <= 9,"invalid address type")
        if atype == adrtype.relative then
            system.memory[system:getrelativeaddress()+adr] = obj
        elseif atype == adrtype.absolute or atype == adrtype.variant then
            system.memory[adr] = obj
        elseif atype == adrtype.Pabsoluteabsolute or atype == adrtype.Pabsoluterelative or atype == adrtype.Pvariantabsolute or atype == adrtype.Pvariantrelative then
            adr = system.memory[adr]
            assert(not (rawequal(adr,nil) or rawequal(adr,nilobj)),"null dereference exception")
            if atype == adrtype.Pabsoluterelative then
                system.memory[system:getrelativeaddress()+adr] = obj
            else
                system.memory[adr] = obj
            end
        elseif atype == adrtype.Prelativeabsolute or atype == adrtype.Prelativerelative then
            adr = system.memory[system:getrelativeaddress()+adr]
            assert(not (rawequal(adr,nil) or rawequal(adr,nilobj)),"null dereference exception")
            if atype == adrtype.Pabsoluterelative then
                system.memory[system:getrelativeaddress()+adr] = obj
            else
                system.memory[adr] = obj
            end
        end
    end,
    [Instructions.SET_LOCAL]=function (system)
        local name,size = serializers.string:decode(system:getcode())
        system:incpc(size)
        local obj = system:popstack()
        if rawequal(obj,nilobj) then
            obj = nil
        end
        system:fetchlocals()[name] = obj
    end,
    [Instructions.ADD]=function (system)
        local b,a = system:popstack(),system:popstack()
        if rawequal(b,nilobj) then
            b = nil
        end
        if rawequal(a,nilobj) then
            a = nil
        end
        local res = a+b
        if rawequal(res,nil) or rawequal(res,nilobj) then
            res = nilobj
        end
        system:addstack(res)
    end,
    [Instructions.SUB]=function (system)
        local b,a = system:popstack(),system:popstack()
        if rawequal(b,nilobj) then
            b = nil
        end
        if rawequal(a,nilobj) then
            a = nil
        end
        local res = a-b
        if rawequal(res,nil) or rawequal(res,nilobj) then
            res = nilobj
        end
        system:addstack(res)
    end,
    [Instructions.MUL]=function (system)
        local b,a = system:popstack(),system:popstack()
        if rawequal(b,nilobj) then
            b = nil
        end
        if rawequal(a,nilobj) then
            a = nil
        end
        local res = a*b
        if rawequal(res,nil) or rawequal(res,nilobj) then
            res = nilobj
        end
        system:addstack(res)
    end,
    [Instructions.DIV]=function (system)
        local b,a = system:popstack(),system:popstack()
        if rawequal(b,nilobj) then
            b = nil
        end
        if rawequal(a,nilobj) then
            a = nil
        end
        local res = a/b
        if rawequal(res,nil) or rawequal(res,nilobj) then
            res = nilobj
        end
        system:addstack(res)
    end,
    [Instructions.POW]=function (system)
        local b,a = system:popstack(),system:popstack()
        if rawequal(b,nilobj) then
            b = nil
        end
        if rawequal(a,nilobj) then
            a = nil
        end
        local res = a^b
        if rawequal(res,nil) or rawequal(res,nilobj) then
            res = nilobj
        end
        system:addstack(res)
    end,
    [Instructions.NEGATE]=function (system)
        local a = system:popstack()
        if rawequal(a,nilobj) then
            a = nil
        end
        local res = -a
        if rawequal(res,nil) or rawequal(res,nilobj) then
            res = nilobj
        end
        system:addstack(res)
    end,
    [Instructions.INT]=function (system)
        local a = system:popstack()
        if rawequal(a,nilobj) then
            a = nil
        end
        local res = math.tointeger(a)
        if rawequal(res,nil) or rawequal(res,nilobj) then
            res = nilobj
        end
        system:addstack(res)
    end,
    [Instructions.CONCAT]=function (system)
        local b,a = system:popstack(),system:popstack()
        if rawequal(b,nilobj) then
            b = nil
        end
        if rawequal(a,nilobj) then
            a = nil
        end
        local res = a..b
        if rawequal(res,nil) or rawequal(res,nilobj) then
            res = nilobj
        end
        system:addstack(res)
    end,
    [Instructions.INDEX]=function (system)
        local b,a = system:popstack(),system:popstack()
        if rawequal(b,nilobj) then
            b = nil
        end
        if rawequal(a,nilobj) then
            a = nil
        end
        local res = a[b]
        if rawequal(res,nil) or rawequal(res,nilobj) then
            res = nilobj
        end
        system:addstack(res)
    end,
    [Instructions.NEWINDEX]=function (system)
        local c,b,a = system:popstack(),system:popstack(),system:popstack()
        if rawequal(c,nilobj) then
            c = nil
        end
        if rawequal(b,nilobj) then
            b = nil
        end
        if rawequal(a,nilobj) then
            a = nil
        end
        a[b] = c
    end,
    [Instructions.LEN]=function (system)
        local a = system:popstack()
        if rawequal(a,nilobj) then
            a = nil
        end
        local res = #a
        if rawequal(res,nil) or rawequal(res,nilobj) then
            res = nilobj
        end
        system:addstack(res)
    end,
    [Instructions.CALL]=function (system)
        local a = system:popstack()
        if rawequal(a,nilobj) then
            a = nil
        end
        local args = system.object_stack[system:fetchstackindex()]
        table_reverse(args)
        system.object_stack[system:fetchstackindex()] = table.pack(a(table.unpack(args)))
    end,
    [Instructions.LOAD_LIB]=function (system)
        local str,size = serializers.string:decode(system:getcode())
        system:pcinc(size)
        if str == "math" then
            system:addstack(math or nilobj)
        elseif str == "os" then
            system:addstack(os or nilobj)
        elseif str == "string" then
            system:addstack(string or nilobj)
        elseif str == "table" then
            system:addstack(table or nilobj)
        elseif str == "utf8" then
            system:addstack(utf8 or nilobj)
        elseif str == "bit32" then
            system:addstack(bit32 or nilobj)
        elseif str == "tostring" then
            system:addstack(tostring or nilobj)
        elseif str == "tonumber" then
            system:addstack(tonumber or nilobj)
        elseif str == "type" then
            system:addstack(serializers.typef or nilobj)
        elseif str == "serializers" then
            system:addstack(frozen_serializers)
        elseif str == "assert" then
            system:addstack(assert or nilobj)
        else
            error("lib not found")
        end
        if rawequal(system:getlaststack(),nilobj) then
            error("lib not found")
        end
    end,
    [Instructions.DUMP]=function (system)
        local obj = system:popstack()
        if rawequal(obj,nilobj) then
            obj = nil
        end
        obj = serializers.variant:encode(obj)
        system:addstack(obj)
    end,
    [Instructions.LOAD]=function (system)
        local obj = system:popstack()
        if rawequal(obj,nilobj) then
            obj = nil
        end
        obj = serializers.variant:decode(obj)
        system:addstack(obj)
    end,
    [Instructions.SETMT]=function (system)
        local obj,mt = system:popstack(),system:popstack()
        if rawequal(obj,nilobj) then
            obj = nil
        end
        if rawequal(mt,nilobj) then
            mt = nil
        end
        setmetatable(obj,mt)
        system:addstack(obj)
    end,
    [Instructions.GETMT]=function (system)
        local obj = system:popstack()
        if rawequal(obj,nilobj) then
            obj = nil
        end
        obj = getmetatable(obj)
        system:addstack(obj)
    end,
    [Instructions.JUMP]=function (system)
        local adr,size = relaaddress:decode(system:getcode())
        system:incpc(size)
        local atype = adr.type
        assert(atype <= 9,"invalid address type")
        if atype == adrtype.relative then
            adr = system:getrelativeaddress()+adr
        elseif atype == adrtype.absolute then
        elseif atype == adrtype.Pabsoluteabsolute or atype == adrtype.Pabsoluterelative then
            adr = system.memory[adr]
            assert(not (rawequal(adr,nil) or rawequal(adr,nilobj)),"null dereference exception")
        elseif atype == adrtype.Prelativeabsolute or atype == adrtype.Prelativerelative then
            adr = system.memory[system:getrelativeaddress()+adr]
            assert(not (rawequal(adr,nil) or rawequal(adr,nilobj)),"null dereference exception")
        else
            error("variant type for address not supported")
        end
        system.pc = adr
    end,
    [Instructions.TESTJUMP]=function (system)
        local tradr,size = relaaddress:decode(system:getcode())
        system:incpc(size)
        local faadr,size = relaaddress:decode(system:getcode())
        system:incpc(size)
        local obj = system:popstack()
        if rawequal(obj,nilobj) then
            obj = nil
        end
        local tratype = tradr.type
        local faatype = faadr.type
        assert(tratype <= 9,"invalid address type")
        assert(faatype <= 9,"invalid address type")
        if tratype == adrtype.relative then
            tradr = system:getrelativeaddress()+tradr
        elseif tratype == adrtype.absolute then
        elseif tratype == adrtype.Pabsoluteabsolute or tratype == adrtype.Pabsoluterelative then
            tradr = system.memory[tradr]
            assert(not (rawequal(tradr,nil) or rawequal(tradr,nilobj)),"null dereference exception")
        elseif tratype == adrtype.Prelativeabsolute or tratype == adrtype.Prelativerelative then
            tradr = system.memory[system:getrelativeaddress()+tradr]
            assert(not (rawequal(tradr,nil) or rawequal(tradr,nilobj)),"null dereference exception")
        else
            error("variant type for address not supported")
        end
        if faatype == adrtype.relative then
            faadr = system:getrelativeaddress()+faadr
        elseif faatype == adrtype.absolute then
        elseif faatype == adrtype.Pabsoluteabsolute or faatype == adrtype.Pabsoluterelative then
            faadr = system.memory[faadr]
            assert(not (rawequal(faadr,nil) or rawequal(faadr,nilobj)),"null dereference exception")
        elseif faatype == adrtype.Prelativeabsolute or faatype == adrtype.Prelativerelative then
            faadr = system.memory[system:getrelativeaddress()+faadr]
            assert(not (rawequal(faadr,nil) or rawequal(faadr,nilobj)),"null dereference exception")
        else
            error("variant type for address not supported")
        end
        if obj then
            system.pc = tradr
        else
            system.pc = faadr
        end
    end,
    [Instructions.STACKJUMP]=function (system)
        local adr,size = relaaddress:decode(system:getcode())
        system:incpc(size)
        local atype = adr.type
        assert(atype <= 9,"invalid address type")
        if atype == adrtype.relative then
            adr = system:getrelativeaddress()+adr
        elseif atype == adrtype.absolute then
        elseif atype == adrtype.Pabsoluteabsolute or atype == adrtype.Pabsoluterelative then
            adr = system.memory[adr]
            assert(not (rawequal(adr,nil) or rawequal(adr,nilobj)),"null dereference exception")
        elseif atype == adrtype.Prelativeabsolute or atype == adrtype.Prelativerelative then
            adr = system.memory[system:getrelativeaddress()+adr]
            assert(not (rawequal(adr,nil) or rawequal(adr,nilobj)),"null dereference exception")
        else
            error("variant type for address not supported")
        end
        local astack = system.address_stack
        local lstack = system.locals_stack
        local ostack = system.object_stack
        astack[#astack+1] = system.pc
        lstack[#lstack+1] = {}
        ostack[#ostack+1] = {}
        system.pc = adr
    end,
    [Instructions.RETURN]=function (system)
        local rsize,size = serializers.ulong:decode(system:getcode())
        system:incpc(size)
        local t = {}
        for i = 1,rsize do
            t[rsize-i+1] = system:popstack()
        end
        local _ostack = system.object_stack
        local ostack = _ostack[#_ostack]
        for i,v in ipairs(t) do
            ostack[#ostack+1] = v
        end
    end,
    [Instructions.PJUMP]=function (system)
        local adr,size = relaaddress:decode(system:getcode())
        system:incpc(size)
        local atype = adr.type
        assert(atype <= 9,"invalid address type")
        if atype == adrtype.relative then
            adr = system:getrelativeaddress()+adr
        elseif atype == adrtype.absolute then
        elseif atype == adrtype.Pabsoluteabsolute or atype == adrtype.Pabsoluterelative then
            adr = system.memory[adr]
            assert(not (rawequal(adr,nil) or rawequal(adr,nilobj)),"null dereference exception")
        elseif atype == adrtype.Prelativeabsolute or atype == adrtype.Prelativerelative then
            adr = system.memory[system:getrelativeaddress()+adr]
            assert(not (rawequal(adr,nil) or rawequal(adr,nilobj)),"null dereference exception")
        else
            error("variant type for address not supported")
        end
        local currpc = system.pc
        system.pc = adr
        local result,err = pcall(cpuinterpreter)
        if not result then
            local ostack = system.object_stack
            ostack[#ostack] = {err}
            system.pc = currpc
        else
            --ok, all is good
        end
    end,
    [Instructions.ASSERT]=function (system)
        local obj = system:popstack()
        if rawequal(obj,nilobj) then
            obj = nil
        end
        assert(obj)
    end,
    [Instructions.THROW]=function (system)
        local obj = system:popstack()
        if rawequal(obj,nilobj) then
            obj = nil
        end
        error(obj)
    end
}

function cpuinterpreter()
    local system = _cputhreads[coroutine.running()]
    while true do
        system._insyscall = false
        if system._yielding then
            if system.waitingthread then
                coroutine.resume(system.waitingthread)
            end
            system.state = "suspended"
            coroutine.yield()
            system.state = "running"
        end
        local code = system:getcode()
        if #code == 0 then
            error("page access violation")
        end
        local inst = string.unpack("!1>B",code)
        code = nil
        local func = instruction_switch[inst]
        system:incpc(1)
        assert(func,"invalid instruction")
        func(system)
    end
end
local function cputhreadstart()
    local system = _cputhreads[coroutine.running()]
    system.state = "initialized"
    if system.waitingthread then
        coroutine.resume(system.waitingthread)
        system.waitingthread = nil
    end
    coroutine.yield()
    system.state = "running"
    pcall(cpuinterpreter)
    system.state = "dead"
    if system.waitingthread then
        coroutine.resume(system.waitingthread)
        system.waitingthread = nil
    end
    system.memory = {}
    system.address_stack = {}
    system.locals_stack = {}
    system.reversed_memory = setmetatable({},{__mode="kv"})
    system.object_stack = {}
    system.code = ""
end
local function newCPUThread(syscallf)
    local thread = newThread(cputhreadstart)
    local cputhread = {
        _yielding=false,
        thread=thread,
        state="none",
        nilobj=nilobj,
        _insyscall=false,
        syscallf=syscallf,

        waitingthread=nil,

        memory={},
        reversed_memory=setmetatable({},{__mode="kv"}),
        address_stack={},
        locals_stack={},
        object_stack={},
        code="",
        codeindex=1,
        codeaddresses={1},
        pc=0,
        incpc=function (self,a)
            self.pc = self.pc+a
        end,
        fetchstackindex=function (self)
            return #(self.address_stack)+1
        end,
        getrelativeaddress=function(self)
            return self.codeaddresses[self.codeindex]
        end,
        addstack=function (self,obj)
            local ostack =self.object_stack[self:fetchstackindex()]
            ostack[#ostack+1] = obj
        end,
        getlaststack=function (self)
            local ostack =self.object_stack[self:fetchstackindex()]
            return ostack[#ostack]
        end,
        popstack=function (self)
            local ostack =self.object_stack[self:fetchstackindex()]
            local obj = ostack[#ostack]
            ostack[#ostack] = nil
            return obj
        end,
        fetchlocals=function (self)
            return self.locals_stack[self:fetchstackindex()]
        end,
        getcode=function (self)
            return self.code:sub(self.pc)
        end,

        start=function (self)
            if self.state == "none" then
                if self.waitingthread then
                    return false
                end
                self.waitingthread = coroutine.running()
                coroutine.yield()
            end
            if self.state == "initialized" then
                coroutine.resume(thread)
                self.state = "starting"
                return true
            elseif self.state == "suspended" then
                coroutine.resume(thread)
                self.state = "resuming"
                return true
            end
            return false
        end,
        stop=function (self)
            self._yielding = true
            if self.thread then
                deleteThread(self.thread)
                self.thread = nil
            end
            self.state = "dead"
        end,
        suspend=function (self)
            if self.state == "running" then
                if self.waitingthread then
                    return false
                end
                self.waitingthread = coroutine.running()
                self._yielding = true
                self.state = "suspending"
                coroutine.yield()
                return true
            end
            return false
        end
    }
    _cputhreads[thread] = cputhread
    dispatchThread(thread)
    return cputhread
end
local function getCPUThread(thr)
    return _cputhread[thr]
end
--rbx return {newCPUThread=newCPUThread,getCPUThread=getCPUThread}