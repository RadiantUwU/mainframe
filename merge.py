dirs = [
    "LICENSE.md",
    "loadstring.lua",
    "table_extend.lua",
    "thread.lua",
    "split.lua",
    "dispatchableEvent.lua",
    "mutex.lua",
    "stream.lua",
    "pipe.lua",
    "process.lua",
    "fileobject.lua",
    "system.lua",
    "executables.lua",
    "returnedobject.lua"
]
strs = ""
for i in dirs:
    with open(i) as fw:
        strs += "--[[==\n    " + i + "\n==]]--\n" + fw.read() + "\n"
with open("out.lua","w") as fw:
    fw.write(strs)