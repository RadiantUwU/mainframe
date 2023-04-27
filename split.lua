local function into_chars(str)
	local t = {}
	for i=1, #str do
		t[i] = str:sub(i,i)
	end
	return t
end
--rbx return {into_chars=into_chars}