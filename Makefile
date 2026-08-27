# tmux-agent-tools — developer tasks.

.PHONY: check test lint

check: test lint

test:
	bats test

lint:
	@if command -v shellcheck >/dev/null; then \
	  shellcheck agent.sh lib/*.sh adapters/*/*.sh agent-tools.tmux \
	    test/support/fake-airline test/support/fake-tmux test/lint-architecture.sh; \
	else \
	  echo "shellcheck not installed; skipping"; \
	fi
	@test/lint-architecture.sh
