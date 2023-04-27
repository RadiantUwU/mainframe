import sys
import os
output = {
    "name":"LinuxSystem.lua",
    "dependencies":[
        "LICENSE.md",
        {
            "name":"table_extend.lua",
            "dependencies":[]
        },
        {
            "name":"split.lua",
            "dependencies":[]
        },
        {
            "name":"mutex.lua",
            "dependencies":[]
        },
        {
            "name":"dispatchableEvent.lua",
            "dependencies":[]
        },
        {
            "name":"stream.lua",
            "dependencies":[]
        },
        {
            "name":"thread.lua",
            "dependencies":[]
        },
        "returnedobject.lua"
    ]
}
buildingLuau = None
if len(sys.argv) > 1:
    if sys.argv[1] in ("--lua","-lua"):
        buildingLuau = False
    elif sys.argv[1] == "--help":
        print("""Build mock linux system module.
    --help          Print help
    --lua
    -lua            Build optimized only for Lua 5.1+
    --compatibility
    -compat         Build a version that could run on both Roblox and Lua 5.1+
    --roblox
    -rbx            Build optimized only for Roblox, exports a folder with __main.lua if its a modulescript, its name as the folder name
""")
        exit(0)
    elif sys.argv[1] in ("--compatibility","-compat"):
        buildingLuau = None
    elif sys.argv[1] in ("--roblox","-rbx"):
        buildingLuau = True
filescontent = {}
for i in output["dependencies"]:
    if type(i) == dict:
        i = i["name"]
    filescontent[i] = []
    with open(i,"r") as fw:
        for line in fw.readlines():
            if line.startswith("--rbx "):
                if buildingLuau is True:
                    filescontent[i].append(line[len("--rbx "):])
            elif line.startswith("--compat "):
                if buildingLuau is None:
                    filescontent[i].append(line[len("--compat "):])
            elif line.startswith("--lua "):
                if buildingLuau is False:
                    filescontent[i].append(line[len("--lua "):])
            else:
                filescontent[i].append(line)

if buildingLuau is True:
    if os.path.exists(output["name"].split(".")[0]):
        os.rmdir(output["name"].split(".")[0])
    os.mkdir(output["name"].split(".")[0])
    with open(output["name"].split(".")[0]+"/__main.lua","w") as fw:
        pass
    for i in output["dependencies"]:
        if type(i) == dict:
            i = i["name"]
            with open(output["name"].split(".")[0]+"/"+i,"w") as fw:
                fw.writelines(filescontent[i])
        else:
            with open(output["name"].split(".")[0]+"/__main.lua","a") as fw:
                fw.writelines(filescontent[i])
else:
    with open(output["name"],"w") as fw:
        for i in output["dependencies"]:
            if type(i) == dict:
                i = i["name"]
            fw.writelines(filescontent[i])