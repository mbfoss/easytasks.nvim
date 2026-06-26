TESTS_INIT=tests/init.lua
TESTS_DIR=tests/

.PHONY: all
all:test

.PHONY: unit_test
unit_test:
	@nvim \
		--headless \
		--noplugin \
		-u ${TESTS_INIT} \

.PHONY: test
test: unit_test

# Re-vendor the TOML engine from upstream (see development.md). Pass REF to pin a
# branch/tag/commit, e.g. `make update-tomltools REF=v1.2.3`.
.PHONY: update-tomltools
update-tomltools:
	@scripts/update-tomltools.sh ${REF}


