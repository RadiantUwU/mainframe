local _processdata = setmetatable({},{__mode="k"})
local SignalReversed = {
    "SIGHUP",    -- Hangup, request to disconnect streams or notification of streams disconnecting
    "SIGINT",    -- Interrupt, equivalent of CTRL C
    "SIGQUIT",   -- Request to quit/exit
    "SIGILL",    -- Unused, critical, ill-formed instruction
    "SIGTRAP",   -- Unused, critical, meant to get called when debugging instuction by instruction
    "SIGABRT",   -- Abort execution,critical,an error occured and it cannot recover
    "SIGBUS",    -- Unused, critical
    "SIGFPE",    -- Unused, critical
    "SIGKILL",   -- Forcefully kill a process, critical, cannot be handled
    "SIGUSR1",   -- User signal
    "SIGSEGV",   -- Segmentation fault,critical, invalid memory access
    "SIGUSR2",   -- User signal
    "SIGPIPE",   -- Attempt to pipe to a process that no longer listens
    "SIGALRM",   -- Alarm, used when alarm() is called to wait, and timer elapses
    "SIGTERM",   -- Terminate, critical
    "SIGSTKFLT", -- Unused, critical, meant to signal a stack fault
    "SIGCHLD",   -- Child process changed, doesnt get called on creation
    "SIGCONT",   -- Continue process, can be handled
    "SIGSTOP",   -- Pause process, cannot be handled
    "SIGTSTP",   -- Terminal pause, USER asks for process to pause
    "SIGTTIN",   -- Attempt to read from terminal while in background
    "SIGTTOU",   -- Attempt to write to terminal while in background
    "SIGURG",    -- Unused, socket has urgent or out of band data to read
    "SIGXCPU",   -- Unused, time elapsed to use CPU, if it continues while handling signal process is killed
    "SIGXFSZ",   -- Sent to a process when it grows a file larger than the maximum allowed size.
    "SIGVTALRM", -- Virtual alarm, critical
    "SIGPROF",   -- Unused
    "SIGWINCH",  -- Unused
    "SIGIO",     -- IO stream available
    "SIGPWR",    -- Signal power loss
    "SIGUNUSED"  -- Unused
}
local Signal = {}
for v,signame in ipairs(SignalReversed) do
    Signal[signame] = v
end
Signal.SIGIOT = Signal.SIGABRT
Signal.SIGPOLL = Signal.SIGIO
Signal.SIGLOST = Signal.SIGPWR
Signal.SIGSYS = Signal.SIGUNUSED
local CriticalSignals = {
    "SIGILL",
    "SIGTRAP",
    "SIGABRT",
    "SIGBUS",
    "SIGFPE",
    "SIGKILL",
    "SIGSEGV",
    "SIGTERM",
    "SIGSTKFLT",
    "SIGVTALRM"
}
local UnhandledSignals = {
    "SIGKILL",
    "SIGSTOP"
}
local StatDescription = {
    R="running",
    D="uninterruptible sleep",
    Z="zombie",
    T="suspended",
    S="sleeping"
}
local function isCriticalSignal(signum)
    return rawFind(CriticalSignals,SignalReversed[signum]) ~= nil
end
local function isUnhandledSignal(signum)
    return rawFind(UnhandledSignals,SignalReversed[signum]) ~= nil
end
local function hasaccessover(proc,checkedproc)
    local cdata = _processdata[checkedproc]
    local pdata = _processdata[proc]
    local user = cdata.user
    local trueuser = pdata.trueuser
    if user == "root" then return true end
    return user == pdata.user or user == trueuser
end
local weaktbl = {__mode="k"}

local function newProcessTable()
    local kernelAPI
    local yieldmutex = newmutex()
    local _yieldedthreads = {}
    local _yieldedpermathreads = {}
    local processmt = {__metatable=false}
    local processtbl = {}
    local function onInitKill()

    end
    processmt.__index = processmt
    local processthreads = setmetatable({},{__mode="kv"})
    local function procdeleteThread(thr)
        processthreads[thr] = nil
        deleteThread(thr)
    end
    local function threadIsOf(proc) 
        return processthreads[coroutine.running()] == proc
    end
    local function yield(ifsuspendedonly)
        ifsuspendedonly = ifsuspendedonly or false
        if ifsuspendedonly then
            if _processdata[processthreads[coroutine.running()]].stat ~= "T" then return end
        end
        yieldmutex:lock()
        if _processdata[processthreads[coroutine.running()]].stat == "T" then
            table.insert(_yieldedpermathreads,coroutine.running())
        else
            table.insert(_yieldedthreads,coroutine.running())
        end
        yieldmutex:unlock()
        local c = coroutine.yield()
        if c then return else while true do coroutine.yield() end end
    end
    local function resume()
        yieldmutex:lock()
        for _,thr in ipairs(_yieldedthreads) do
            coroutine.resume(thr,true)
        end
        _yieldedthreads = {}
        yieldmutex:unlock()
    end
    local function terminate()
        yieldmutex:lock()
        for _,thr in ipairs(_yieldedthreads) do
            coroutine.resume(thr,false)
        end
        for _,thr in ipairs(_yieldedpermathreads) do
            coroutine.resume(thr,false)
        end
        _yieldedthreads = {}
        _yieldedpermathreads = {}
        for thr,proc in pairs(processthreads) do
            procDeleteThread(thr) -- kill all threads
        end
        for pid,proc in pairs(processtbl) do
            proc.stat = "Z"
            if proc.stdinhook then
                proc.stdinhook:Disconnect()
            end
            proc.stdin:close()
            proc.stdout:close()
            proc.stderr:close()
            proc.threads = {}
        end
        yieldmutex:panic()
        -- all processes cleared
        processthreads = setmetatable({},{__mode="kv"})
        processtbl = {}

    end
    local function suspendthreads(proc)
        proc.stat = "T"
        yieldmutex:lock()
        while true do
            local found = false
            for k,thr in ipairs(_yieldedthreads) do
                if processthreads[thr] == proc then
                    found = true
                    table.remove(_yieldedthreads,k)
                    table.insert(_yieldedpermathreads,thr)
                    break
                end
            end
            if not found then break end
        end
        yieldmutex:unlock()
    end
    local function continuethreads(proc)
        proc.stat = "R"
        yieldmutex:lock()
        while true do
            local found = false
            for k,thr in ipairs(_yieldedpermathreads) do
                if processthreads[thr] == proc then
                    found = true
                    table.remove(_yieldedpermathreads,k)
                    table.insert(_yieldedthreads,thr)
                    break
                end
            end
            if not found then break end
        end
        yieldmutex:unlock()
    end
    local function terminateyieldproc(process)
        yieldmutex:lock()
        while true do
            local found = false
            for k,thr in ipairs(_yieldedthreads) do
                if processthreads[thr] == process then
                    coroutine.resume(thr,false)
                    found = true
                    table.remove(_yieldedthreads,k)
                    break
                end
            end
            if not found then break end
        end
        while true do
            local found = false
            for k,thr in ipairs(_yieldedpermathreads) do
                if processthreads[thr] == process then
                    coroutine.resume(thr,false)
                    found = true
                    table.remove(_yieldedthreads,k)
                    break
                end
            end
            if not found then break end
        end
        yieldmutex:unlock()
    end
    local function getnewPID()
        if #processtbl > 500000 then
            for pid = 2,1048576 do
                if not processtbl[pid] then
                    return pid
                end
            end
            error("There are no left PIDs")
        else
            while true do
                local pid = math.random(2,1048576)
                if not processtbl[pid] then
                    return pid
                end
            end
        end
    end
    local function killProcess(proc,pdata,signal)
        terminateyieldproc(proc)
        for _,thr in ipairs(pdata.threads) do
            procDeleteThread(thr)
        end
        -- this process has been killed
        pdata.stat = "Z"
        pdata.threads = {}
        pdata.mainthread = nil
        if pdata.stdin then
            pdata.stdinhook:Disconnect()
            pdata.stdin:close()
        end if pdata.stdout then
            pdata.stdout:close()
        end if pdata.stderr then
            pdata.stderr:close()
        end
        local parent = pdata.parent
        for _,chld in ipairs(pdata.children) do
            chld.parent = parent
            table.insert(parent.children,chld)
        end
        pdata.children = {}
        pdata.retval = signal
        pdata.returntype = 2
    end
    local function mainthreadrunner(func,proc)
        local pdata = _processdata[proc]
        if pdata.forked then
            pdata.retval = func(proc,pdata.forked)
        else
            pdata.retval = func(proc,-1)
        end
        pdata.returntype = 1
        terminateyieldproc(proc)
        for _,thr in ipairs(pdata.threads) do
            procDeleteThread(thr)
        end
        -- this process has been killed
        pdata.stat = "Z"
        pdata.threads = {}
        pdata.mainthread = nil
        if pdata.stdin then
            pdata.stdinhook:Disconnect()
            pdata.stdin:close()
        end if pdata.stdout then
            pdata.stdout:close()
        end if pdata.stderr then
            pdata.stderr:close()
        end
        local parent = pdata.parent
        for _,chld in ipairs(pdata.children) do
            chld.parent = parent
            table.insert(parent.children,chld)
        end
        pdata.children = {}
    end
    local function threadrunner(f,...)
        local proc = processthreads[coroutine.running()]
        local pdata = _processdata[proc]
        local nerr,err = pcall(f,...)
        table.remove(pdata.threads,rawFind(pdata.threads,coroutine.running()))
        if not nerr then error(err) end
    end
    function processmt.new(name,init,sigh,parent,user,pid,stdin,stdout,stderr,tty,argv,filepath,pubenv,privenv,trueuser,groupuser)
        pid = pid or getnewPID()
        user = user or "root"
        trueuser = trueuser or user
        groupuser = groupuser or nil
        parent = parent or processtbl[1]
        local proc = {}
        setmetatable(proc,processmt)
        processtbl[pid] = proc
        local function onwrite()
            proc:sendSignal(Signal.SIGIO)
        end
        _processdata[proc] = {
            pid = pid,
            name = name,
            parent = parent,
            children = {},
            stdin=stdin,
            stdout=stdout,
            stderr=stderr,
            tty=tty,
            argv=argv,
            user=user,
            trueuser=trueuser,
            groupuser=groupuser,
            filepath=filepath,
            threads = {newThread(mainthreadrunner,init,proc)},
            _onwrite = onwrite,
            sigh=sigh,
            stat="R",
            retval=nil,
            returntype=0,
            mainthread=nil,
            forked=false,
            pubenv=table_clone(pubenv or {}),
            privenv=table_clone(privenv or {})
        }
        local pdata = _processdata[proc]
        pdata.mainthread = pdata.threads[1]
        processthreads[pdata.mainthread] = proc
        dispatchThread(pdata.mainthread,init,proc)
        if stdin then
            pdata.stdinhook = stdin:getWriteEvent():Connect(onwrite)
        end
        if parent then
            table.insert(pdata.children,proc)
        end
        return proc
    end
    function processmt:changeStdIn(newstdin)
        local sendingproc = processthreads[coroutine.running()]
        if not hasaccessover(self,sendingproc) then error("access denied") end
        local pdata = _processdata[self]
        if pdata.stdin then
            pdata.stdinhook:Disconnect()
            pdata.stdinhook = nil
        end
        pdata.stdin = newstdin
        if pdata.stdin then
            pdata.stdinhook = pdata.stdin:getWriteEvent():Connect(pdata._onwrite)
        end
    end
    function processmt:changeStdOut(newstdout)
        local sendingproc = processthreads[coroutine.running()]
        if not hasaccessover(self,sendingproc) then error("access denied") end
        local pdata = _processdata[self]
        if pdata.stdout then
            pdata.stdout:close()
        end
        pdata.stdout = newstdout
    end
    function processmt:changeStdErr(newstderr)
        local sendingproc = processthreads[coroutine.running()]
        if not hasaccessover(self,sendingproc) then error("access denied") end
        local pdata = _processdata[self]
        if pdata.stderr then
            pdata.stderr:close()
        end
        pdata.stderr = newstderr
    end
    function processmt:changeTty(tty)
        local sendingproc = processthreads[coroutine.running()]
        if not hasaccessover(self,sendingproc) then error("access denied") end
        local pdata = _processdata[self]
        pdata.tty = tty
    end
    function processmt:sendSignal(signal)
        local sendingproc = processthreads[coroutine.running()]
        local pdata = _processdata[self]
        if not hasaccessover(self,sendingproc) then error("access denied") end
        if signal == Signal.SIGKILL then
            if pdata.pid == 1 then onInitKill() else killProcess(self,pdata) end
        elseif signal == Signal.SIGCONT then
            if pdata.stat == "T" then 
                continuethreads(self) -- resume process at next resumption cycle
                if pdata.sigh[signal] ~= nil then
                    local thr = newThread(pdata.sigh[signal],self)
                    processthreads[signal] = thr
                    dispatchThread(thr,self)
                    -- signal handled
                end
            end
        elseif pdata.sigh[signal] ~= nil and not isUnhandledSignal(signal) then
            local thr = newThread(pdata.sigh[signal],self)
            processthreads[signal] = thr
            dispatchThread(thr,self)
            -- signal handled
        elseif signal == Signal.SIGSTOP then
            if self.stat ~= "R" then return end
            suspendthreads(self)
            -- suspended
        elseif isCriticalSignal(signal) then
            if pdata.pid == 1 then onInitKill() else killProcess(self,pdata) end
        else
            --ignore
        end
    end
    function processmt:forkStreams()
        local pdata = _processdata[self]
        assert(processthreads[coroutine.running()] == self,"cannot fork streams from outside process")
        if pdata.stdin then
            pdata:changeStdIn(cloneStream(pdata.stdin,false))
        end if pdata.stdout then
            pdata:changeStdOut(cloneStream(pdata.stdout,false))
        end if pdata.stderr then
            pdata:changeStdErr(cloneStream(pdata.stderr,false))
        end
        -- successfully forked streams
    end
    function processmt:getUser()
        return _processdata[self].user
    end
    function processmt:getOwningUser()
        return _processdata[self].trueuser
    end
    function processmt:getGroupUser()
        return _processdata[self].groupuser
    end
    function processmt:getStdIn()
        return _processdata[self].stdin
    end
    function processmt:getStdOut()
        return _processdata[self].stdout
    end
    function processmt:getStdErr()
        return _processdata[self].stderr
    end
    function processmt:getTty()
        return _processdata[self].tty
    end
    function processmt:getFilePath()
        return _processdata[self].filepath
    end
    function processmt:getArgs()
        return _processdata[self].argv
    end
    function processmt:getThreads()
        local t = {}
        for i,thr in ipairs(_processdata[self].threads) do
            t[i] = "<"..tostring(thr).."> "..coroutine.status(thr)
        end
        return t
    end
    function processmt:getPID()
        return _processdata[self].pid
    end
    function processmt:getParent()
        return _processdata[_processdata[self].parent].pid
    end
    function processmt:getChildren()
        local t = {}
        for i,proc in ipairs(_processdata[self].children) do
            t[i] = _processdata[proc].pid
        end
        return t
    end
    function processmt:getStat()
        return _processdata[self].stat
    end
    function processmt:newThread(func,...)
        assert(processthreads[coroutine.running()] == self,"cannot create new thread outside of process")
        local thr = newThread(threadrunner,func,...)
        processthreads[thr] = self
        table.insert(_processdata[self].threads,thr)
        dispatchThread(func,...)
    end
    function processmt:isMainThread()
        return _processdata[self].mainthread == coroutine.running()
    end
    function processmt:giveUpGroupUser()
        assert(processthreads[coroutine.running()] == self,"cannot give up permission outside of process")
        local pdata = _processdata[self]
        pdata.groupuser = nil
    end
    function processmt:giveUpSuperUser()
        assert(processthreads[coroutine.running()] == self,"cannot give up permission outside of process")
        local pdata = _processdata[self]
        pdata.user = pdata.trueuser
    end
    function processmt:fork(func)
        assert(processthreads[coroutine.running()] == self,"cannot fork outside of process")
        local pdata = _processdata[self]
        local proc = processmt.new(pdata.name,func,pdata.sigh,self,pdata.user,nil,pdata.stdin,pdata.stdout,pdata.stderr,pdata.tty,pdata.argv,pdata.filepath,table_clone(pdata.pubenv),table_clone(pdata.privenv),pdata.trueuser,pdata.groupuser)
        local thr = coroutine.running()
        processthreads[thr] = proc
        proc:forkStreams()
        processthreads[thr] = self
        local ppdata = _processdata[proc]
        ppdata.forked = true
        return func(self,proc.pid)
    end
    function processmt:exec(name,init,sigh,argv,filepath,trueuser)
        local thr = coroutine.running()
        assert(processthreads[thr] == self,"cannot exec outside of process")
        local pdata = _processdata[self]
        local threads = pdata.threads
        --kill all other threads
        while threads[1] ~= thr do
            procDeleteThread(threads[1])
            table.remove(threads,1)
        end
        while threads[2] ~= nil do
            procDeleteThread(threads[2]) 
            table.remove(threads,2)
        end
        pdata.name = name
        pdata.sigh = sigh
        pdata.argv = argv
        pdata.filepath = filepath
        pdata.forked = false
        thr = newThread(mainthreadrunner,init,self)
        pdata.mainthread = thr
        pdata.threads={thr}
        pdata.trueuser = trueuser or pdata.trueuser
        dispatchThread(thr,init,self)
        procDeleteThread(coroutine.running())
        while true do coroutine.yield() end
        -- marks the end of the thread
    end
    function processmt:getEnv(key)
        return _processdata[self].pubenv[key]
    end
    function processmt:setEnv(key,value)
        local sendingproc = processthreads[coroutine.running()]
        if not hasaccessover(self,sendingproc) then error("access denied") end
        _processdata[self].pubenv[key] = value
    end
    function processmt:setPrivEnv(key,value)
        if processthreads[coroutine.running()] ~= self then error("cannot set private enviroment outside of process") end
        _processdata[self].privenv[key] = value
    end
    function processmt:getPrivEnv(key)
        if processthreads[coroutine.running()] ~= self then error("cannot get private enviroment outside of process") end
        return _processdata[self].privenv[key]
    end
    function processmt:getAPI()
        return setmetatable({},{
            __index=kernelAPI,
            __metatable=false,
            __newindex = function(t,k,v) error("frozen table") end
        })
    end
    local rootproc = setmetatable({},processmt)
    _processdata[rootproc] = {user="root"}
    local function runFuncAsRoot(func,...)
        local thr = coroutine.running()
        local currproc = processthreads[thr]
        processthreads[thr] = rootproc
        local t = {pcall(func,...)}
        processthreads[thr] = currproc
        if t[1] then table.remove(t,1) return table.unpack(t) else error(t[2]) end
    end
    local grouptbl = setmetatable({},{__index=function (t,k)
        local nt = {}
        rawset(t,k,nt)
        return nt
    end})
    return {
        yield=yield,
        processthreads=processthreads,
        getCurrentProcess=function ()
            return processthreads[coroutine.running()]
        end,
        getCurrentUser=function ()
            local p = processthreads[coroutine.running()]
            if p then return _processdata[p].user end
        end,
        resume=resume,
        terminate=terminate,
        setKernelAPI=function(new)
            kernelAPI = new
        end,
        processmt=processmt,
        setOnInitKill=function(new)
            onInitKill=new
        end,
        threadIsOf = threadIsOf,
        rootproc=rootproc,
        runFuncAsRoot=runFuncAsRoot,
        grouptbl=grouptbl,
        addUserToGroup=function (group,user)
            grouptbl[group][user]=true
        end,
        removeUserFromGroup=function (group,user)
            grouptbl[group][user]=nil
        end,
        addGroup=function (group)
            if grouptbl[group] then end -- create group if it doesnt exist
        end,
        delGroup=function (group)
            grouptbl[group]=nil
        end,
        isOwnerOfGroup=function (group,user)
            return group == user
        end,
        isInGroup=function (group,user)
            if not group then return false end
            return grouptbl[group][user] == true
        end,
        isInGroupWith=function (u1,u2)
            for gname,group in pairs(grouptbl) do
                if group[u1] and group[u2] then
                    return gname
                end
            end
        end,
        getGroupsOfUser = function (user)
            local t = {}
            for gname,group in pairs(grouptbl) do
                if group[user] then
                    t[#t+1] = gname
                end
            end
            return t
        end
    }
end