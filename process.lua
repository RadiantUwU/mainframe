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
	local function rawIsIn(tbl,v)
		for k,vv in pairs(tbl) do
			if rawequal(v,vv) then return k end
		end
		return nil
	end
	local processmt = {}
	processmt.__index = processmt
	function processmt:sendSignal(sig)
		if processesthr[coroutine.running()] then
			if processesthr[coroutine.running()].user ~= self.user then return end
		else
			return
		end
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
		assert(processesthr[coroutine.running()] == self,"cannot forcibly return process from anonymous thread")
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
			if processesthr[thr] != nil then
				error("thread already bound!")
			else
				processesthr[thr] = self
			end
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
	
	local publicKernelAPI
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
			kernelAPI = publicKernelAPI,
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
		end,
		setKernelAPI=function(newapi)
			publicKernelAPI = newapi
		end
	}
end