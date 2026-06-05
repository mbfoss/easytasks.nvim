-- Composite tasks have no command of their own; their entire behaviour is
-- the dependency resolution done by exec.lua before run() is called.
---@type easytasks.TaskTypeDef
return {
    run = function(_, _, on_done)
        on_done(true)
    end,
}
