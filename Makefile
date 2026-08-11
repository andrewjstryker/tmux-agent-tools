# tmux-agent-tools — developer tasks.

.PHONY: test lint

test:
	bats test

lint:
	@command -v shellcheck >/dev/null \
	  && shellcheck scripts/*.sh agent-tools.tmux \
	  || echo "shellcheck not installed; skipping"
