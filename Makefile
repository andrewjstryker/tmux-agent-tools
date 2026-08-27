# tmux-agent-tools — installation and developer tasks.

.PHONY: install check test lint

PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

install:
	install -d "$(DESTDIR)$(BINDIR)"
	install -m 755 agent "$(DESTDIR)$(BINDIR)/agent"

check: test lint

test:
	bats test

lint:
	@if command -v shellcheck >/dev/null; then \
	  shellcheck agent agent.sh agent.tmux lib/*.sh adapters/*/*.sh \
	    test/support/fake-airline test/support/fake-tmux test/lint-architecture.sh; \
	else \
	  echo "shellcheck not installed; skipping"; \
	fi
	@test/lint-architecture.sh
