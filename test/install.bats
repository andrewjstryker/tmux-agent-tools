#!/usr/bin/env bats

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/aginstall.XXXXXX")"
  export FAKE_TMUX_STATE_DIR="$TESTDIR/tmux-state"
}

teardown() {
  [[ -n "${TESTDIR:-}" ]] && rm -rf "$TESTDIR"
}

@test "make install places only the executable facade in BINDIR" {
  run make -s -C "$ROOT" install \
    DESTDIR="$TESTDIR/stage" PREFIX=/usr BINDIR=/usr/bin
  [[ "$status" -eq 0 ]]

  installed="$TESTDIR/stage/usr/bin/agent"
  [[ -x "$installed" ]]
  cmp "$ROOT/agent" "$installed"
  [[ "$(find "$TESTDIR/stage" -type f | wc -l)" -eq 1 ]]
}
