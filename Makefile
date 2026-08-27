# tmux-agent-tools — developer tasks.

.PHONY: check test lint

check: test lint

test:
	bats test

lint:
	@if command -v shellcheck >/dev/null; then \
	  shellcheck operations/*.sh adapters/*/*.sh agent-tools.tmux; \
	else \
	  echo "shellcheck not installed; skipping"; \
	fi
