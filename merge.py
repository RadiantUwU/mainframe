dirs = [
    "LICENSE.md",
    "loadstring.lua",
    "split.lua",
    "dispatchableEvent.lua",
    "mutex.lua",
    "stream.lua"
]
strs = ""
for i in dirs:
    with open(i) as fw:
        strs += fw.read() + "\n"
with open("out.lua","w") as fw:
    fw.write(strs)