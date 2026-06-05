TESTS_INIT=tests/init.lua
TESTS_DIR=tests/

.PHONY: all
all:unit_test

.PHONY: unit_test
unit_test:
	@nvim \
		--headless \
		--noplugin \
		-u ${TESTS_INIT} \
		-c "lua require('plenary.test_harness').test_directory('${TESTS_DIR}', { init = '${TESTS_INIT}' })"



