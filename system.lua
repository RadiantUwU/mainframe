local function newSystem()
    local pr = newProcessTable()
    local rootfs,du = newFileSystem(pr)
    local newFolder = du._newFolder
    local newStreamFile = du._newStreamFile
    local newStreamFolder = du._newStreamFolder
    local newSymlink = du._newSymLink
    local rootrw = "rwxr-xr-x"
    local usrdir = newFolder("usr",rootfs,"root",rootrw)
    local bindir = newFolder("bin",usrdir,"root",rootrw)
    local sbindir = newFolder("sbin",usrdir,"root","rwx------")
    local devdir = newFolder("dev",rootfs,"root",rootrw)
    local etcdir = newFolder("etc",rootfs,"root",rootrw)
    local homedir = newFolder("home",rootfs,"root",rootrw)
    local mntdir = newFolder("mnt",rootfs,"root",rootrw)
    local rundir = newFolder("run",rootfs,"root",rootrw)
    local tmpdir = newFolder("tmp",rootfs,"root",rootrw)
    local procdir
    local function newprocdir(proc)
        local pdata = _processdata[proc]
        local folder = setmetatable({},fileobjectmt)
        _objectisFolder[folder] = true
        _objectparent[folder] = procdir
        _objectowner[folder] = "root"
        _objectname[folder] = tostring(pdata.pid)
        _objectpermission[folder] = "r-xr-xr-x"
        _foldercontent[folder] = {}
        newStreamFile("owner",folder,"root","r--r--r--",function (op,a1)
            if op == "r" then return newStream(pdata.user)
            else error("Operation not permitted.",2) end
        end)
        newStreamFile("cwd",folder,"root","r--r--r--",function (op,a1)
            if op == "r" then return newStream(pdata.pubenv["workingDir"] or "/")
            else error("Operation not permitted.",2) end
        end)
        newStreamFile("signal",folder,pdata.user,"-w-------",function (op,a1)
            if op == "w" then return newBasicStdout(function(sig,a1)
                proc:sendSignal(sig)
            end)
            else error("Operation not permitted.",2) end
        end)
        local nerr,exec = pcall(FSGoTo,pdata.filepath)
        if nerr then
            newSymlink("exec",folder,exec)
        end
        newStreamFile("stat",folder,"root","r--r--r--",function (op,a1)
            if op == "r" then return newStream(pdata.stat)
            else error("Operation not permitted.",2) end
        end)
        newStreamFile("args",folder,"root","r--r--r--",function (op,a1)
            if op == "r" then return newStream((function()
                local t = ""
                for _,arg in ipairs(pdata.argv) do
                    t = t .. arg .. " "
                end
                return t:sub(1,-2)
            end)())
           else error("Operation not permitted.",2) end
        end)
        newStreamFile("cmdline",folder,"root","r--r--r--",function (op,a1)
            if op == "r" then return newStream((function()
                local t = pdata.filpath .. " "
                for _,arg in ipairs(pdata.argv) do
                    t = t .. arg .. " "
                end
                return t:sub(1,-2)
            end)())
            else error("Operation not permitted.",2) end
        end)
        newStreamFile("filepath",folder,"root","r--r--r--",function (op,a1)
            if op == "r" then return newStream(pdata.filepath)
            else error("Operation not permitted.",2) end
        end)
        if pdata.stdin then
            newStreamFile("stdin",folder,pdata.user,"r--------",function (op,a1)
            if op == "r" then
                local s = pdata.stdin
                if s then
                    return cloneStream(s,false)
                end
            else error("Operation not permitted.",2) end
            end)
        end
        if pdata.stdout then
            newStreamFile("stdout",folder,pdata.user,"-w-------",function (op,a1)
            if op == "w" then
                local s = pdata.stdout
                if s then
                    return cloneStream(s,false)
                end
            else error("Operation not permitted.",2) end
            end)
        end
        if pdata.stderr then
            newStreamFile("stderr",folder,pdata.user,"-w-------",function (op,a1)
            if op == "w" then
                local s = pdata.stderr
                if s then
                    return cloneStream(s,false)
                end
            else error("Operation not permitted.",2) end
            end)
        end
        return folder
    end
    local function procdirf(op,a1,a2)
        if op == "r" then
            local t = {"self"}
            for pid,proc in pairs(pr.processtbl) do
                t[#t+1] = tostring(pid)
            end
            return t
        elseif op == "w" then --ignore
        elseif op == "a" then
            if a1 == "self" then
                return newprocdir(pr.processthreads[coroutine.running()])
            else
                local p = tonumber(a1)
                if not p then
                    return nil
                end
                local proc = pr.processtbl[p]
                if not proc then
                    return nil
                end
                return newprocdir(proc)
            end
        end
    end
    procdir = newStreamFolder("proc",rootfs,"root","r-xr-xr-x",procdirf)
    newSymlink("bin",rootfs,bindir)
    newSymlink("sbin",rootfs,sbindir)

    return {
        bindir=bindir,
        devdir=devdir,
        etcdir=etcdir,
        homedir=homedir,
        mntdir=mntdir,
        procdir=procdir,
        rundir=rundir,
        tmpdir=tmpdir,

        pr=pr,
        rootfs=rootfs,
        du=du,

        populateDevFolder = function()
            newStreamFile("null",devdir,"root","rw-rw-rw-",function(op,a1)
                if op == "r" then
                    return newBasicStdin(function() return "" end,false)
                elseif op == "w" then
                    return newBasicStdin(function() return "" end,false)
                else error("Operation not permitted.",2) end
            end)
            newStreamFile("zero",devdir,"root","r--r--r--",function(op,a1)
                if op == "r" then
                    return newBasicStdin(function() return string.char(0) end,false)
                else error("Operation not permitted.",2) end
            end)
            newStreamFile("urandom",devdir,"root","r--r--r--",function(op,a1)
                if op == "r" then
                    return newBasicStdin(function() return string.char(math.random(0,255)) end,false)
                else error("Operation not permitted.",2) end
            end)
            newStreamFile("stdin",devdir,"root","r--r--r--",function(op,a1)
                if op == "r" then
                    local proc = pr.processthreads[coroutine.running()]
                    local pdata = _processdata[proc]
                    return newBasicStdin(function() if pdata.stdin then return pdata.stdin:read(1) else return "" end end)
                else error("Operation not permitted.",2) end
            end)
            newStreamFile("stdout",devdir,"root","-w--w--w-",function(op,a1)
                if op == "w" then
                    local proc = pr.processthreads[coroutine.running()]
                    local pdata = _processdata[proc]
                    return cloneStream(pdata.stdout,false)
                else error("Operation not permitted.",2) end
            end)
            newStreamFile("stderr",devdir,"root","-w--w--w-",function(op,a1)
                if op == "w" then
                    local proc = pr.processthreads[coroutine.running()]
                    local pdata = _processdata[proc]
                    return cloneStream(pdata.stderr,false)
                else error("Operation not permitted.",2) end
            end)
            newStreamFile("tty",devdir,"root","rw-rw-rw-",function(op,a1)
                if op == "r" or op == "w" then
                    local proc = pr.processthreads[coroutine.running()]
                    local pdata = _processdata[proc]
                    return pdata.tty
                else error("Operation not permitted.",2) end
            end)
        end
    }
end