#!/usr/bin/env bash
# CY-CLI Linux launcher (parity with packaging/macos/launcher).
#
#   1. Resolves a CY API key (ENV, ~/.cy/auth.json — cyclic field search
#      CY_API_KEY|openai_api_key|OPENAI_API_KEY|api_key|API_KEY) and writes it
#      to ~/.cy/auth.json so the `cy` CLI can authenticate.
#   2. Starts the local responses->chat bridge (python3, port 8790) if it is
#      not already running, passing the key into its environment. The bridge
#      also serves GET /v1/models and HEAD for reachability checks.
#   3. Writes a default ~/.cy/config.toml with base_url=http://127.0.0.1:8790/v1.
#   4. Opens a terminal (x-terminal-emulator / gnome-terminal / konsole /
#      xfce4-terminal / xterm, inline fallback) showing the big pink CY splash,
#      then runs `cy` in a real TTY with CY_API_KEY exported.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CY_HOME="${CY_HOME:-$HOME/.cy}"
PORT="${CY_BRIDGE_PORT:-8790}"
mkdir -p "$CY_HOME"

AUTH_FILE="$CY_HOME/auth.json"
CONFIG="$CY_HOME/config.toml"

KEY_FIELDS="CY_API_KEY openai_api_key OPENAI_API_KEY api_key API_KEY"

# --- Resolve the cy binary ---------------------------------------------------
CY_BIN=""
for c in "$SCRIPT_DIR/cy" "$SCRIPT_DIR/bin/cy" "$HOME/.local/share/cy/bin/cy"; do
  if [ -x "$c" ]; then CY_BIN="$c"; break; fi
done
if [ -z "$CY_BIN" ]; then
  CY_BIN="$(command -v cy 2>/dev/null || true)"
fi
if [ -z "$CY_BIN" ]; then
  echo "CY: cy binary not found. Run the install script first." >&2
  exit 1
fi

# --- Resolve the bridge script ------------------------------------------------
BRIDGE=""
for b in "$SCRIPT_DIR/cy_bridge.py" \
         "$SCRIPT_DIR/../packaging/bridge/cy_bridge.py" \
         "$SCRIPT_DIR/../packaging/macos/cy_bridge.py"; do
  if [ -f "$b" ]; then BRIDGE="$(cd "$(dirname "$b")" && pwd)/$(basename "$b")"; break; fi
done

# --- Resolve the API key (ENV first, cyclic field order) ----------------------
KEY=""
for f in $KEY_FIELDS; do
  v="$(printenv "$f" 2>/dev/null || true)"
  if [ -n "$v" ]; then KEY="$v"; break; fi
done

if [ -z "$KEY" ] && [ -f "$AUTH_FILE" ]; then
  if command -v python3 >/dev/null 2>&1; then
    KEY="$(python3 - "$AUTH_FILE" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as fh:
        data = json.load(fh)
    for field in ("CY_API_KEY", "openai_api_key", "OPENAI_API_KEY", "api_key", "API_KEY"):
        v = data.get(field)
        if isinstance(v, str) and v.strip():
            print(v.strip())
            break
except Exception:
    pass
PY
)"
  else
    for f in $KEY_FIELDS; do
      KEY="$(sed -n "s/.*\"$f\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$AUTH_FILE" 2>/dev/null | head -1 || true)"
      if [ -n "$KEY" ]; then break; fi
    done
  fi
fi
# Strip surrounding whitespace.
KEY="$(printf '%s' "$KEY" | tr -d '[:space:]')"

if [ -z "$KEY" ]; then
  # No key anywhere: open the CY authorization page in the browser and surface
  # a branded, readable message (CY Engine v2 phrase).
  for opener in xdg-open sensible-browser x-www-browser; do
    if command -v "$opener" >/dev/null 2>&1; then
      "$opener" "https://auth.symbiotyc.workers.dev" >/dev/null 2>&1 || true
      break
    fi
  done
  cat <<'NO_KEY' >&2

  ██████╗██╗   ██╗
 ██╔════╝╚██╗ ██╔╝
 ██║      ╚████╔╝
 ██║       ╚██╔╝
 ╚██████╗   ██║
  ╚═════╝   ╚═╝

  Тебе нужен API ключ.
  Открыли страницу авторизации в браузере: https://auth.symbiotyc.workers.dev
  1. Войди через Google — получишь ключ вида cfat_...
  2. Сохрани его:  cy login --with-api-key
     или:  export CY_API_KEY=cfat_...
  3. Запусти CY заново.

NO_KEY
  exit 1
fi

# --- Write auth.json (overwrite empty one) ------------------------------------
printf '{\n  "auth_mode": "apiKey",\n  "openai_api_key": "%s"\n}\n' "$KEY" > "$AUTH_FILE"
chmod 600 "$AUTH_FILE"

# --- Start the local bridge if it is not already running -----------------------
port_open() {
  bash -c "exec 3<>/dev/tcp/127.0.0.1/$PORT" 2>/dev/null
}

if ! port_open; then
  if [ -z "$BRIDGE" ]; then
    echo "CY: cy_bridge.py not found; continuing without local bridge." >&2
  else
    PYTHON="$(command -v python3 || true)"
    if [ -z "$PYTHON" ]; then
      echo "CY: python3 not found. Install Python 3 and try again." >&2
      exit 1
    fi
    CY_API_BASE_URL="${CY_API_BASE_URL:-https://cy.symbiotyc.workers.dev/v1}" \
    CY_BRIDGE_PORT="$PORT" \
    CY_HOME="$CY_HOME" \
    CY_API_KEY="$KEY" \
    nohup "$PYTHON" "$BRIDGE" >"$CY_HOME/bridge.log" 2>&1 &
    disown 2>/dev/null || true
    for _ in $(seq 1 50); do
      if port_open; then break; fi
      sleep 0.1
    done
  fi
fi

# --- Seed SYMBIOTYC-branded syntax themes on first launch ----------------------
# Copies any bundled .tmTheme files into ~/.cy/themes/ without ever
# overwriting existing ones (the user might have edited a theme).
THEMES_SRC="$SCRIPT_DIR/themes"
THEMES_DST="$CY_HOME/themes"
if [ -d "$THEMES_SRC" ]; then
  mkdir -p "$THEMES_DST"
  for t in "$THEMES_SRC"/*.tmTheme; do
    [ -f "$t" ] || continue
    name="$(basename "$t")"
    if [ ! -f "$THEMES_DST/$name" ]; then
      cp "$t" "$THEMES_DST/$name"
    fi
  done
fi

# --- Config (always written to ensure correct port) ----------------------------
cat > "$CONFIG" <<EOF
# CY Config - generated by CY-CLI launcher
model = "cy/i1a"
model_provider = "symbiotyc"
model_context_window = 128000
model_auto_compact_token_limit = 96000
model_reasoning_summary = "auto"
model_reasoning_effort = "none"
approval_policy = "never"

[model_providers.symbiotyc]
name = "SYMBIOTYC"
base_url = "http://127.0.0.1:$PORT/v1"
wire_api = "responses"
supports_websockets = false
models = ["cy/i1a"]
EOF

# --- Build the first-screen splash (big pink CY ASCII art) ----------------------
#   1;35 = bold magenta (pink), 0 = reset, 1;36 = bold cyan, 2;37 = dim grey.
ESC=$'\033'
PINK="${ESC}[1;35m"
CYAN="${ESC}[1;36m"
DIM="${ESC}[2;37m"
RESET="${ESC}[0m"

SPLASH_FILE="$CY_HOME/.splash.ansi"
cat > "$SPLASH_FILE" <<SPLASH_EOF
${PINK}
  ██████╗██╗   ██╗
 ██╔════╝╚██╗ ██╔╝
 ██║      ╚████╔╝
 ██║       ╚██╔╝
 ╚██████╗   ██║
  ╚═════╝   ╚═╝${RESET}

 ${PINK}CY${RESET} ${DIM}— Symbiotic Coding Assistant${RESET}
 ${DIM}Loading TUI...${RESET}
SPLASH_EOF

# --- Inner script executed by the terminal emulator -----------------------------
INNER="$CY_HOME/.cy_launch.sh"
cat > "$INNER" <<INNER_EOF
#!/bin/bash
export CX_HOME='$CY_HOME'
export CODEX_HOME='$CY_HOME'
export CY_API_KEY='$KEY'
clear
cat '$SPLASH_FILE'
cd '$HOME' && '$CY_BIN'
rm -f '$SPLASH_FILE'
rm -f '$INNER'
exec bash
INNER_EOF
chmod +x "$INNER"

# --- Open a terminal with the splash, then the CLI -------------------------------
if command -v x-terminal-emulator >/dev/null 2>&1; then
  x-terminal-emulator -e bash "$INNER" >/dev/null 2>&1 &
elif command -v gnome-terminal >/dev/null 2>&1; then
  gnome-terminal -- bash "$INNER" >/dev/null 2>&1 &
elif command -v konsole >/dev/null 2>&1; then
  konsole -e bash "$INNER" >/dev/null 2>&1 &
elif command -v xfce4-terminal >/dev/null 2>&1; then
  xfce4-terminal -e "bash '$INNER'" >/dev/null 2>&1 &
elif command -v xterm >/dev/null 2>&1; then
  xterm -e bash "$INNER" >/dev/null 2>&1 &
else
  # No terminal emulator (headless/SSH): run inline in the current TTY.
  echo "CY: no terminal emulator found; launching inline." >&2
  export CX_HOME="$CY_HOME"
  export CODEX_HOME="$CY_HOME"
  export CY_API_KEY="$KEY"
  clear || true
  cat "$SPLASH_FILE"
  cd "$HOME"
  exec "$CY_BIN"
fi
