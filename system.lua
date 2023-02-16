local function newSystem()
    local pr = newProcessTable()
    local rootfs,du = newFileSystem(pr)
    local newFolder = du._newFolder
    local rootrw = "rwxr-xr-x"
    local bindir = newFolder("bin",rootfs,"root",rootrw)
    local devdir = newFolder("dev",rootfs,"root",rootrw)
    local sbindir = newFolder("sbin",rootfs,"root",rootrw)
    local etcdir = newFolder("etc",rootfs,"root",rootrw)
    local homedir = newFolder("home",rootfs,"root",rootrw)
    local mntdir = newFolder("mnt",rootfs,"root",rootrw)
    local mediadir = newFolder("media",rootfs,"root",rootrw)
end