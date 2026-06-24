-- Test-suite entry point. Run via `make test`, i.e.
--   nvim --headless --noplugin -u tests/init.lua
-- It sets up the environment through the shared minimal init, then runs every
-- spec under tests/, spawning each spec in a child nvim that reuses the same
-- minimal init (so children get an identical, fully-configured environment).

local minimal_init = "tests/minimal_init.lua"
dofile(minimal_init)

vim.cmd("runtime plugin/plenary.vim")

local testdir = "tests/"
require("plenary.test_harness").test_directory(testdir, { minimal_init = minimal_init })
