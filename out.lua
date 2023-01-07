local function into_chars(str)
	local t = {}
	for i=1, #str do
		t[i] = str:sub(i,i)
	end
	return t
end
local _isdigit = {
	["0"]=true,
	["1"]=true,
	["2"]=true,
	["3"]=true,
	["4"]=true,
	["5"]=true,
	["6"]=true,
	["7"]=true,
	["8"]=true,
	["9"]=true
}
local function isdigit (c)
	if _isdigit[c] then return true else return false end
end
local function huge_split(str)
	local chars = into_chars(str)
	local strs = {}
	local quote = ""
	local instr = 0
	local buf = ""
	for _,c in ipairs(chars) do
		if instr == 0 then
			if c == '"' then
				--buffer flush
				if #buf > 0 then
					table.insert(strs,buf)
					buf = ""
				end
				quote = '"'
				instr = 1
				--continue
			elseif c == "'" then
				--buffer flush
				if #buf > 0 then
					table.insert(strs,buf)
					buf = ""
				end
				quote = "'"
				instr = 1
				--continue
			elseif c == '\n' then
				break
			elseif c == ' ' then
				--buffer flush
				if #buf > 0 then
					table.insert(strs,buf)
					buf = ""
				end
				--continue
			elseif c == '\\' then
				instr = 2
				--continue
			else 
				buf = buf .. c
				--continue
			end
		elseif instr == 1 then
			if c == quote then
				--buffer flush
				table.insert(strs,buf)
				buf = ""
				instr = 0
				--continue
			elseif c == '\\' then
				instr = 3
				--continue
			else
				buf = buf .. c
				--continue
			end
		elseif instr == 2 then
			if c == '\n' then
				instr = 0
				--continue
			else
				error("invalid escape sequence")
			end
		elseif instr == 3 then
			if c == 'a' then
				buf = buf .. "\a"
				instr = 1
			elseif c == quote then
				buf = buf .. quote
				instr = 1
			elseif c == 'b' then
				buf = buf .. "\b"
				instr = 1
			elseif c == 'f' then
				buf = buf .. "\f"
				instr = 1
			elseif c == 'n' then
				buf = buf .. "\n"
				instr = 1
			elseif c == 'r' then
				buf = buf .. "\r"
				instr = 1
			elseif c == 't' then
				buf = buf .. "\t"
				instr = 1
			elseif c == 'v' then
				buf = buf .. "\v"
				instr = 1
			elseif c == '\n' then
				buf = buf .. "\n"
				instr = 1
			elseif c == '\r' then
				buf = buf .. "\n"
				instr = 1
			else
				if isdigit(c) then
					buf = buf .. c
					instr = 4
				else
					error("invalid escape in string")
				end
			end
		elseif instr == 4 then
			if isdigit(c) then
				buf = buf .. c
				instr = 5
			else
				error("invalid escape in string")
			end
		else
			if isdigit(c) then
				buf = buf .. c
				local s = tonumber(buf:sub(-3,-1),8)
				buf = buf:sub(0,-4) .. string.char(s)
				instr = 1
			else
				error("invalid escape in string")
			end
		end
	end
	if instr == 0 then
		if #buf > 0 then
			table.insert(strs,buf)
			buf = ""
		end
	elseif instr == 1 then
		error("unended string")
	elseif instr == 2 then
		error("escape EOF")
	else
		error("unended string")
	end
	return strs
end
local streamfuncs = {}
streamfuncs.__index = streamfuncs
function streamfuncs.read(self,amount)
	local s = self.__buf:sub(0,amount)
	self.__buf = self.__buf:sub(amount + 1,-1)
	return s
end
function streamfuncs.readAll(self)
	local s = self.__buf
	self.__buf = ""
	return s
end
function streamfuncs.write(self,str)
	self.__buf = self.__buf .. str
	return self
end
function streamfuncs.available(self)
	return #(self.__buf)
end
function streamfuncs.close(self)
	--unimplemented, placeholder
end
function streamfuncs.seek(self,place)
	self.__buf = self.__buf:sub(place + 1,-1)
	return self
end
local function newStream()
	return setmetatable({__buf = ""},streamfuncs)
end
local genstreamfuncs = {}
genstreamfuncs.__index = genstreamfuncs
function genstreamfuncs.read(self,amount)
	return self.__gen("r",amount)
end
function genstreamfuncs.readAll(self)
	return self.__gen("r",-1)
end
function genstreamfuncs.write(self,str)
	self.__gen("w",str)
	return self
end
function genstreamfuncs.available(self)
	return self.__gen("l")
end
function genstreamfuncs.close(self)
	self.__gen("c")
end
function genstreamfuncs.seek(self,place)
	self.__gen("s",place)
	return self
end
local function newStreamGen(f)
	return setmetatable({__gen=f},genstreamfuncs)
end
local function newStdIn(f)
	local self
	local function stdingen(operation,arg)
		if operation == "l" then
			self.__buf = self.__buf .. f()
			return #(self.__buf)
		elseif operation == "s" then
			self.__buf = (self.__buf .. f()):sub(arg + 1,-1)
		elseif operation == "c" then
		elseif operation == "r" then
			self.__buf = self.__buf .. f()
			local s
			if arg == -1 then
				s = self.__buf
				self.__buf = ""
			else
				s = self.__buf:sub(1,arg)
				self.__buf = self.__buf:sub(arg + 1,-1)
			end
			return s
		elseif operation == "w" then
			self.__buf = self.__buf .. arg
		end
	end
	self = setmetatable({__gen=stdingen,__buf=""},genstreamfuncs)
	return self
end
local function newStdOut(f)
	local s
	local function stdoutgen(operation,arg)
		if operation == "l" then
			return 0
		elseif operation == "w" then
			f(arg)
		end
	end
	s = setmetatable({__gen=stdoutgen,__buf=""},genstreamfuncs)
	return s
end
local function propagateStream(stream,op,arg)
	if op == "r" then
		if arg == -1 then
			return stream:readAll()
		else
			return stream:read(arg)
		end
	elseif op == "c" then
		stream:close()
	elseif op == "s" then
		stream:seek(arg)
	elseif op == "l" then
		return stream:available()
	elseif op == "w" then
		stream:write(arg)
	end
end
--stdout works for stderr too
local function MutexModule()
    local MutexCls = {}
    local _private = setmetatable({},{__mode="k"})
    local weaktbl = {__mode="v"}
    local panicEnabled = false --If true, creates a new method :panic(), releases all threads

    MutexCls.__index = MutexCls
    function MutexCls:lock()
        local t = _private[self]
        local b = #t == 0
        table.insert(t,coroutine.running())
        if not b then
            local panic = coroutine.yield()
            if panic then
                error("InternalError: Mutex panic.",2)
            end
        end
    end
    function MutexCls:try_lock()
        local t = _private[self]
        local b = #t == 0
        if b then
            table.insert(t,coroutine.running())
        end
        return b
    end
    function MutexCls:locked()
        return _private[self] > 0
    end
    function MutexCls:unlock()
        local t = _private[self]
        if t[1] == coroutine.running() then
            table.remove(t,1)
            pcall(function() coroutine.resume(t[1],false) end)
        end
    end
    if panicEnabled then
        function MutexCls:panic()
            local t = _private[self]
            local nt = table.clone(t)
            table.clear(t)
            for _,thr in ipairs(nt) do
                coroutine.resume(thr,true)
            end
        end
    else
        function MutexCls:panic()
            error("Not enabled.")
        end
    end
    --Freeze all functions
    return function()
        local x = setmetatable({},MutexCls)
        table.freeze(x)
        _private[x] = setmetatable({},weaktbl)
        return x
    end
end
local newmutex = MutexModule()
local objtraits = {}
local __exobj = setmetatable({},{__mode="k"})
local exmt
exmt = {
    __newindex=function(t,k,v) error("frozen object") end,
    __metatable=false,
    __call=function(t,func)
        local tt = setmetatable({},exmt)
        __exobj[tt] = func
        return tt
    end,
    __tostring=function(t)
        return "executableobject"..tostring(__exobj[t]):sub(8,-1)
    end,

}
exmt.__index = exmt
local executableobject = setmetatable({},exmt)
objtraits.__index = objtraits
local function rawIsIn(tbl,v)
    for k,vv in pairs(tbl) do
        if rawequal(v,vv) then return k end
    end
    return nil
end
local function isExecutableObject(obj)
    return not rawequal(__exobj[obj],nil)
end
function objtraits:isADirectory()
    error("unimplemented")
end
function objtraits:getFullPath()
    local buf = ""
    local c = self
    if self.parent then 
        while true do
            if c.parent then
                buf = "/" .. c.name
                c = c.parent
            else break end
        end
        return buf
    else
        return "/"
    end
end
function objtraits:getPerms()
    return self.perms,self.owner
end
function objtraits:rename(name)
    error("unimplemented")
end
function objtraits:read(at,amount)
    error("unimplemented")
end
function objtraits:subread(name)
    error("unimplemented")
end
function objtraits:write(obj)
    error("unimplemented")
end
function objtraits:subwrite(name,obj)
    error("unimplemented")
end
function objtraits:append(obj,at)
    error("unimplemented")
end
function objtraits:access() --list dir
    error("unimplemented")
end
function objtraits:execute(args)
    error("unimplemented")
end
function objtraits:changeOwner(proc,newuser)
    if self.owner == proc.user or proc.user == "root" then
        self.owner = newuser
    end
end
function objtraits:changePerms(proc,newperms)
    if self.owner == proc.user or proc.user == "root" then
        self.perms = newperms
    end
end
function objtraits:canRead(proc,grouptbl)
    if proc.user == self.owner or proc.user == "root" then
        return self.perms:sub(1,1) == "r"
    else
        local t = false
        for groupname,group in pairs(grouptbl) do
            if rawIsIn(group,self.owner) then 
                if rawIsIn(group,proc.user) then
                    t = true
                    break;
                end
            end
        end
        if t then
            return self.perms:sub(4,4) == "r"
        else
            return self.perms:sub(7,7) == "r"
        end
    end
end
function objtraits:canWrite(proc,grouptbl)
    if proc.user == self.owner or proc.user == "root" then
        return self.perms:sub(2,2) == "w"
    else
        local t = false
        for groupname,group in pairs(grouptbl) do
            if rawIsIn(group,self.owner) then 
                if rawIsIn(group,proc.user) then
                    t = true
                    break;
                end
            end
        end
        if t then
            return self.perms:sub(5,5) == "w"
        else
            return self.perms:sub(8,8) == "w"
        end
    end
end
function objtraits:canExecute(proc,grouptbl)
    if proc.user == self.owner or proc.user == "root" then
        return self.perms:sub(3,3) == "x"
    else
        local t = false
        for groupname,group in pairs(grouptbl) do
            if rawIsIn(group,self.owner) then 
                if rawIsIn(group,proc.user) then
                    t = true
                    break;
                end
            end
        end
        if t then
            return self.perms:sub(6,6) == "x"
        else
            return self.perms:sub(9,9) == "x"
        end
    end
end
function objtraits:canAccess(proc,grouptbl)
    if proc.user == self.owner or proc.user == "root" then
        return self.perms:sub(3,3) == "a"
    else
        local t = false
        for groupname,group in pairs(grouptbl) do
            if rawIsIn(group,self.owner) then 
                if rawIsIn(group,proc.user) then
                    t = true
                    break;
                end
            end
        end
        if t then
            return self.perms:sub(6,6) == "a"
        else
            return self.perms:sub(9,9) == "a"
        end
    end
end
function objtraits:delete()
    error("unimplemented")
end
local function table_clone(t)
    local tt = {}
    for k,v in pairs(t) do
        tt[k] = v
    end
    return tt
end
local function newIsolatedRootfs(grouptbl,newProcess,getCurrentProc)
    local function rawIsIn(tbl,v)
		for k,vv in pairs(tbl) do
			if rawequal(v,vv) then return k end
		end
		return nil
	end
    local dirmt = setmetatable({},{__index=objtraits})
    local __dir = setmetatable({},{__mode="k"})
    dirmt.__index = dirmt
    function dirmt:changeOwner(newuser)
        local proc = getCurrentProc()
        if self.owner == proc.user or proc.user == "root" then
            self.owner = newuser
        end
    end
    function dirmt:changePerms(newperms)
        local proc = getCurrentProc()
        if self.owner == proc.user or proc.user == "root" then
            self.perms = newperms
        end
    end
    function dirmt:isADirectory()
        return true
    end
    function dirmt:subread(name)
        local proc = getCurrentProc()
        if objtraits.canRead(self,proc,grouptbl) then
            local c = __dir[self][name]
            if c then
                return c
            end
        end
        error("permission error")
    end
    function dirmt:subwrite(name,obj)
        local proc = getCurrentProc()
        if objtraits.canWrite(self,proc,grouptbl) then
            __dir[self][name] = obj
            return
        end
        error("permission error")
    end
    function dirmt:access()
        local proc = getCurrentProc()
        if objtraits.canAccess(self,proc,grouptbl) then
            local directory = {}
            for k,v in pairs(__dir[self]) do
                table.insert(directory,k)
            end
            return directory
        end
        error("permission error")
    end
    function dirmt:rename(newname)
        local proc = getCurrentProc()
        if proc.user == self.user or proc.user == "root" then
            if self.parent then
                __dir[self.parent][self.name] = nil
                __dir[self.parent][newname] = self
            end
            self.name = newname
            return
        end
        error("permission error")
    end
    function dirmt:execute(args)
        local proc = getCurrentProc()
        if objtraits.canExecute(self,proc,grouptbl) then
            error("not executable")
        end
        error("permission error")
    end
    function dirmt:canExecute()
        error("unimplemented")
    end
    function dirmt:canRead()
        local proc = getCurrentProc()
        return objtraits.canRead(self,proc,grouptbl)
    end
    function dirmt:canWrite()
        local proc = getCurrentProc()
        return objtraits.canWrite(self,proc,grouptbl)
    end
    function dirmt:canAccess()
        local proc = getCurrentProc()
        return objtraits.canAccess(self,proc,grouptbl)
    end
    function dirmt:delete()
        local proc = getCurrentProc()
        if proc.user == self.user or proc.user == "root" then
            __dir[self] = {}
            if self.parent then
                local k = rawIsIn(__dir[self.parent],self.name)
                if k then
                    __dir[self.parent][k] = nil
                end
            end
            return
        end
        error("permission error")
    end
    local function newDirectory(name,parentdir,owner,perms,void)
        local dir = setmetatable({
            name=name,
            parent=parentdir,
            owner=owner or "root",
            perms=perms or "rwarwarwa"
        },dirmt)
        __dir[dir] = {}
        if parentdir then
            if not void then table.insert(__dir[parentdir],dir) end
        end
        return dir
    end
    local execmt = setmetatable({},{__index=objtraits})
    local __exec = setmetatable({},{__mode="k"})
    execmt.__index = execmt
    function execmt:changeOwner(newuser)
        local proc = getCurrentProc()
        if self.owner == proc.user or proc.user == "root" then
            self.owner = newuser
        end
    end
    function execmt:changePerms(newperms)
        local proc = getCurrentProc()
        if self.owner == proc.user or proc.user == "root" then
            self.perms = newperms
        end
    end
    function execmt:isADirectory()
        return false
    end
    function execmt:read()
        local proc = getCurrentProc()
        if objtraits.canRead(self,proc,grouptbl) then
            return __exec[self]
        end
        error("permission error")
    end
    function execmt:write(func)
        local proc = getCurrentProc()
        assert(type(func) == "function","func must be a function")
        if objtraits.canWrite(self,proc,grouptbl) then
            __exec[self] = executableobject(func)
            return
        end
        error("permission error")
    end
    function execmt:execute(args)
        local proc = getCurrentProc()
        args = args or {}
        if objtraits.canExecute(self,proc,grouptbl) then
            local start,sigh,__kill = __exobj[__exec[self]]()
            local args = table_clone(args)
            local nn = self:getFullPath()
            table.insert(args,1,nn)
            local np = newProcess(nn,start,proc.stdin,proc.stdout,proc.stderr,sigh,__kill,proc,proc.user)
            np.argv = args
            return np
        end
        error("permission error")
    end
    function execmt:rename(newname)
        local proc = getCurrentProc()
        if proc.user == self.user or proc.user == "root" then
            if self.parent then
                __dir[self.parent][self.name] = nil
                __dir[self.parent][newname] = self
            end
            self.name = newname
            return
        end
        error("permission error")
    end
    function execmt:canRead()
        local proc = getCurrentProc()
        return objtraits.canRead(self,proc,grouptbl)
    end
    function execmt:canWrite()
        local proc = getCurrentProc()
        return objtraits.canWrite(self,proc,grouptbl)
    end
    function execmt:canAccess()
        error("not implemented")
    end
    function execmt:canExecute()
        local proc = getCurrentProc()
        return objtraits.canExecute(self,proc,grouptbl)
    end
    function execmt:delete()
        local proc = getCurrentProc()
        if proc.user == self.user or proc.user == "root" then
            if self.parent then
                local k = rawIsIn(__dir[self.parent],self.name)
                if k then
                    __dir[self.parent][k] = nil
                end
            end
            return
        end
        error("permission error")
    end
    local function newExecutable(func,name,parentdir,owner,perms,void)
        assert(type(func) == "function","func must be a function")
        local excv = setmetatable({
            name=name,
            parent=parentdir,
            owner=owner or "root",
            perms=perms or "rwxrwxrwx"
        },execmt)
        __exec[excv] = executableobject(func)
        if parentdir then
            if not void then table.insert(__dir[parentdir],excv) end
        end
        return excv
    end
    local filemt = setmetatable({},{__index=objtraits})
    local __file = setmetatable({},{__mode="k"})
    filemt.__index = filemt
    function filemt:changeOwner(newuser)
        local proc = getCurrentProc()
        if self.owner == proc.user or proc.user == "root" then
            self.owner = newuser
        end
    end
    function filemt:changePerms(newperms)
        local proc = getCurrentProc()
        if self.owner == proc.user or proc.user == "root" then
            self.perms = newperms
        end
    end
    function filemt:isADirectory()
        return false
    end
    function filemt:read(at,amount)
        local proc = getCurrentProc()
        if objtraits.canRead(self,proc,grouptbl) then
            if (at == nil) and (amount == nil) then return __file[self]
            else
                return __file[self]:sub(at+1,at+1+amount)
            end
        end
        error("permission error")
    end
    function filemt:write(str)
        local proc = getCurrentProc()
        if objtraits.canWrite(self,proc,grouptbl) then
            __file[self] = str
            return
        end
        error("permission error")
    end
    function filemt:append(str,at)
        local proc = getCurrentProc()
        if objtraits.canWrite(self,proc,grouptbl) then
            if at == nil then
                __file[self] = __file[self]..str
            else
                __file[self] = __file[self]:sub(1,at+1)..str..__file[self]:sub(at+1+#str,-1)
                return
            end
        end
        error("permission error")
    end
    function filemt:rename(newname)
        local proc = getCurrentProc()
        if proc.user == self.user or proc.user == "root" then
            if self.parent then
                __dir[self.parent][self.name] = nil
                __dir[self.parent][newname] = self
            end
            self.name = newname
            return
        end
        error("permission error")
    end
    function filemt:execute(args)
        local proc = getCurrentProc()
        if objtraits.canExecute(self,proc,grouptbl) then
            error("not executable")
        end
        error("permission error")
    end
    function filemt:canRead()
        local proc = getCurrentProc()
        return objtraits.canRead(self,proc,grouptbl)
    end
    function filemt:canWrite()
        local proc = getCurrentProc()
        return objtraits.canWrite(self,proc,grouptbl)
    end
    function filemt:canAccess()
        error("not implemented")
    end
    function filemt:canExecute()
        local proc = getCurrentProc()
        return objtraits.canExecute(self,proc,grouptbl)
    end
    function filemt:delete()
        local proc = getCurrentProc()
        if proc.user == self.user or proc.user == "root" then
            if self.parent then
                local k = rawIsIn(__dir[self.parent],self.name)
                if k then
                    __dir[self.parent][k] = nil
                end
            end
            return
        end
        error("permission error")
    end
    local function newFile(file,name,parentdir,owner,perms,void)
        local excv = setmetatable({
            name=name,
            parent=parentdir,
            owner=owner or "root",
            perms=perms or "rwxrwxrwx"
        },filemt)
        __file[excv] = file or ""
        if parentdir then
            if not void then table.insert(__dir[parentdir],excv) end
        end
        return excv
    end
    local streamt = setmetatable({},{__index=objtraits})
    local __stream = setmetatable({},{__mode="k"})
    streamt.__index = streamt
    function streamt:changeOwner(newuser)
        local proc = getCurrentProc()
        if self.owner == proc.user or proc.user == "root" then
            self.owner = newuser
        end
    end
    function streamt:changePerms(newperms)
        local proc = getCurrentProc()
        if self.owner == proc.user or proc.user == "root" then
            self.perms = newperms
        end
    end
    function streamt:isADirectory()
        return false
    end
    function streamt:read(at,amount)
        local proc = getCurrentProc()
        if objtraits.canRead(self,proc,grouptbl) then
            __stream[self].mutex:lock()
            local nerr,s = pcall(function()
                __stream[self]:seek(at)
                local s = __stream[self]:read(amount)
                __stream[self]:close()
                return s
            end)
            __stream[self].mutex:unlock()
            if nerr then
                return s
            else
                error("an error occured while reading stream")
            end
        end
        error("permission error")
    end
    function streamt:write(str)
        local proc = getCurrentProc()
        if objtraits.canWrite(self,proc,grouptbl) then
            __stream[self].mutex:lock()
            local nerr,s = pcall(function()
                __stream[self]:write(str)
                __stream[self]:close()
            end)
            __stream[self].mutex:unlock()
            if not nerr then
                error("an error occured while writing stream")
            end
            return
        end
        error("permission error")
    end
    function streamt:execute()
        local proc = getCurrentProc()
        if objtraits.canExecute(self,proc,grouptbl) then
            error("not executable")
        end
        error("permission error")
    end
    function streamt:append(obj,at)
        local proc = getCurrentProc()
        if objtraits.canWrite(self,proc,grouptbl) then
            __stream[self].mutex:lock()
            local nerr,s = pcall(function()
                __stream[self]:seek(at)
                __stream[self]:write(obj)
                __stream[self]:close()
            end)
            __stream[self].mutex:unlock()
            if not nerr then
                error("an error occured while writing stream")
            end
            return
        end
        error("permission error")
    end
    function streamt:rename(newname)
        local proc = getCurrentProc()
        if proc.user == self.user or proc.user == "root" then
            if self.parent then
                __dir[self.parent][self.name] = nil
                __dir[self.parent][newname] = self
            end
            self.name = newname
            return
        end
        error("permission error")
    end
    function streamt:canRead()
        local proc = getCurrentProc()
        return objtraits.canRead(self,proc,grouptbl)
    end
    function streamt:canWrite()
        local proc = getCurrentProc()
        return objtraits.canWrite(self,proc,grouptbl)
    end
    function streamt:canAccess()
        error("not implemented")
    end
    function streamt:canExecute()
        local proc = getCurrentProc()
        return objtraits.canExecute(self,proc,grouptbl)
    end
    function streamt:delete()
        local proc = getCurrentProc()
        if proc.user == self.user or proc.user == "root" then
            if self.parent then
                local k = rawIsIn(__dir[self.parent],self.name)
                if k then
                    __dir[self.parent][k] = nil
                end
            end
            return
        end
        error("permission error")
    end
    local function newStreamFile(stream,name,parentdir,owner,perms,void)
        local excv = setmetatable({
            name=name,
            parent=parentdir,
            owner=owner or "root",
            perms=perms or "rwxrwxrwx"
        },streamt)
        __stream[excv] = setmetatable(table.clone(stream),genstreamfuncs)
        __stream[excv].mutex = newmutex()
        if parentdir then
            if not void then table.insert(__dir[parentdir],excv) end
        end
        return excv
    end
    local streamdirmt = setmetatable({},{__index=objtraits})
    local __streamdir = setmetatable({},{__mode="k"})
    streamdirmt.__index = streamdirmt
    function streamdirmt:changeOwner(newuser)
        local proc = getCurrentProc()
        if self.owner == proc.user or proc.user == "root" then
            self.owner = newuser
        end
    end
    function streamdirmt:changePerms(newperms)
        local proc = getCurrentProc()
        if self.owner == proc.user or proc.user == "root" then
            self.perms = newperms
        end
    end
    function streamdirmt:isADirectory()
        return true
    end
    function streamdirmt:subread(name)
        local proc = getCurrentProc()
        if objtraits.canRead(self,proc,grouptbl) then
            return __streamdir[self]("r",name)
        end
        error("permission error")
    end
    function streamdirmt:subwrite(name,obj)
        local proc = getCurrentProc()
        if objtraits.canWrite(self,proc,grouptbl) then
            return __streamdir[self]("w",name,obj)
        end
        error("permission error")
    end
    function streamdirmt:access()
        local proc = getCurrentProc()
        if objtraits.canAccess(self,proc,grouptbl) then
            return __streamdir[self]("a")
        end
        error("permission error")
    end
    function streamdirmt:rename(newname)
        local proc = getCurrentProc()
        if proc.user == self.user or proc.user == "root" then
            if self.parent then
                __dir[self.parent][self.name] = nil
                __dir[self.parent][newname] = self
            end
            self.name = newname
            return
        end
        error("permission error")
    end
    function streamdirmt:canExecute()
        error("unimplemented")
    end
    function streamdirmt:canRead()
        local proc = getCurrentProc()
        return objtraits.canRead(self,proc,grouptbl)
    end
    function streamdirmt:canWrite()
        local proc = getCurrentProc()
        return objtraits.canWrite(self,proc,grouptbl)
    end
    function streamdirmt:canAccess()
        local proc = getCurrentProc()
        return objtraits.canAccess(self,proc,grouptbl)
    end
    function streamdirmt:delete()
        local proc = getCurrentProc()
        if proc.user == self.user or proc.user == "root" then
            if self.parent then
                local k = rawIsIn(__dir[self.parent],self.name)
                if k then
                    __dir[self.parent][k] = nil
                end
            end
            return
        end
        error("permission error")
    end
    local function newStreamDirectory(stream,name,parentdir,owner,perms,void)
        local excv = setmetatable({
            name=name,
            parent=parentdir,
            owner=owner or "root",
            perms=perms or "rwxrwxrwx"
        },streamdirmt)
        __streamdir[excv] = stream
        if parentdir then
            if not void then table.insert(__dir[parentdir],excv) end
        end
        return excv
    end
    --return rootfs and commands
    return newDirectory("",nil,"root","rwar-ar-a"),{
        newDirectory=newDirectory,
        newExecutable=newExecutable,
        newFile=newFile,
        newStreamFile,newStreamFile,
        newStreamDirectory=newStreamDirectory
    }
end
local signals = {
	SIGABRT=1,
	SIGALRM=2,
	SIGHUP=3,
	SIGINT=4,
	SIGTSTP=5,
	SIGTERM=6,
	SIGSTOP=7,
	SIGCONT=8,
	SIGKILL=9,
	SIGCHLD=10
}
local rsignals = {}
for k,v in pairs(signals) do rsignals[v] = k end
local dsignals = {
	"Aborted",
	"Alarm interrupt",
	"Hanged up",
	"Interrupted",
	"Terminal stop",
	"Terminated",
	"Stopped",
	"Continue execution",
	"Killed",
	"Child check"
}
local proc_states = {
	I="initialized",
	R="running",
	Z="zombie",
	D="dead",
	S="stopped"
}
local function newIsolatedProcessTable()
	local processes = {}
	local processesthr = setmetatable({},{__mode="kv"})
	local grouptbl = {
		root={"root"}
	}
	setmetatable(grouptbl,{
		__index=function(t,i)
			t[i] = {}
			return t[i]
		end
	})
	local processmt = {}
	processmt.__index = processmt
	function processmt:sendSignal(sig)
		if self.state == "I" then
			if sig == signals.SIGKILL or sig == signals.SIGTERM or sig == signals.SIGABRT or sig == signals.SIGHUP then
				self.thr = nil
				self.sigexit = true
				self.state = "Z"
				self.stdin = newStream()
				self.stdout = newStream()
				self.stderr = newStream()
				self.retcode = sig
			end
		elseif self.state ~= "R" and self.state ~= "S" then return end
		if sig == signals.SIGKILL then
			self.sigexit = true
			self.state = "Z"
			self.stdin = newStream()
			self.stdout = newStream()
			self.stderr = newStream()
			self.retcode = sig
			coroutine.wrap(function(s)
				processesthr[coroutine.running()] = s
				if s.__kill then
					pcall(s.__kill)(s)
				end
				self.sigh = {}
				for _,p in ipairs(s.children) do
					p:kill()
					p:destroy()
				end
				if s.parent then
					s.parent:sendSignal(signals.SIGCHLD)
				end
			end)(self)
		else
			local f = self.sigh[sig]
			if f then
				local thr = coroutine.create(f)
				processesthr[thr] = self
				coroutine.resume(self)
			else
				--terminating?
				if sig == signals.SIGABRT or sig == signals.SIGHUP or sig == signals.SIGINT or sig == signals.SIGTERM then
					self.sigexit = true
					self.state = "Z"
					self.stdin = newStream()
					self.stdout = newStream()
					self.stderr = newStream()
					self.retcode = sig
					coroutine.wrap(function(s)
						processesthr[coroutine.running()] = s
						if s.__kill then
							s.__kill(s)
						end
						self.sigh = {}
						for _,p in ipairs(s.children) do
							p:kill()
							p:destroy()
						end
						if s.parent then
							s.parent:sendSignal(signals.SIGCHLD)
						end
					end)(self)
				elseif sig == signals.SIGCHLD then
					for _,p in ipairs(self.children) do
						if p.state == "Z" then
							p:kill()
						end
					end
				end
			end
		end
	end
	function processmt:ret(retcode)
		self.state = "Z"
		self.stdin = newStream()
		self.stdout = newStream()
		self.stderr = newStream()
		self.retcode = retcode
		coroutine.wrap(function(s)
			if s.__kill then
				s.__kill(s)
			end
			self.sigh = {}
			for _,p in ipairs(s.children) do
				p:kill()
				p:destroy()
			end
			if s.parent then
				s.parent:sendSignal(signals.SIGCHLD)
			end
		end)(self)
	end
	function processmt:pause()
		self:sendSignal(signals.SIGSTOP)
	end
	function processmt:resume()
		self:sendSignal(signals.SIGCONT)
	end
	function processmt:interrupt()
		self:sendSignal(signals.SIGINT)
	end
	function processmt:terminate()
		self:sendSignal(signals.SIGTERM)
	end
	function processmt:kill()
		self:sendSignal(signals.SIGKILL)
	end
	function processmt:abort()
		self:sendSignal(signals.SIGABRT)
	end
	function processmt:destroy()
		if self.state == "Z" then
			self.state = "D"
			processes[self.pid] = nil
			self.children = {}
			self.proctbl = nil
		end
	end
	function processmt:start()
		if self.state == "I" then
			coroutine.resume(self.thr,self)
			self.state = "R"
		end
	end
	function processmt:attachThr(thr)
		--current thread must be trusted!
		if rawequal(processesthr[coroutine.running()],self) then
			processesthr[thr] = self
		else
			error("access denied")
		end
	end
	function processmt:getEnv(var)
		if rawequal(processesthr[coroutine.running()],self) then
			local v = self.privenv[var]
			if v then return v end
		end
		return self.pubenv[var]
	end
	local function rawIsIn(tbl,v)
		for k,vv in pairs(tbl) do
			if rawequal(v,vv) then return k end
		end
		return nil
	end
	local function newProcess(name,func,stdin,stdout,stderr,sigh,__kill,parent,user)
		stdin = stdin or parent.stdin or newStream()
		stdout = stdout or parent.stdout or newStream()
		stderr = stderr or parent.stderr or newStream()
		__kill = __kill or sigh[signals.SIGKILL]
		parent = parent or processes[1]
		user = user or "root"
		local process = setmetatable({
			state = "I",
			pid = math.random(65536),
			name = name,
			sigh = sigh,
			stdin = stdin,
			stdout = stdout,
			stderr = stderr,
			thr = coroutine.create(func),
			parent = parent,
			children = {},
			sigexit = false,
			pubenv = table.clone((parent or {}).pubenv or {}),
			privenv = {},
			proctbl = processes,
			argv = {name},
			user = user,
			__kill = __kill
		},processmt)
		processesthr[process.thr] = process
		table.insert((parent or {}).children or {},process)
		processes[process.pid] = process
		processesthr[process.thr] = process
		return process
	end
	return {
		processtable=processes,
		newProcess=newProcess,
		grouptbl=grouptbl,
		processesthr=processesthr,
		isInGroup=function(groupname,username)
			return rawIsIn(grouptbl[groupname],username)
		end,
		getCurrentProc=function()
			return processesthr[coroutine.running()]
		end
	}
end
local function newTerm(devname,user,prompt,stdinf,stdoutf,stderrf,termname,pr,rootdir,du,procparent)
	--command: (argv,stdin,stdout,stderr) -> process not running
	local stdin = newStdIn(stdinf)
	local stdout = newStdOut(stdoutf)
	local stderr = newStdOut(stderrf)
	local processtbl,newProcess,grouptbl,processesthr = pr.processtable,pr.newProcess,pr.grouptbl,pr.processesthr
	local bindir
	local newDirectory,newStreamFile = du.newDirectory,du.newStreamFile
	--[[
	local devdir = rootdir:subread({user="root"},"dev")
	local tty = newStreamFile(newStreamGen(function(op,arg)
		if op == "w" then
			stdout:write(arg)
		elseif op == "r" then
			if arg == -1 then
				return stdin:readAll()
			else 
				return stdin:read(arg)
			end
		end
	end),ttyname,devdir,"root","rw-rw-rw-")]]--
	local commandbuffer = ""
	local jobs = {}
	local isnext = false
	--DC1 - color nbgcrmywNBGCRMYW
	--DC2 - bB - blinking, fF - setting foreground color or background, eE - echo, 12 - stdout,stderr
	local waitingon = nil
	local function next(proc)
		local prompt = proc:getEnv("PS1")
		local splitted = into_chars(prompt)
		local escape = 0
		local buf = ""
		for _,c in ipairs(splitted) do
			if escape == 0 then
				if c == "\\" then
					escape = 1
				else
					buf = buf .. c
				end
			elseif escape == 1 then
				if c == "l" or c == "h" then
					escape = 0
					buf = buf .. proc:getEnv("HOSTNAME")
				elseif c == "u" then
					escape = 0
					buf = buf .. proc:getEnv("USER")
				elseif c == "$" then
					escape = 0
					buf = buf .. ({[false]='$',[true]='#'})[proc:getEnv("USER") == "root"]
				elseif c == "j" then
					escape = 0
					buf = buf .. tostring(#jobs)
				elseif c == "s" then
					escape = 0
					buf = buf .. termname
				elseif c == "c" then
					escape = 2 --color
				else escape = 0
				end
			else
				buf = buf .. string.char(17) .. c
				escape = 0
			end
		end
		stdout:write(buf)
	end
	local function start(proc)
		proc.pubenv.USER = user
		proc.pubenv.HOSTNAME = devname
		proc.pubenv.PS1 = prompt
		stdout:write(string.char(18).."B")
		--[[
		--set as init
		if processtbl[1] then 
			coroutine.wrap(proc.sendSignal)(proc,signals.SIGKILL)
			error("can't start when process table already has init")
		end
		processtbl[proc.pid] = nil
		processtbl[1] = proc
		proc.pid = 1
		]]--
		local c,bindirtry = pcall(rootdir.subread)(rootdir,"bin")
		if not c then
			stderr:write("cannot open bin dir\n")
			self:ret(1)
		else
			bindir = bindirtry
			next(proc)
		end
		--what am i supposed to do?
	end

	return newProcess(termname .. "",start,stdin,stdout,stderr,{
		[signals.SIGKILL]=function(proc)
			waitingon = nil
			jobs = {}
		end,
		[signals.SIGINT]=function(proc) 
			commandbuffer = ""
			stdout:write("\n")
			next(proc)
		end,
		[signals.SIGTSTP]=function(proc)
			if waitingon then
				waitingon:sendSignal(signals.SIGTSTP)
			end
		end,
		[signals.SIGALRM]=function(proc)
			if waitingon then
				if waitingon.state == "Z" then
					if waitingon.sigexit then
						stderr:write(dsignals[waitingon.retcode])
						stdout:write("\n")
						next(proc)
						waitingon:destroy()
						waitingon = nil
					else
						if waitingon.retcode ~= 0 then
							stderr:write("Exited with code "..tostring(waitingon.retcode))
						end
						stdout:write("\n")
						next(proc)
						waitingon:destroy()
						waitingon = nil
					end
				end
			else
				--fetching commands
				local b = stdin:readAll()
				if #b == 0 and not isnext then return end
				local t = false
				commandbuffer = commandbuffer .. b
				for _,c in ipairs(into_chars(commandbuffer)) do
					if c == "\n" then t = true break end
				end
				if t then
					--find first
					local i = string.find(commandbuffer,"\n",1,true)
					local c = commandbuffer:sub(0,i)
					commandbuffer = commandbuffer:sub(i,-1)
					isnext = string.find(commandbuffer,"\n",1,true)
					--do c
					local w,argv = pcall(huge_split)(c)
					if not w then
						stderr:write(argv)
						stdout:write("\n")
						next(proc)
					end
					local err,command = pcall(bindir.subread)(bindir,c)
					if not err then
						stderr:write(err .. "\n")
						next(proc)
					else
						if command then
							local _argv = {}
							for i,v in ipairs(argv) do
								if i ~= 1 then
									_argv[i - 1] = v
								end
							end
							local err,np = pcall(command.execute)(command,_argv)
							if not err then
								stderr:write(err .. "\n")
								next(proc)
							else
								np:start()
								waitingon = np
							end
						else
							stderr:write("command not found\n")
							next(proc)
						end
					end
				end
			end
		end,
		[signals.SIGCHLD]=function(proc)
			if waitingon then
				if waitingon.state == "Z" then
					if waitingon.sigexit then
						stderr:write(dsignals[waitingon.retcode])
						stdout:write("\n")
						next(proc)
						waitingon:destroy()
						waitingon = nil
					else
						if waitingon.retcode ~= 0 then
							stderr:write("Exited with code "..tostring(waitingon.retcode))
						end
						stdout:write("\n")
						next(proc)
						waitingon:destroy()
						waitingon = nil
					end
				end
			end
		end
	},nil,procparent,user),function() return waitingon end
end
local function newSystem(devname,stdinf,stdoutf,stderrf) --> init proc, kernel API
	stdoutf("[0.00000] [kernel] initializing")
	local ti = os.clock()
	local function rawIsIn(t,v)
		for k,bb in pairs(t) do
			if rawequal(bb,v) then return k end
		end
	end
	--create proc table
	local pr = newIsolatedProcessTable()
	local krnlprocplaceholder = {
		user="root"
	}
	--create filesystem
	stdoutf("\n[" .. string.format("%.5f",os.clock()-ti) .."] [scsi] starting disk")
	local rootdir,du = newIsolatedRootfs(pr.grouptbl,pr.newProcess,pr.getCurrentProc)
	--load macros
	local 
	 newDirectory,newExecutable,newFile,newStreamFile,newProcess,getCurrentProc,processesthr,newStreamDirectory,isInGroup
	 = du.newDirectory,du.newExecutable,du.newFile,du.newStreamFile,pr.newProcess,pr.getCurrentProc,pr.processesthr,du.newStreamDirectory,pr.isInGroup
	local processtable = pr.processtable
	processesthr[coroutine.running()] = krnlprocplaceholder
	task.wait(0.3)
	stdoutf("\n[" .. string.format("%.5f",os.clock()-ti) .."] [fs] mounting /dev/sda1")
	local devdir = newDirectory("dev",rootdir,nil,"rwarwar-a")
	local bindir = newDirectory("bin",rootdir,nil,"rwarwar-a")
	local sbindir = newDirectory("sbin",rootdir,nil,"rwarwa---")
	local etcdir = newDirectory("etc",rootdir,nil,"rwarwar-a")
	local hostname = newFile(devname,"hostname",etcdir,nil,"rw-rw-r--")
	local procdir
	local powerdown = false
	local powerdownhooks = {}
	local sysreboot,syspoweroff,syshalt
	local function newProcDir(process)
		local pru = process.user
		local ro = "r--r--r--"
		local rw = "rw-rw-rw-"
		local wo = "-w--w--w-"
		local prc = newDirectory(tostring(process.pid),procdir,pru,"r-ar-ar-a",false)
		newStreamFile(newStreamGen(function(op,arg)
			if op == "r" then
				if arg == 0 then
					return ""
				end
				return process.state
			end
		end),"state",prc,pru,ro)
		newFile(tostring(process.pid),"pid",prc,pru,ro)
		newFile(tostring(process.name),"name",prc,pru,ro)
		newStreamFile(process.stdin,"stdin",prc,pru,rw)
		newStreamFile(process.stdout,"stdout",prc,pru,rw)
		newStreamFile(process.stderr,"stderr",prc,pru,rw)
		newFile(pru,"user",prc,pru,ro)
		newStreamFile(newStreamGen(function(op,arg)
			if op == "w" then
				process:sendSignal(arg)
			end
		end),"signal",prc,pru,"-w--w----")
		newStreamFile(newStreamGen(function(op,arg)
			if op == "r" then
				return process.argv
			end
		end),"argv",prc,pru,ro)
		return prc
	end
	local function newSysrqTrigger()
		return newStreamFile(newStdOut(function(a)
			for _,c in ipairs(into_chars(a)) do
				if c == "o" then
					syspoweroff()
				elseif c == "b" then
					sysreboot()
				elseif c == "c" then
					syshalt()
				end
			end
		end),"sysrq-trigger",procdir,nil,"-w--w----")
	end
	procdir = newStreamDirectory(function(op,name,objtow)
		if op == "r" then
			if name == "self" then
				local p = getCurrentProc()
				if not p then return end
				return newProcDir(processtable[p])
			elseif name == "sysrq-trigger" then
				return newSysrqTrigger()
			elseif processtable[name] then
				return newProcDir(processtable[name])
			end
		elseif op == "a" then
			local dir = {"sysrq-trigger"}
			if getCurrentProc() then
				table.insert(dir,"self")
			end
			for k,_ in pairs(processtable) do
				table.insert(dir,k)
			end
			return dir
		else
			error("unknown operation")
		end
	end,"proc",rootdir,nil,"r-ar-ar-a")
	local roothomedir = newDirectory("root",rootdir,nil,"rwarwa---")
	newStreamFile(function(op,arg)
		local proc = getCurrentProc()
		return propagateStream(proc.stdin,op,arg)
	end,"stdin",devdir,nil,"rw-rw-rw-")
	newStreamFile(function(op,arg)
		local proc = getCurrentProc()
		return propagateStream(proc.stdout,op,arg)
	end,"stdout",devdir,nil,"rw-rw-rw-")
	newStreamFile(function(op,arg)
		local proc = getCurrentProc()
		return propagateStream(proc.stderr,op,arg)
	end,"stderr",devdir,nil,"rw-rw-rw-")
	local stdin = newStreamGen(stdinf)
	local stdout = newStreamGen(stdoutf)
	local stderr = newStreamGen(stderrf)
	stdoutf("\n[" .. string.format("%.5f",os.clock()-ti) .."] [kernel] loading init")
	local function findGroupsOfUser(group,user)
		local gs = {}
		for gn,g in pairs(pr.grouptbl) then
			if rawisIn(g,user) then
				table.insert(gs,gn)
			end
		end
		return gs
	end
	local function isInRootGroup(user)
		return rawIsIn(pr.grouptbl.root,user)
	end
	function syspoweroff()
		if powerdown then return end
		powerdown = true
		if processtable[1] then
			processtable[1]:kill()
		end
		stdoutf("\n[" .. string.format("%.5f",os.clock()-ti) .."] [fs] unmounting /dev/sda1")
		task.wait(0.4)
		stdoutf("\n[" .. string.format("%.5f",os.clock()-ti) .."] [scsi] stopping disk")
		task.wait(1)
		stdoutf("\n[" .. string.format("%.5f",os.clock()-ti) .."] [kernel] shutting down")
		task.wait(1)
		for _,f in ipairs(powerdownhooks) do
			coroutine.wrap(f)("poweroff")
		end
	end
	function syshalt()
		if powerdown then return end
		powerdown = true
		if processtable[1] then
			processtable[1]:kill()
		end
		stdoutf("\n[" .. string.format("%.5f",os.clock()-ti) .."] [fs] unmounting /dev/sda1")
		task.wait(0.4)
		stdoutf("\n[" .. string.format("%.5f",os.clock()-ti) .."] [scsi] stopping disk")
		task.wait(1)
		stdoutf("\n[" .. string.format("%.5f",os.clock()-ti) .."] [kernel] system halted")
		for _,f in ipairs(powerdownhooks) do
			coroutine.wrap(f)("halt")
		end
	end
	function sysreboot()
		if powerdown then return end
		powerdown = true
		if processtable[1] then
			processtable[1]:kill()
		end
		stdoutf("\n[" .. string.format("%.5f",os.clock()-ti) .."] [fs] unmounting /dev/sda1")
		task.wait(0.4)
		stdoutf("\n[" .. string.format("%.5f",os.clock()-ti) .."] [kernel] rebooting")
		task.wait(0.1)
		for _,f in ipairs(powerdownhooks) do
			coroutine.wrap(f)("reboot")
		end
	end
	local function initStart(proc)

	end
	local initSignalHandles = {
		[signals.SIGKILL]=function(self)
			if not powerdown then
				stderrf("\n[system panic: attempt to kill init!]")
				for _,p in ipairs(self.children) do
					coroutine.wrap(pcall)(p.kill,p)
					p.state = "Z"
					p:destroy()
				end
				for k,p in pairs(processtable) do
					if k ~= 1 then 
						coroutine.wrap(pcall)(p.kill,p)
						p.state = "Z"
						p:destroy()
					end
				end
				self.state = "Z"
				self:destroy()
				syshalt()
			else
				for _,p in ipairs(self.children) do
					coroutine.wrap(pcall)(p.kill,p)
					p.state = "Z"
					p:destroy()
				end
				for k,p in pairs(processtable) do
					if k ~= 1 then 
						coroutine.wrap(pcall)(p.kill,p)
						p.state = "Z"
						p:destroy()
					end
				end
				self.state = "Z"
				self:destroy()
			end
		end,
		[signals.SIGTERM]=function(proc) end,
		[signals.SIGINT]=function(proc) end,
		[signals.SIGCHLD]=function(proc)
			for _,p in ipairs(proc.children) do
				if p.state == "Z" then
					p:destroy()
				end
			end
		end,
		[signals.SIGHUP]=function(proc) end,
		[signals.SIGABRT]=function(proc) end
	}
	local function newInit() return initStart,nil,initSignalHandles end
	local code = nil
	local function epoinit(proc)
		if isInRootGroup(proc.user) then
			syspoweroff()
		end
		if not code then proc:ret(19) -- access denied
		else
			proc.stdout:write("Code:")
			proc.privenv.code = ""
		end
	end

	local function newEpo()
		return epoinit,{
			[signals.SIGALRM]=function(proc)
				if proc.privenv.code then
					local c = nil
					while c ~= "" do
						c = stdin:read(1)
						if c == "\n" then
							if proc.privenv.code == code then
								stdout:write("Emergency poweroff.")
								syspoweroff()
								return
							else
								stderr:write("Invalid code.\n")
								proc:ret(19)
								return
							end
						else
							proc.privenv.code = proc.privenv.code .. c
						end
					end
				end
			end
		}
	end
	newExecutable(newEpo,"epo",bindir,nil,"rwxrwxr-x")
	local initfile = newExecutable(newInit,"init",sbindir,nil,"rwxrw----")
	local ip = initfile:execute()
	ip.pid = 1
	ip.stdin = newStdIn(stdinf)
	ip.stdout = newStdOut(stdoutf)
	ip.stderr = newStdOut(stderrf)
	return ip,{
		syspoweroff = syspoweroff,
		syshalt = syshalt,
		sysreboot = sysreboot,
		stdin=stdin,
		stdout=stdout,
		stderr=stderr,
		setEPOCode=function(codetoset)
			code = codetoset
		end
		reProcAnyRoot=function()
			pr.processesthr[coroutine.running()]={user="root"}
		end
		powerdownhook=function(f)
			--function (action) -> ?
			table.insert(powerdownhooks,f)
		end,
		newProcess = pr.newProcess,
		addUserInGroup = function(group,user)
			if not rawIsIn(group,user) then
				table.insert(group,user)
			end
		end,
		removeUserFromGroup = function(group,user)
			local k = rawIsIn(group,user)
			if k then
				table.remove(group,k)
			end
		end,
		findGroupsOfUser = findGroupsOfUser,
		isInGroup = isInGroup,
		pr = pr,
		grouptable = pr.grouptbl,
		ProcessThreads = pr.processesthr,
		isInGroup=pr.isInGroup,
		getCurrentProc=pr.getCurrentProc,
		du=du,
		rootDirectory = rootdir,
		newDirectory = du.newDirectory,
		newExecutable = du.newExecutable,
		newFile = du.newFile,
		newStreamFile = du.newStreamFile,
		newStreamDirectory = du.newStreamDirectory,
		devdir = devdir,
		state = function()
			if powerdown == false then
				return "Running"
			end
			return "Offline"
		end
	}
end
return {
    newStream=newStream,
    newStreamGen=newStreamGen,
    newStdIn=newStdIn,
    newStdOut=newStdOut,
    propagateStream=propagateStream,
    isExecutableObject=isExecutableObject,
    newIsolatedRootfs=newIsolatedRootfs,
    newIsolatedProcessTable=newIsolatedProcessTable,
    signals=signals,
    rsignals=rsignals,
    dsignals=dsignals,
    proc_states=proc_states,
    newTerm=newTerm,
    newSystem=newSystem,
    newmutex=newmutex
}
