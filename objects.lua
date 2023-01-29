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
            if __dir[self][name] ~= nil then
                __dir[self][name].parent = nil
            end
            __dir[self][name] = obj
            obj.parent = self
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
    function execmt:read(at,amount)
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
    function execmt:execute(args,rawargs)
        local proc = getCurrentProc()
        args = args or {}
        if objtraits.canExecute(self,proc,grouptbl) then
            local start,sigh,__kill = __exobj[__exec[self]]()
            local args = table_clone(args)
            local nn = self:getFullPath()
            if not rawargs then table.insert(args,1,nn) end
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
                at = at or 0
                at = at + 1
                if amount == -1 then
                    return __file[self]:sub(at,-1)
                else
                    return __file[self]:sub(at,at+amount)
                end
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
        at = at or 1
        amount = amount or -1
        local proc = getCurrentProc()
        if objtraits.canRead(self,proc,grouptbl) then
            __stream[self].mutex:lock()
            local nerr,s = pcall(function()
                __stream[self]:seek(at)
                local s
                if amount == -1 then
                    s = __stream[self]:readAll()
                else
                    s = __stream[self]:read(amount)
                end
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