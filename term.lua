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
				elseif c == "e" then
					for id,proc in pairs(processtable) do
						coroutine.wrap(function()
							pr.processesthr[coroutine.running()] = krnlprocplaceholder
							proc:terminate()
						)()
					end
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
			coroutine.wrap(function()
				pr.processesthr[coroutine.running()] = krnlprocplaceholder
				processtable[1]:kill()
			end)()
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
			coroutine.wrap(function()
				pr.processesthr[coroutine.running()] = krnlprocplaceholder
				processtable[1]:kill()
			end)()
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
			coroutine.wrap(function()
				pr.processesthr[coroutine.running()] = krnlprocplaceholder
				processtable[1]:kill()
			end)()
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
		if not code then
			stderr:write("access denied.\n")
			proc:ret(19) -- access denied
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
	local function cdinit(proc)
		local dir = proc.parent:getEnv("workingDir")
		if dir then
			local nerr,res = pcall(dir.to)(dir,proc.argv[2])
			if nerr then
				if res then
					if res:isADirectory() then
						proc.parent.pubenv.workingDir = res
						proc:ret(0)
					else
						stderr:write("Not a directory.\n")
						proc:ret(2)
					end
				else
					stderr:write("Link not found.\n")
					proc:ret(3)
				end
			else
				stderr:write("An error occurred while changing directory: "..res.."\n")
				proc:ret(4)
			end
		else
			stderr:write("Parent process does not support cd.")
			proc:ret(1)
		end
	end
	local function newCd() return cdinit,{} end
	newExecutable(newCd,"cd",bindir,nil,"rwxrwxr-x")
	local function dirinit(proc)
		local dir = proc.argv[2]
		if type(dir) == "string" then
			local wd = proc.parent:getEnv("workingDir")
			if wd then
				local nerr,dir_ = wd:to(dir)
				if nerr then
					if dir_ then
						dir = dir_
					else
						stderr:write("Path not found.\n")
						proc:ret(1)
						return
					end
				else
					if dir_ == "access denied" then
						stderr:write("Access denied.\n")
					else
						stderr:write(dir_ .. "\n")
					end
					proc:ret(1)
					return
				end
			else
				local nerr,dir_ = rootdir:to(dir,true)
				if nerr then
					if dir_ then
						dir = dir_
					else
						stderr:write("Path not found.\n")
						proc:ret(1)
						return
					end
				else
					if dir_ == "access denied" then
						stderr:write("Access denied.\n")
					else
						stderr:write(dir_ .. "\n")
					end
					proc:ret(1)
					return
				end
			end
		end
		if type(dir) == "table" then
			if dir.isADirectory then
				if dir:isADirectory() then
					if not dir:canAccess() then
						stderr:write("Access denied.\n")
						proc:ret(1)
						return
					else
						local dirs = dir:access()
						for _,i in ipairs(dirs) do
							stdout:write(i .. "\n")
						end
						proc:ret(0)
						return
					end
				else
					stderr:write("Not a directory\n")
					proc:ret(1)
					return
				end
			else
				stderr:write("Not a directory\n")
				proc:ret(1)
				return
			end	
		else
			stderr:write("Not a directory\n")
			proc:ret(1)
			return
		end
	end
	local function newDir() return dirinit,{} end
	newExecutable(newDir,"dir",bindir,nil,"rwxrwxr-x")
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