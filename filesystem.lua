local function newFileSystem(processSystem)
    local function newFolder(name,parent,owner,permissionstring)
        local object = setmetatable({},fileobjectmt)
        _objectname[object] = name
        _objectparent[object] = parent
        _objectowner[object] = owner
        _objectpermission[object] = permstrtoint(permissionstring)
        _objectisFolder[object] = true
        _objectprocesssystem[object] = processSystem
        _foldercontent[object] = {}
        if parent then
            _foldercontent[parent][name] = object
        end
        return object
    end
    local function newFile(name,parent,owner,permissionstring,content)
        content = content or ""
        local object = setmetatable({},fileobjectmt)
        _objectname[object] = name
        _objectparent[object] = parent
        _objectowner[object] = owner
        _objectpermission[object] = permstrtoint(permissionstring)
        _objectisFolder[object] = true
        _objectprocesssystem[object] = processSystem
        _filecontent[object] = content
        if parent then
            _foldercontent[parent][name] = object
        end
        return object
    end
    local function _newFolder(name,parent,owner,permissions)
        local object = setmetatable({},fileobjectmt)
        _objectname[object] = name
        _objectparent[object] = parent
        _objectowner[object] = owner
        _objectpermission[object] = permissions
        _objectisFolder[object] = true
        _objectprocesssystem[object] = processSystem
        _foldercontent[object] = {}
        if parent then
            _foldercontent[parent][name] = object
        end
        return object
    end
    local function _newFile(name,parent,owner,permissions,content)
        content = content or ""
        local object = setmetatable({},fileobjectmt)
        _objectname[object] = name
        _objectparent[object] = parent
        _objectowner[object] = owner
        _objectpermission[object] = permissions
        _objectisFolder[object] = true
        _objectprocesssystem[object] = processSystem
        _filecontent[object] = content
        if parent then
            _foldercontent[parent][name] = object
        end
        return object
    end
    local rootfs = newFolder("",nil,"root","rwxr-xr-x")
    local function ProcNewFolder(name,path,permissions)
        local process = processSystem.processthreads[coroutine.running()]
        if not process then error("not a process",2) end
        local folder = FSGoTo(path,rootfs)
        if not folder:canWrite() then error("access denied.",2) end
        return _newFolder(name,folder,process.user,permissions)
    end
    local function ProcNewFile(name,path,permissions,content)
        local process = processSystem.processthreads[coroutine.running()]
        if not process then error("not a process",2) end
        local folder = FSGoTo(path,rootfs)
        if not folder:canWrite() then error("access denied.",2) end
        return _newFile(name,folder,process.user,permissions,content)
    end
    return rootfs,{
        newFolder=ProcNewFolder,
        newFile=ProcNewFile,
        _newFolder=newFolder,
        _newFile=newFile,
        getPath=function (path)
            return FSGoTo(path,rootfs)
        end
    }
end