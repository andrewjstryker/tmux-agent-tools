# tmux-agent-tools — installation and developer tasks.

.PHONY: install check release-check airline-contract widget-integration test lint

PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

install:
	install -d "$(DESTDIR)$(BINDIR)"
	install -m 755 agent "$(DESTDIR)$(BINDIR)/agent"

check: test lint

release-check: check airline-contract widget-integration

airline-contract:
	@test/airline-contract.sh "$(AIRLINE_SOURCE)"

widget-integration:
	@test/widget-integration.sh "$(AIRLINE_SOURCE)"

test:
	bats test

lint:
	@if command -v shellcheck >/dev/null; then \
	  shellcheck agent agent.sh agent.tmux lib/*.sh adapters/*/*.sh widgets/*.sh \
	    test/support/fake-airline test/support/fake-tmux \
	    test/airline-contract.sh test/widget-integration.sh; \
	else \
	  echo "shellcheck not installed; skipping"; \
	fi
