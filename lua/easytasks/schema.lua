return {
    title = "Task Configuration",
    type = "object",
    additionalProperties = false,
    required = { "tasks" },
    properties = {
        tasks = {
            type = "array",
            description = "List of task definitions",
            additionalProperties = false,
            items = {
                type = "object",
                ["x-order"] = { "name", "type" },
                ["x-valueSelector"] = "loop.task.jsonhooks.select_taskobj",
                description = "Single task definition entry",
                properties = {
                    type = {
                        type = "string",
                        ["x-valueSelector"] = "loop.task.jsonhooks.select_tasktype",
                        enum = { "process", "composite", "debug", "build" },
                        description = "Task type (used to determine behavior)"
                    }
                },

                -- Polymorphic task definitions based on the 'type' field
                allOf = {
                    -- 1. PROCESS TASK
                    {
                        ["if"] = {
                            type = "object",
                            properties = { type = { const = "process" } }
                        },
                        ["then"] = {
                            description = "Definition of a `process` task",
                            ["x-order"] = { "name", "type", "save_buffers", "if_running", "depends_on", "depends_order", "command", "cwd", "env" },
                            ["x-valueSelector"] = "loop.task.jsonhooks.select_taskobj",
                            additionalProperties = false,
                            required = { "name", "type", "command" },
                            properties = {
                                type = { const = "process" },
                                name = { type = "string", minLength = 1, description = "Unique, non-empty name of the task" },
                                save_buffers = { type = "boolean", default = false, description = "If true, all modified workspace buffers will be saved before running the task" },
                                if_running = {
                                    type = "string",
                                    enum = { "restart", "refuse", "parallel" },
                                    ["x-enumDescriptions"] = {
                                        "Stop the current instance and start a new one",
                                        "Do not start a new instance if one is already running",
                                        "Start a new instance alongside any existing ones"
                                    },
                                    description = "Specifies what happens if the task is already running"
                                },
                                depends_on = {
                                    type = { "array", "null" },
                                    description =
                                    "List of task names that must complete successfully before this task runs.\nThis enforces a completion-based dependency order.\n",
                                    items = {
                                        type = "string",
                                        minLength = 1,
                                        ["x-valueSelector"] = "loop.task.jsonhooks.select_dependency",
                                        description = "Name of a task this task depends on"
                                    }
                                },
                                depends_order = {
                                    type = "string",
                                    enum = { "sequence", "parallel" },
                                    ["x-enumDescriptions"] = { "dependencies run one after another", "dependencies run concurrently" },
                                    description = "Specifies how dependencies listed in 'depends_on' are executed"
                                },
                                cwd = { type = { "string", "null" }, description = "Working directory used when executing the command" },
                                command = {
                                    description =
                                    "Command to execute. Can be a single string, or a list of string (program + args)",
                                    oneOf = {
                                        { type = "string", minLength = 1,                       description = "Command or process to execute, can include arguments" },
                                        {
                                            type = "array",
                                            minItems = 1,
                                            description = "Command with arguments, executed without shell interpolation",
                                            items = { type = "string", minLength = 1, description = "Command or argument token" }
                                        },
                                        { type = "null",   description = "No command execution" }
                                    }
                                },
                                env = {
                                    description = "Environment variables applied to the command execution",
                                    oneOf = {
                                        { type = "string", minLength = 1, description = "Environment variables applied to the command execution, format: VAR1=VALUE1 VAR2=VALUE2 ..." },
                                        {
                                            type = { "object", "null" },
                                            description =
                                            "Additional environment variables applied to the command execution",
                                            additionalProperties = { type = "string", description = "Environment variable value" }
                                        }
                                    }
                                }
                            }
                        }
                    },

                    -- 2. COMPOSITE TASK
                    {
                        ["if"] = {
                            type = "object",
                            properties = { type = { const = "composite" } }
                        },
                        ["then"] = {
                            description = "Definition of a `composite` task",
                            ["x-order"] = { "name", "type", "save_buffers", "if_running", "depends_on", "depends_order" },
                            ["x-valueSelector"] = "loop.task.jsonhooks.select_taskobj",
                            additionalProperties = false,
                            required = { "name", "type" },
                            properties = {
                                type = { const = "composite" },
                                name = { type = "string", minLength = 1, description = "Unique, non-empty name of the task" },
                                save_buffers = { type = "boolean", default = false, description = "If true, all modified workspace buffers will be saved before running the task" },
                                if_running = {
                                    type = "string",
                                    enum = { "restart", "refuse", "parallel" },
                                    ["x-enumDescriptions"] = {
                                        "Stop the current instance and start a new one",
                                        "Do not start a new instance if one is already running",
                                        "Start a new instance alongside any existing ones"
                                    },
                                    description = "Specifies what happens if the task is already running"
                                },
                                depends_on = {
                                    type = { "array", "null" },
                                    description =
                                    "List of task names that must complete successfully before this task runs.\nThis enforces a completion-based dependency order.\n",
                                    items = {
                                        type = "string",
                                        minLength = 1,
                                        ["x-valueSelector"] = "loop.task.jsonhooks.select_dependency",
                                        description = "Name of a task this task depends on"
                                    }
                                },
                                depends_order = {
                                    type = "string",
                                    enum = { "sequence", "parallel" },
                                    ["x-enumDescriptions"] = { "dependencies run one after another", "dependencies run concurrently" },
                                    description = "Specifies how dependencies listed in 'depends_on' are executed"
                                }
                            }
                        }
                    },

                    -- 3. DEBUG TASK
                    {
                        ["if"] = {
                            type = "object",
                            properties = { type = { const = "debug" } }
                        },
                        ["then"] = {
                            type = "object",
                            description = "Definition of a `debug` task",
                            ["x-order"] = { "name", "type", "save_buffers", "if_running", "depends_on", "depends_order", "command", "cwd", "debugger", "host", "port", "request", "terminate_on_disconnect", "debug_options" },
                            ["x-valueSelector"] = "loop.task.jsonhooks.select_taskobj",
                            additionalProperties = false,
                            required = { "name", "type", "debugger", "request" },
                            properties = {
                                type = { const = "debug" },
                                name = { type = "string", minLength = 1, description = "Unique, non-empty name of the task" },
                                debugger = { type = "string", ["x-valueSelector"] = "loop-debug.tools.dbgselect.select", description = "Debugger backend to use (e.g. gdb, lldb, node, python)." },
                                request = { type = "string", enum = { "launch", "attach" }, description = "How to start debugging: 'launch' starts a new process, 'attach' connects to an existing one." },
                                save_buffers = { type = "boolean", default = false, description = "If true, all modified workspace buffers will be saved before running the task" },
                                if_running = {
                                    type = "string",
                                    enum = { "restart", "refuse", "parallel" },
                                    ["x-enumDescriptions"] = {
                                        "Stop the current instance and start a new one",
                                        "Do not start a new instance if one is already running",
                                        "Start a new instance alongside any existing ones"
                                    },
                                    description = "Specifies what happens if the task is already running"
                                },
                                depends_on = {
                                    type = { "array", "null" },
                                    description =
                                    "List of task names that must complete successfully before this task runs.\nThis enforces a completion-based dependency order.\n",
                                    items = {
                                        type = "string",
                                        minLength = 1,
                                        ["x-valueSelector"] = "loop.task.jsonhooks.select_dependency",
                                        description = "Name of a task this task depends on"
                                    }
                                },
                                depends_order = {
                                    type = "string",
                                    enum = { "sequence", "parallel" },
                                    ["x-enumDescriptions"] = { "dependencies run one after another", "dependencies run concurrently" },
                                    description = "Specifies how dependencies listed in 'depends_on' are executed"
                                },
                                command = {
                                    description = "Command used to start the debugger or debug adapter.",
                                    oneOf = {
                                        { type = "string" },
                                        { type = "array", items = { type = "string" } }
                                    }
                                },
                                cwd = { type = "string", description = "Working directory for the debug session. Defaults to `${wsdir}` if not specified" },
                                env = {
                                    type = "object",
                                    description = "Environment variables passed to the debugged process.",
                                    additionalProperties = { type = "string" }
                                },
                                terminate_on_disconnect = { type = "boolean", description = "Terminate the debugged process when the debugger disconnects." },
                                host = { type = "string", minLength = 1, description = "Host name for the remote debugger" },
                                port = { type = "number", description = "Port number for the remote debugger" },
                                debug_options = {
                                    type = "object",
                                    additionalProperties = true,
                                    description =
                                    "Arbitrary key-value pairs passed specifically to the debugger backend."
                                }
                            },
                            -- Nested validation conditional for remote debugging context
                            ["if"] = {
                                type = "object",
                                properties = { debugger = { const = "remote" } }
                            },
                            ["then"] = {
                                type = "object",
                                required = { "host", "port" }
                            }
                        }
                    },

                    -- 4. BUILD TASK
                    {
                        ["if"] = {
                            type = "object",
                            properties = { type = { const = "build" } }
                        },
                        ["then"] = {
                            __name = "Command",
                            description = "Definition of a `build` task",
                            ["x-order"] = { "name", "type", "save_buffers", "if_running", "depends_on", "depends_order", "command", "cwd", "env", "quickfix_matcher" },
                            ["x-valueSelector"] = "loop.task.jsonhooks.select_taskobj",
                            additionalProperties = false,
                            required = { "name", "type", "command" },
                            properties = {
                                type = { const = "build" },
                                name = { type = "string", minLength = 1, description = "Unique, non-empty name of the task" },
                                save_buffers = { type = "boolean", default = false, description = "If true, all modified workspace buffers will be saved before running the task" },
                                if_running = {
                                    type = "string",
                                    enum = { "restart", "refuse", "parallel" },
                                    ["x-enumDescriptions"] = {
                                        "Stop the current instance and start a new one",
                                        "Do not start a new instance if one is already running",
                                        "Start a new instance alongside any existing ones"
                                    },
                                    description = "Specifies what happens if the task is already running"
                                },
                                depends_on = {
                                    type = { "array", "null" },
                                    description =
                                    "List of task names that must complete successfully before this task runs.\nThis enforces a completion-based dependency order.\n",
                                    items = {
                                        type = "string",
                                        minLength = 1,
                                        ["x-valueSelector"] = "loop.task.jsonhooks.select_dependency",
                                        description = "Name of a task this task depends on"
                                    }
                                },
                                depends_order = {
                                    type = "string",
                                    enum = { "sequence", "parallel" },
                                    ["x-enumDescriptions"] = { "dependencies run one after another", "dependencies run concurrently" },
                                    description = "Specifies how dependencies listed in 'depends_on' are executed"
                                },
                                cwd = { type = { "string", "null" }, description = "Working directory used when executing the command" },
                                quickfix_matcher = { type = { "string", "null" }, description = "Name of a quickfix matcher used to parse command output into quickfix entries" },
                                command = {
                                    description =
                                    "Command to execute. Can be a single string, a list of arguments, or null to disable execution.",
                                    oneOf = {
                                        { type = "string", minLength = 1,                       description = "Shell command executed as-is" },
                                        {
                                            type = "array",
                                            minItems = 1,
                                            description = "Command with arguments, executed without shell interpolation",
                                            items = { type = "string", minLength = 1, description = "Command or argument token" }
                                        },
                                        { type = "null",   description = "No command execution" }
                                    }
                                },
                                env = {
                                    description = "Environment variables applied to the command execution",
                                    oneOf = {
                                        { type = "string", minLength = 1, description = "Environment variables applied to the command execution, format: VAR1=VALUE1 VAR2=VALUE2 ..." },
                                        {
                                            type = { "object", "null" },
                                            description =
                                            "Additional environment variables applied to the command execution",
                                            additionalProperties = { type = "string", description = "Environment variable value" }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
