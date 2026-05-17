local schema = {
    title = "Loop Variables Configuration",
    description = "Configuration file for loop.nvim custom variables",
    type = "object",
    additionalProperties = false,
    required = { "workspace" },
    properties = {
        workspace = {
            type = "object",
            required = { "name", "files" },
            ["x-order"] = { "name", "files" },
            properties = {
                name = {
                    type = { "string" },
                    default = "",
                    description = "Workspace name",
                },
                files = {
                    type = { "object", "null" },
                    description = "File saving/filtering options",
                    default = {},
                    required = { "include", "exclude", "follow_symlinks" },
                    ["x-order"] = { "include", "exclude", "follow_symlinks" },
                    properties = {
                        include = {
                            type = { "array" },
                            description = "Glob patterns for files to include when saving",
                            items = { type = "string" },
                        },
                        exclude = {
                            type = { "array" },
                            description = "Glob patterns for files/directories to exclude when saving",
                            items = { type = "string" },
                        },
                        follow_symlinks = {
                            type = { "boolean" },
                            description = "Whether to follow symbolic links when scanning files for saving",
                        },
                    },
                    additionalProperties = false,
                },
            },
            additionalProperties = false,

        },
    },
}


return schema
