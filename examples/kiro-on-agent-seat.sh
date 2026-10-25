#!/usr/bin/env bash
# Electron 앱(예: Kiro)을 에이전트 워크스페이스 99에 접근성 트리를 켠 채 띄운다.
#
# - --force-renderer-accessibility만으로는 AT-SPI 레지스트리에 붙지 않는다. ACCESSIBILITY_ENABLED=1이 같이 필요하다.
# - 배포판 래퍼(/usr/bin/kiro 등)는 ELECTRON_RUN_AS_NODE로 cli.js를 부르는 경우가 많아 플래그가 안 먹는다 — 실제 바이너리를 부른다.
# - 단일 인스턴스 앱은 이미 떠 있으면 새 플래그가 무시된다 — 먼저 완전히 닫는다.
set -euo pipefail

BIN=${1:-/opt/Kiro/kiro}

agent-display up
hypruse launch --workspace 99 --wait 30 env ACCESSIBILITY_ENABLED=1 "$BIN" -- --force-renderer-accessibility
