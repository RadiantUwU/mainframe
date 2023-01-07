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