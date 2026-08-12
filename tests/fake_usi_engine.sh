#!/usr/bin/env bash
set -u

# Deterministic USI fixture used by test_usi_engine.gd. It deliberately rejects
# movetime and malformed byoyomi so a test cannot pass via an implementation's
# accidental fallback. Modes are selected through FAKE_USI_MODE.
mode="${FAKE_USI_MODE:-normal}"
option_mode="${FAKE_USI_OPTIONS:-valid}"

emit_options() {
  case "$option_mode" in
    missing)
      printf '%s\n' 'option name uSi_LimitStrength type check default false'
      ;;
    invalid)
      printf '%s\n' 'option name uSi_LimitStrength type check default false'
      printf '%s\n' 'option name uSi_Strength type spin default 1 min 5 max 1'
      ;;
    unknown)
      printf '%s\n' 'option name EngineLevel type spin default 1 min 1 max 8'
      ;;
    invalid_integer)
      printf '%s\n' 'option name uSi_LimitStrength type check default false'
      printf '%s\n' 'option name uSi_Strength type spin default 1 min low max 8'
      ;;
    wrong_type)
      printf '%s\n' 'option name uSi_LimitStrength type spin default 0 min 0 max 1'
      printf '%s\n' 'option name uSi_Strength type check default false'
      ;;
    *)
      # Deliberately unusual case is part of the spelling contract.
      printf '%s\n' 'option name uSi_LimitStrength type check default false'
      printf '%s\n' 'option name uSi_Strength type spin default 1 min -2 max 3'
      ;;
  esac
}

while IFS= read -r line; do
  case "$line" in
    usi)
      if [[ "$mode" == no_usiok ]]; then
        printf '%s\n' 'id name Strict Fake USI (no usiok)'
        emit_options
        continue
      fi
      if [[ "$mode" == exit_handshake ]]; then
        exit 0
      fi
      printf '%s\n' 'id name Strict Fake USI'
      emit_options
      printf '%s\n' usiok
      ;;
    isready)
      if [[ "$mode" != no_ready ]]; then
        printf '%s\n' readyok
      fi
      ;;
    usinewgame)
      ;;
    position\ *)
      ;;
    go\ *)
      if [[ "$line" == *movetime* ]]; then
        exit 31
      fi
      if [[ ! "$line" =~ ^go[[:space:]]btime[[:space:]]0[[:space:]]wtime[[:space:]]0[[:space:]]byoyomi[[:space:]][0-9]+$ ]]; then
        exit 32
      fi
      case "$mode" in
        timeout)
          sleep 20
          ;;
        exit)
          exit 0
          ;;
        promotion)
          printf '%s\n' 'bestmove 2b3c+'
          ;;
        drop)
          printf '%s\n' 'bestmove P*7f'
          ;;
        resign)
          printf '%s\n' 'bestmove resign'
          ;;
        win)
          printf '%s\n' 'bestmove win'
          ;;
        invalid)
          printf '%s\n' 'bestmove not-a-usI-move'
          ;;
        none)
          printf '%s\n' 'bestmove 0000'
          ;;
        malformed)
          printf '%s\n' bestmove
          ;;
        *)
          printf '%s\n' 'bestmove 7g7f'
          ;;
      esac
      ;;
    setoption\ *)
      # The adapter is expected to use the advertised spelling exactly.
      ;;
    quit)
      exit 0
      ;;
    *)
      # Ignore harmless info/debug output, but reject unknown protocol commands.
      ;;
  esac
done
