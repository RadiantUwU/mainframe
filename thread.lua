local isRoblox = game and workspace and Vector3 and UDim2
if isRoblox then isRoblox = true else isRoblox = false end
local newThread
local stopThread
if isRoblox then
    function newThread(func, ...)
        return task.defer(func,...) -- do not immediately spawn it!
    end
    function deleteThread(thread)
        local status = coroutine.status(thread)
        if status == "normal" or status == "suspended" then
            task.close(thread)
            return
        elseif status == "dead"
            return
        end
        local hook
        hook = game:GetService("RunService").Heartbeat:Connect(function(dt)
            local status = coroutine.status(thread)
            if status == "normal" or status == "suspended" then
                task.close(thread)
                hook:Disconnect()
            elseif status == "dead"
                hook:Disconnect()
            end
        end)
    end
    function dispatchThread(thr,...)
        --already dispatching on next resumption cycle
    end
else --legacy support
    function newThread(func, ...)
        local thr = coroutine.create(func)
        return thr
    end
    function deleteThread(thread)
        --there is no valid way to make sure a thread is killed
    end
    function dispatchThread(thr,...)
        coroutine.resume(thr,...)
    end
end