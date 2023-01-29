dirs = [
    "LICENSE.md",
    "loadstring.lua",
    "split.lua",
    "stream.lua",
    "mutex.lua",
    "objtraits.lua",
    "objects.lua",
    "process.lua",
    "term.lua",
    "objtoret.lua"
]
strs = ""
for i in dirs:
    with open(i) as fw:
        strs += fw.read() + "\n"
with open("out.lua","w") as fw:
    fw.write(strs)