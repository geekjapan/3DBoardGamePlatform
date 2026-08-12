#!/usr/bin/env bash
set -u

# Minimal deterministic UCI peer for T28 result-normalization regression tests.
mode="${FAKE_UCI_MODE:-normal}"

while IFS= read -r line; do
  case "$line" in
    uci)
      printf '%s\n' 'id name Strict Fake UCI' uciok
      ;;
    isready)
      printf '%s\n' readyok
      ;;
    ucinewgame|position\ *|setoption\ *)
      ;;
    go\ *)
      case "$mode" in
        resign) printf '%s\n' 'bestmove resign' ;;
        zero) printf '%s\n' 'bestmove 0000' ;;
        none) printf '%s\n' 'bestmove (none)' ;;
        *) printf '%s\n' 'bestmove e2e4' ;;
      esac
      ;;
    quit)
      exit 0
      ;;
  esac
done
