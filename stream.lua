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
local function streamnull(op,arg)
	if op == "r" then
		return ""
	elseif op == "l" then
		return 0
	end
end
local function newNullStream()
	return newStreamGen(streamnull)
end
local function propagateStream(stream)
	return function(op,arg)
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
end
--stdout works for stderr too