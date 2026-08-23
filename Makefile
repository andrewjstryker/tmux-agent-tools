# tmux-agent-tools — developer tasks.

.PHONY: test lint

test:
	bats test

lint:
	@if command -v shellcheck >/dev/null; then \
	  shellcheck scripts/*.sh integrations/*.sh agent-tools.tmux; \
	else \
	  echo "shellcheck not installed; skipping"; \
	fi
