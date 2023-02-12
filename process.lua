local _processdata = setmetatable({},{__mode="k"})
local SignalReversed = {
    "SIGHUP",    -- Hangup, request to disconnect streams or notification of streams disconnecting
    "SIGINT",    -- Interrupt, equivalent of CTRL C
    "SIGQUIT",   -- Request to quit/exit
    "SIGILL",    -- Unused, critical, ill-formed instruction
    "SIGTRAP",   -- Unused, meant to get called when debugging instuction by instruction
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
    "SIGPWR",    -- Unused, meant to signal power loss
    "SIGUNUSED"     -- Unused
}
local Signal = {}
for v,signame in ipairs(SignalReversed) do
    Signal[signame] = v
end
Signal.SIGIOT = Signal.SIGABRT
Signal.SIGPOLL = Signal.SIGIO
Signal.SIGLOST = Signal.SIGPWR
Signal.SIGSYS = Signal.SIGUNUSED
local function newProcessTable()
    local kernelAPI
    local yieldmutex = newmutex()
    local _yieldedthreads = {}
    local _yieldedpermathreads = {}
    local processmt = {}
    local processthreads = setmetatable({},{__mode="k"})
    local function yield()
        yieldmutex:lock()
        table.insert(_yieldedthreads,coroutine.running())
        yieldmutex:unlock()
        local c = coroutine.yield()
        if c then return else error("terminate() call",2)
    end
    local function resume()
        yieldmutex:lock()
        for _,thr in ipairs(_yieldedthreads) do
            coroutine.resume(thr,true)
        end
        table.clear(_yieldedthreads)
        yieldmutex:unlock()
    end
    local function terminate()
        yieldmutex:lock()
        for _,thr in ipairs(_yieldedthreads) do
            coroutine.resume(thr,false)
        end
        table.clear(_yieldedthreads)
        yieldmutex:unlock()
    end
    local function terminateyieldproc(process)
        yieldmutex:lock()
        while true do
            local found = false
            for k,thr in ipairs(_yieldedthreads) do
                if proccessthreads[thr] == process then
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
    
    return {
        yield=yield,
        processthreads=processthreads,
        resume=resume,
        terminate=terminate,
        terminateyieldproc=terminateyieldproc
    }
end