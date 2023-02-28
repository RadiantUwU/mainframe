local function populateExecutables(kernelAPI)
    local du,pr,bindir,sbindir = kernelAPI.du,kernelAPI.pr,kernelAPI.bindir,kernelAPI.sbindir
    local newFile = du._newFile
    newFile("sh",bindir,"root","rwx--x--x",function()
        return function()
    end)
end