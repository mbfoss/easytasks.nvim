local ordered = require("easytasks.util.table_util").ordered

--- Debug templates are projected from easydap's per-adapter named configurations
--- rather than hand-maintained: one entry per (adapter, configuration) that
--- easydap declares, with `parameters` prefilled for the configuration's
--- required inputs. This keeps the template list in lockstep with whatever
--- adapters easydap ships.

--- Build the `parameters` skeleton for one (adapter, configuration): every
--- required input, in sorted order. Each starting value comes from easydap's input
--- registry, so a seeded task is written in the same authored form the tasks-file
--- schema demands of it (a `shell_args` input seeds the command line you type, not
--- the argument list easydap splits it into).
---@param sch table  the `easydap.schema` module
---@param adapter string
---@param configuration_name string
---@return table params, string[] order  empty when the configuration requires nothing
local function _parameters(sch, adapter, configuration_name)
    local dap_inputs = require("easydap.inputs")
    local required   = sch.configuration_required(adapter, configuration_name)
    local inputs     = sch.configuration_inputs(adapter, configuration_name)
    local params, order = {}, {}
    for _, name in ipairs(required) do
        params[name] = dap_inputs.seed(inputs[name])
        order[#order + 1] = name
    end
    return params, order
end

---@return easytasks.TaskTemplate[]
return function()
    local sch = require("easydap.schema")
    local templates = {}
    for _, adapter in ipairs(sch.configurable_adapters()) do
        for _, configuration_name in ipairs(sch.configuration_names(adapter)) do
            local task_keys = { "name", "type", "adapter", "configuration" }
            local task = {
                name          = "debug-" .. adapter,
                type          = "debug",
                adapter       = adapter,
                configuration = configuration_name,
            }
            local params, order = _parameters(sch, adapter, configuration_name)
            if #order > 0 then
                task.parameters = ordered(params, order)
                task_keys[#task_keys + 1] = "parameters"
            end
            templates[#templates + 1] = {
                label = ("%s (%s)"):format(adapter, configuration_name),
                task  = ordered(task, task_keys),
            }
        end
    end
    return templates
end
