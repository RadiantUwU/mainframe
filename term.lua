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
		proc.pubenv.workingDir = rootdir
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
local function newSystem(devname,stdinf,stdoutf,stderrf) --> init proc, kernel API, public accessible API
	stdoutf("[0.00000] [kernel] initializing")
	local ti = os.clock()
	local function rawIsIn(t,v)
		for k,bb in pairs(t) do
			if rawequal(bb,v) then return k end
		end
	end
	local function log(module,msg)
		stdoutf("\n[" .. string.format("%.5f",os.clock()-ti) .."] ["..module.."] "..msg)
	end
	--create proc table
	local pr = newIsolatedProcessTable()
	local krnlprocplaceholder = {
		user="root"
	}
	--create filesystem
	log("scsi","starting disk")
	local rootdir,du = newIsolatedRootfs(pr.grouptbl,pr.newProcess,pr.getCurrentProc)
	--load macros
	local 
	 newDirectory,newExecutable,newFile,newStreamFile,newProcess,getCurrentProc,processesthr,newStreamDirectory,isInGroup
	 = du.newDirectory,du.newExecutable,du.newFile,du.newStreamFile,pr.newProcess,pr.getCurrentProc,pr.processesthr,du.newStreamDirectory,pr.isInGroup
	local processtable = pr.processtable
	processesthr[coroutine.running()] = krnlprocplaceholder
	task.wait(0.3)
	log("sda","mounting /dev/sda1")
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
		newStreamFile(newStdOut(function(str)
			if str == "s" and process.state == "I" then
				process:start()
			elseif str == "d" and process.state = "I" then
				process.state = "Z"
				process.retcode = -1
			end
		end),"start",prc,pru,"-w--w----")
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
						if id == 1 then return end
						coroutine.wrap(function()
							pr.processesthr[coroutine.running()] = krnlprocplaceholder
							proc:terminate()
						)()
					end
				elseif c == "i" then
					for id,proc in pairs(processtable) do
						if id == 1 then return end
						coroutine.wrap(function()
							pr.processesthr[coroutine.running()] = krnlprocplaceholder
							proc:kill()
						)()
					end
				end
			end
		end),"sysrq-trigger",procdir,nil,"rw-rw----")
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
	newStreamFile(streamnull,"null",devdir,nil,"rw-rw-rw-")
	newStreamFile(function(op,arg)
		if op == "r" then
			if arg == -1 then
				return "0"
			else
				return string.rep("0",arg)
			end
		elseif op == "l" then
			return 268435455
		end
	end,"zero",devdir,nil,"rw-rw-rw-")
	local stdin = newStreamGen(stdinf)
	local stdout = newStreamGen(stdoutf)
	local stderr = newStreamGen(stderrf)
	log("kernel","loading init")
	local function findGroupsOfUser(group,user)
		local gs = {}
		for gn,g in pairs(pr.grouptbl) then
			if rawIsIn(g,user) then
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
		log("fs","unmounting /dev/sda1")
		task.wait(0.4)
		log("scsi","stopping disk")
		task.wait(1)
		log("kernel","shutting down")
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
		log("fs","unmounting /dev/sda1")
		task.wait(0.4)
		log("scsi","stopping disk")
		task.wait(1)
		log("kernel","system halted")
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
		log("fs","unmounting /dev/sda1")
		task.wait(0.4)
		log("scsi","stopping disk")
		task.wait(1)
		log("kernel","rebooting")
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
			return
		else
			proc.stdout:write("Code:")
			proc.privenv.code = ""
		end
		proc.kernelAPI.yield()
		while true do
			local c = nil
			while c ~= "" do
				c = stdin:read(1
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
			proc.kernelAPI.yield()
		end
	end
	local function newEpo()
		return epoinit,{}
	end
	newExecutable(newEpo,"epo",bindir,"root","rwxrwxr-x")
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
	newExecutable(newCd,"cd",bindir,"root","rwxrwxr-x")
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
	newExecutable(newDir,"ls",bindir,"root","rwxrwxr-x")
	newExecutable(newDir,"dir",bindir,"root","rwxrwxr-x")
	local function whoamiinit(proc)
		local nerr,hostname = pcall(rootdir:to("/etc/hostname"))
		if not nerr then
			proc.stderr:write("failed to open /etc/hostname\n")
			proc:ret(1)
			return
		end
		nerr = pcall(function ()
			hostname = hostname:read()
		end)
		if not nerr then
			proc.stderr:write("failed to open /etc/hostname\n")
			proc:ret(1)
			return
		end
		proc.stdout:write(proc.user .. "@" .. hostname)
		proc:ret(0)
	end
	local function newwhoami() return whoamiinit,{} end
	newExecutable(newwhoami,"whoami",bindir,"root","rwxrwxr-x")
	local function catinit(proc)
		local filetoreadpath = proc.argv[2]
		if filetoreadpath == nil then
			proc.stderr:write("no file specified\n")
			proc:ret(1)
			return
		end
		local file,nerr
		if proc.pubenv.workingDir != nil then
			nerr,file = pcall(function()
				return proc.pubenv.workingDir:to(filetoreadpath)
			end)
		else
			nerr,file = pcall(function()
				return rootdir:to(filetoreadpath,true)
			end)
		end
		if not nerr then
			proc.stderr:write(file .. "\n")
			proc:ret(1)
			return
		end
		if file == nil then
			proc.stderr:write("file not found\n")
			proc:ret(1)
			return
		end
		nerr,file = pcall(function()
			return file:read()
		end)
		if not nerr then
			proc.stderr:write(file .. "\n")
			proc:ret(1)
			return
		end
		proc.stdout:write(file)
		proc:ret(0)
	end
	local function newcat() return catinit,{} end
	newExecutable(newcat,"cat",bindir,"root","rwxrwxr-x")
	local function echoinit(proc) 
		local arguments = {}
		local sizemultipliers={
			b=1,
			k=1000,
			m=1000000,
			g=1000000000,
			t=1000000000000,
			p=1000000000000000,
			B=512,
			K=1024,
			M=1048576,
			G=1073741824,
			T=1099511627776,
			P=1125899906842624
		}
		local sizelimit = sizemultipliers.M * 10
		local size = sizelimit
		local blocksize = sizemultipliers.B -- one block, 512 bytes
		local globalseek = 0
		local actualargs = {
			["-wp"]=0,  -- waits for all processes to terminate, auto on for the processes spawned
			["-b"]=1,   -- block size
			["-s"]=1,   -- size
			["-is"]=1,  -- input seek
			["-os"]=1   -- output seek
		}
		for i,v in ipairs(proc.argv) do
			if i ~= 1 then
				arguments[i - 1] = v
			end
		end
		local stream = newStream()
		local types = {v="variable",f="file",p="process",s="seek",n="none",sa="seekawait",pa}
		local states = {none="none",iargs="iargs",oargs="oargs",inp="inp",out="out",app="app",inputprocess="ip",outputprocess="op",parsingarg="pa"}
		local statesallowed= {none="none",iargs="iargs",oargs="oargs"}
		local inputseek = 1
		local argparse = ""
		local special = {
			["<"]="inp",[">"]="out",[">>"]="app",
			["-if"]="inp",["-of"]="out"}
		local state = states.none
		local buffer = {}
		local stdins = {}
		local _stdins = {}
		local _stdouts = {}
		local _stdapps = {}
		local stdouts = {}
		local stdoutstreams = {}
		local stdapps = {}
		local function isnumber(n)
			return pcall(tonumber,n)
		end
		proc.privenv.waitforproc={}
		for _,v in ipairs(arguments) do
			local k = rawIsIn(special,v)
			if k then
				if rawIsIn(statesallowed,state) then
					if state == statesallowed.iargs then
						table.insert(stdins,0)
					elseif state == statesallowed.oargs then
						table.insert(stdouts,0)
					end
					state = states[k]
				else
					proc.stderr:write("parsing error\n")
					proc:ret(1)
					return
				end
			else
				if state == states.none then
					if v == "-wp" then
						proc.privenv.waitforproc = true
					elseif rawIsIn(actualargs,v) then
						argparse = v
						state = states.parsingarg
					elseif v:sub(1,1) == "$" then
						stream:write(proc.parent:getEnv(v:sub(2,-1)))
					else
						stream:write(v)
					end
				elseif state == states.inp then
					if v == "-p" then
						state = states.inputprocess
					elseif v:sub(1,1) == "$" then
						stream:write(proc.parent:getEnv(v:sub(2,-1)))
						state = states.none
					else
						table.insert(stdins,types.f)
						table.insert(stdins,v)
						state = states.none
					end
				elseif state == states.out then
					if v == "-p" then
						state = states.outputprocess
					elseif v:sub(1,1) == "$" then
						table.insert(stdouts,types.v)
						table.insert(stdouts,v:sub(2,-1))
						state = states.none
					else
						table.insert(stdouts,types.f)
						table.insert(stdouts,v)
						state = states.none
					end
				elseif state == states.app then
					if v == "-p" then
						state = states.outputprocess
					elseif v:sub(1,1) == "$" then
						table.insert(stdapps,types.v)
						table.insert(stdapps,v:sub(2,-1))
						state = states.none
					else
						table.insert(stdapps,types.f)
						table.insert(stdapps,v)
						state = states.none
					end
				elseif state == states.inputprocess then
					table.insert(stdins,types.p)
					table.insert(stdins,v)
					state = states.iargs
				elseif state == states.outputprocess then
					table.insert(stdouts,types.p)
					table.insert(stdouts,v)
					state = states.oargs
				elseif state == states.iargs then
					table.insert(stdins,v)
				elseif state == states.oargs then
					table.insert(stdouts,v)
				elseif state == states.parsingarg then
					if argparse == "-b" then
						local numtoparse = v
						local mult = 1
						if sizemultipliers[v:sub(-2,-1)] then
							mult = sizemultipliers[v:sub(-2,-1)]
							numtoparse = v:sub(1,-2)
						end
						local nerr,i = pcall(tonumber,numtoparse)
						if not nerr then
							proc.stderr:write("parsing error\n")
							proc:ret(1)
							return
						end
						blocksize = i
						if i > sizelimit then
							proc.stderr:write("exceeds sizelimit\n")
							proc:ret(1)
							return
						end
					elseif argparse == "-s" then
						local numtoparse = v
						local mult = 1
						if sizemultipliers[v:sub(-2,-1)] then
							mult = sizemultipliers[v:sub(-2,-1)]
							numtoparse = v:sub(1,-2)
						end
						local nerr,i = pcall(tonumber,numtoparse)
						if not nerr then
							proc.stderr:write("parsing error\n")
							proc:ret(1)
						end
						size = i
						if i > sizelimit then
							proc.stderr:write("exceeds sizelimit\n")
							proc:ret(1)
							return
						end
					elseif argparse == "-is" then
						local numtoparse = v
						local mult = 1
						if sizemultipliers[v:sub(-2,-1)] then
							mult = sizemultipliers[v:sub(-2,-1)]
							numtoparse = v:sub(1,-2)
						end
						local nerr,i = pcall(tonumber,numtoparse)
						if not nerr then
							proc.stderr:write("parsing error\n")
							proc:ret(1)
						end
						inputseek = i + 1
					elseif argparse = "-os" then
						local numtoparse = v
						local mult = 1
						if sizemultipliers[v:sub(-2,-1)] then
							mult = sizemultipliers[v:sub(-2,-1)]
							numtoparse = v:sub(1,-2)
						end
						local nerr,i = pcall(tonumber,numtoparse)
						if not nerr then
							proc.stderr:write("parsing error\n")
							proc:ret(1)
						end
						table.insert(stdouts,types.s)
						table.insert(stdouts,i + 1)
					end
				end
			end
		end
		local file,nerr
		local state = types.n
		for _,i in ipairs(stdins) do
			local cango = true
			if state == types.sa then
				state = types.n
				if i ~= types.s then
					table.insert(_stdins,{type="file",object=file,seek=1})
				else
					state = types.s
					cango = false
				end
			end
			if not cango then
			elseif state == types.n then state = i
			elseif state == types.f then
				--get file
				nerr,file = proc.kernelAPI.getFileRelativeFromProc(i)
				if not nerr then
					stderr:write(file .. "\n")
					proc:ret(1)
					return
				end
				if file:isADirectory() then
					stderr:write("not a file\n")
					proc:ret(1)
					return
				end
				if not file:canRead() then
					stderr:write("access denied\n")
					proc:ret(1)
					return
				end
				state = types.sa
			elseif state == types.s then
				table.insert(_stdins,{type="file",object=file,seek=i})
				state = types.n
			elseif state == types.p then
				if type(i) == "number" then
					--terminator, start process
					nerr,file = proc.kernelAPI.getFileRelativeFromProc(buffer[1])
					if not nerr then
						stderr:write(file.."\n")
						proc:ret(1)
						return
					end
					local process
					table.remove(buffer,1)
					nerr,process = pcall(file.execute,file,buffer)
					if not nerr then
						stderr:write(process.."\n")
						proc:ret(1)
						return
					end
					process.stdout = stream
					process:start()
					buffer = {}
				else
					table.insert(buffer,i)
				end
			end
		end
		for _,i in ipairs(stdouts) do
			local cango = true
			if state == types.sa then
				state = types.n
				if i ~= types.s then
					table.insert(_stdouts,{type="file",object=file,seek=1})
				else
					state = types.s
					cango = false
				end
			end
			if not cango then
			elseif state == types.n then 
				if v == states.s then	
					stderr:write("parsing error\n")
					proc:ret(1)
					return
				end
				state = i
			elseif state == types.f then
				--get file
				nerr,file = proc.kernelAPI.getFileRelativeFromProc(i)
				if not nerr then
					stderr:write(file .. "\n")
					proc:ret(1)
					return
				end
				if file:isADirectory() then
					stderr:write("not a file\n")
					proc:ret(1)
					return
				end
				if not file:canWrite() then
					stderr:write("access denied\n")
					proc:ret(1)
					return
				end
				state = types.sa
			elseif state == types.s then
				table.insert(_stdouts,{type="file",object=file,seek=i})
				state = types.n
			elseif state == types.p then
				if type(i) == "number" then
					--terminator, start process
					nerr,file = proc.kernelAPI.getFileRelativeFromProc(buffer[1])
					if not nerr then
						stderr:write(file.."\n")
						proc:ret(1)
						return
					end
					local process
					table.remove(buffer,1)
					nerr,process = pcall(file.execute,file,buffer)
					if not nerr then
						stderr:write(process.."\n")
						proc:ret(1)
						return
					end
					local newstreams = newStream()
					process.stdin = newstreams
					table.insert(stdoutstreams,newstreams)
					process:start()
					buffer = {}
				else
					table.insert(buffer,i)
				end
			elseif state == types.v then
				local varname = v
				proc.parent.pubenv[varname] = ""
				local function appendtovar(str)
					local var = proc.parent:getEnv(varname)
					proc.parent.pubenv[varname] = var .. str
				end
				table.insert(stdoutstreams,newStdOut(appendtovar))
			end
		end
		for _,i in ipairs(stdapps) do
			local cango = true
			if state == types.sa then
				state = types.n
				if i ~= types.s then
					table.insert(_stdapps,{type="file",object=file,seek=1})
				else
					state = types.s
					cango = false
				end
			end
			if not cango then
			elseif state == types.n then state = i
			elseif state == types.f then
				--get file
				nerr,file = proc.kernelAPI.getFileRelativeFromProc(i)
				if not nerr then
					stderr:write(file .. "\n")
					proc:ret(1)
					return
				end
				if file:isADirectory() then
					stderr:write("not a file\n")
					proc:ret(1)
					return
				end
				if not file:canWrite() then
					stderr:write("access denied\n")
					proc:ret(1)
					return
				end
				state = types.sa
			elseif state == types.s then
				table.insert(_stdapps,{type="file",object=file,seek=i})
				state = types.n
			elseif state == types.p then
				if type(i) == "number" then
					--terminator, start process
					nerr,file = proc.kernelAPI.getFileRelativeFromProc(buffer[1])
					if not nerr then
						stderr:write(file.."\n")
						proc:ret(1)
						return
					end
					local process
					table.remove(buffer,1)
					nerr,process = pcall(file.execute,file,buffer)
					if not nerr then
						stderr:write(process.."\n")
						proc:ret(1)
						return
					end
					local newstreams = newStream()
					process.stdin = newstreams
					table.insert(stdoutstreams,newstreams)
					process:start()
					buffer = {}
				else
					table.insert(buffer,i)
				end
			elseif state == types.v then
				local varname = v
				assert(type(proc.parent.pubenv[varname]) == "string","var must be a string")
				local function appendtovar(str)
					local var = proc.parent:getEnv(varname)
					proc.parent.pubenv[varname] = var .. str
				end
				table.insert(stdoutstreams,newStdOut(appendtovar))
			end
		end
		local function initall()
			local s = stream:readAll()
			for _,o in ipairs(_stdouts) do
				o:write(s)
			end
			for _,o in ipairs(_stdapps) do
				o:append(s)
			end
			for _,o in ipairs(stdoutstreams) do
				o:write(s)
			end
		end
		local function pushall()
			local s = stream:readAll()
			for _,o in ipairs(_stdouts) do
				o:append(s)
			end
			for _,o in ipairs(_stdapps) do
				o:append(s)
			end
			for _,o in ipairs(stdoutstreams) do
				o:write(s)
			end
		end
		initall()
		while true do 
			for _,fileentry in ipairs(_stdins) do
				local fileobj = fileentry.object
				local seekedat = globalseek + fileentry.seek
				stream:write(fileobj:read(seekedat,blocksize))
			end
			globalseek = globalseek + blocksize
			pushall()
			--check for EOF
			for _,fileentry in ipairs(_stdins) do
				local fileobj = fileentry.object
				local seekedat = globalseek + fileentry.seek
				if fileobj:read(seekedat,1) == "" then
					--reached EOF
					proc:ret(0)
					return
				end
			end
			proc.kernelAPI.yield()
		end
	end
	local function newecho() return echoinit,{} end
	newExecutable(newecho,"echo",bindir,"root","rwxrwxr-x")
	newExecutable(newecho,"pipe",bindir,"root","rwxrwxr-x")
	newExecutable(newecho,"dd",bindir,"root","rwxrwxr-x")
	local initfile = newExecutable(newInit,"init",sbindir,"root","rwxrw----")
	local ip = initfile:execute()
	ip.pid = 1
	ip.stdin = newStdIn(stdinf)
	ip.stdout = newStdOut(stdoutf)
	ip.stderr = newStdOut(stderrf)
	local getRunningUser = function()
		local proc = processesthr[coroutine.running()]
		if proc then
			return proc.user
		end
	end
	local ownsGroup = function(group,user)
		if user == "root" then return true end
		return user == group
	end
	local privatekernelAPI = {
		syspoweroff = syspoweroff,
		syshalt = syshalt,
		sysreboot = sysreboot,
		stdin=stdin,
		stdout=stdout,
		stderr=stderr,
		setEPOCode=function(codetoset)
			code = codetoset
		end
		reProcAnyRoot=function(procholder)
			procholder = procholder or ip -- init process
			pr.processesthr[coroutine.running()]=procholder
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
		bindir = bindir,
		state = function()
			if powerdown == false then
				return "Running"
			end
			return "Offline"
		end,
		resume=pr.resumeAll,
		yield=pr.yield,
		log=log
	}
	local publicKernelAPI = {
		rootfs = rootdir,
		getRunningUser = getRunningUser,
		getFileRelativeFromProc = function(file) --nerr, file/msg
			return pcall(function()
				local proc = processesthr[coroutine.running()]
				if not proc then error("function can't be used in an anonymous thread") end
				local workingDir = proc:getEnv("workingDir")
				local newfile
				if workingDir == nil then
					newfile = rootdir:to(file,true)
				else 
					newfile = workingDir:to(file)
				end
				if newfile == nil then error("file not found") end
				return newfile
			end)
		end,
		isThreadRooted = function()
			local user = getRunningUser()
			if user == nil then return false end
			return isInGroup("root",user)
		end,
		isInGroup=isInGroup,
		isCurrentInGroup=function(group)
			local user = getRunningUser()
			if user == nil then return false end
			return isInGroup(group,user)
		end,
		addUserToGroup=function(group,user)
			local cu = getRunningUser()
			if user == nil then error("access denied")
			if ownsGroup(group,cu) then
				privatekernelAPI.addUserInGroup(group,user)
			end
		end,
		removeUserFromGroup=function(group,user)
			local cu = getRunningUser()
			if user == nil then error("access denied")
			if ownsGroup(group,cu) then
				privatekernelAPI.removeUserInGroup(group,user)
			end
		end,
		ownsGroup = ownsGroup,
		newStream=newStream,
		newStreamGen=newStreamGen,
		newStdIn=newStdIn,
		newStdOut=newStdOut,
		newNullStream=newNullStream,
		findGroupsOfUser=findGroupsOfUser,
		yield=pr.yield
	}
	table.freeze(publicKernelAPI)
	return ip,privatekernelAPI,publicKernelAPI
end