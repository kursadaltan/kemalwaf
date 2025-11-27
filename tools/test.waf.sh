#!/usr/bin/env bash
set -euo pipefail

#docker run --rm --network="host" -it -v ${PWD}/reports:/app/reports wallarm/gotestwaf --url=http://192.168.1.127:3030 --addHeader="Host: www.cloudapplicationsecurity.tr"


# portable WAF test runner - improved for macOS / python differences
# Usage: ./test.waf.sh <target_url>

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 <target_url>"
  exit 2
fi

echo "⚠️  Running active security tests against: $TARGET"
echo "Make sure you have authorization to test this target. Continue? (y/N)"
read -r CONFIRM
CONFIRM_LOWER="$(printf "%s" "$CONFIRM" | tr '[:upper:]' '[:lower:]')"
if [[ "$CONFIRM_LOWER" != "y" ]]; then
  echo "Aborting."
  exit 1
fi

WORKDIR="$(pwd)/waf_test_reports"
TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
OUTDIR="${WORKDIR}/${TIMESTAMP}"
mkdir -p "$OUTDIR"
echo "Reports will be written to: $OUTDIR"

# Paths
WAFNINJA_DIR="${HOME}/tools/WAFNinja"
XSSTRIKE_DIR="${HOME}/tools/XSStrike"
NIKTO_CMD="$(command -v nikto || true)"
PY3_BIN="$(command -v python3 || command -v python || true)"
PY2_BIN="$(command -v python2 || command -v python2.7 || true)"
PIP_CMD="$(command -v pip3 || command -v pip || true)"
GIT_CMD="$(command -v git || true)"
WKHTMLTOPDF="$(command -v wkhtmltopdf || true)"

# ensure minimal tools
if [[ -z "$PY3_BIN" || -z "$PIP_CMD" || -z "$GIT_CMD" ]]; then
  echo "Missing required tool (python3/pip/git). Install them and re-run."
  exit 3
fi

# ----- WAFNINJA (Python2 tool) -----
WAFNINJA_OUT_HTML="${OUTDIR}/wafninja_report.html"
if [[ ! -d "$WAFNINJA_DIR" ]]; then
  echo "Cloning WAFNinja into $WAFNINJA_DIR..."
  mkdir -p "$(dirname "$WAFNINJA_DIR")"
  git clone https://github.com/khalilbijjou/WAFNinja.git "$WAFNINJA_DIR"
fi

# Try to install requirements only if python2 available (WAFNinja is Python2)
if [[ -n "$PY2_BIN" ]]; then
  echo "Installing WAFNinja python2 requirements (via pip) — may require pip2 on your system..."
  # attempt pip for python2; try pip2 or pip pointing to python2
  if command -v pip2 >/dev/null 2>&1; then
    pip2 install -r "$WAFNINJA_DIR/requirements.txt" --user || true
  else
    # fallback: try python2 -m pip if available
    "$PY2_BIN" -m pip install -r "$WAFNINJA_DIR/requirements.txt" --user || true
  fi

  echo "Running WAFNinja (python2)..."
  pushd "$WAFNINJA_DIR" >/dev/null
  # WARN: WAFNinja may be outdated; output is mostly HTML/text
  if ! "$PY2_BIN" wafninja.py -u "$TARGET" -o "$WAFNINJA_OUT_HTML"; then
    echo "WAFNinja run failed (non-zero exit). Continuing with other tests."
  fi
  popd >/dev/null
  echo "WAFNinja report: $WAFNINJA_OUT_HTML"
else
  echo "python2 not found. Skipping WAFNinja (this tool requires Python 2)."
  echo "(Hint: install python2 or use the Docker-based runner I'll provide if you want.)"
fi

# ----- XSStrike (Python3) -----
if [[ ! -d "$XSSTRIKE_DIR" ]]; then
  echo "Cloning XSStrike into $XSSTRIKE_DIR..."
  mkdir -p "$(dirname "$XSSTRIKE_DIR")"
  git clone https://github.com/s0md3v/XSStrike.git "$XSSTRIKE_DIR"
  if [[ -f "$XSSTRIKE_DIR/requirements.txt" ]]; then
    echo "Installing XSStrike requirements..."
    "$PIP_CMD" install -r "$XSSTRIKE_DIR/requirements.txt" --user || true
  fi
fi

XS_OUT="${OUTDIR}/xsstrike.json"
echo "Running XSStrike (XSS fuzzing)..."
pushd "$XSSTRIKE_DIR" >/dev/null
# Current XSStrike uses --json and --log-file flags; write JSON to log-file
if "$PY3_BIN" xsstrike.py -u "$TARGET" --json > "$XS_OUT" 2>&1; then
  echo "XSStrike finished, output: $XS_OUT"
else
  echo "XSStrike returned non-zero exit. Check $XS_OUT (it may include error logs)."
fi
popd >/dev/null

# ----- Nikto (optional) -----
if [[ -n "$NIKTO_CMD" ]]; then
  echo "Running Nikto..."
  NIKTO_OUT="${OUTDIR}/nikto.txt"
  "$NIKTO_CMD" -h "$TARGET" -output "$NIKTO_OUT" || echo "Nikto finished with errors; check $NIKTO_OUT"
  echo "Nikto output: $NIKTO_OUT"
else
  echo "Nikto not found in PATH. Skipping."
fi

# ----- PDF conversion if possible -----
if [[ -x "$WKHTMLTOPDF" ]]; then
  echo "Converting HTML reports to PDF..."
  if [[ -f "$WAFNINJA_OUT_HTML" ]]; then
    "$WKHTMLTOPDF" "$WAFNINJA_OUT_HTML" "${OUTDIR}/wafninja_report.pdf" || echo "wkhtmltopdf failed for WAFNinja report"
  fi
  if [[ -f "$XS_OUT" ]]; then
    XS_HTML="${OUTDIR}/xsstrike_report.html"
    "$PY3_BIN" - <<PY > "$XS_HTML"
import json
j=json.load(open("$XS_OUT"))
html = "<html><head><meta charset='utf-8'><title>XSStrike Report</title></head><body><h1>XSStrike Report</h1><pre>{}</pre></body></html>".format(json.dumps(j, indent=2))
open("$XS_HTML","w").write(html)
PY
    "$WKHTMLTOPDF" "$XS_HTML" "${OUTDIR}/xsstrike_report.pdf" || echo "wkhtmltopdf failed for XSStrike report"
  fi
else
  echo "wkhtmltopdf not found; skipping PDF conversion."
fi

# ----- index -----
INDEX="${OUTDIR}/index.html"
cat > "$INDEX" <<HTML
<!doctype html>
<html><head><meta charset="utf-8"><title>WAF Test Report - ${TIMESTAMP}</title></head><body>
<h1>WAF Test Report - ${TIMESTAMP}</h1>
<ul>
  <li><a href="wafninja_report.html">WAFNinja HTML report</a> (if generated)</li>
  <li><a href="xsstrike.json">XSStrike JSON output</a></li>
  <li><a href="xsstrike_report.html">XSStrike HTML view</a> (if generated)</li>
  <li><a href="nikto.txt">Nikto output</a> (if generated)</li>
</ul>
</body></html>
HTML

echo "Done. Open $INDEX in your browser."
