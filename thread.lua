--rbx local isRoblox = true
--compat local isRoblox = game and workspace and Vector3 and UDim2
--compat if isRoblox then isRoblox = true else isRoblox = false end
--lua local isRoblox = false
local newThread
local deleteThread
local dispatchThread
local sleepWait
if isRoblox then
    function newThread(func, ...)
        return task.defer(func,...) -- do not immediately spawn it!
    end
    function deleteThread(thread)
        local status = coroutine.status(thread)
        if status == "normal" or status == "suspended" then
            task.close(thread)
            return
        elseif status == "dead" then
            return
        end
        local hook
        hook = game:GetService("RunService").Heartbeat:Connect(function(dt)
            local status = coroutine.status(thread)
            if status == "normal" or status == "suspended" then
                task.close(thread)
                hook:Disconnect()
            elseif status == "dead" then
                hook:Disconnect()
            end
        end)
    end
    function dispatchThread(thr,...)
        --already dispatching on next resumption cycle
    end
    function sleepWait(sec)
        task.wait(sec)
    end
else --legacy support
    function newThread(func, ...)
        local thr = coroutine.create(func)
        return thr
    end
    function deleteThread(thread)
        coroutine.close(thread)
    end
    function dispatchThread(thr,...)
        coroutine.resume(thr,...)
    end
    function sleepWait(sec)
        -- no existent method
    end
end
--rbx return {newThread=newThread,deleteThread=deleteThread,dispatchThread=dispatchThread,sleepWait=sleepWait}