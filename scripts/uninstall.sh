#!/bin/zsh
set -euo pipefail

echo "[SU1VolumeBridge] Удаление..."

APP_SUPPORT_DIR="$HOME/Library/Application Support/SU1VolumeBridge"
BIN_DIR="$APP_SUPPORT_DIR/bin"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_ID="com.deagle.su1volumebridge"

echo "[launchd] Отключение LaunchAgent..."
launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_ID.plist" >/dev/null 2>&1 || true
rm -f "$LAUNCH_AGENTS_DIR/$PLIST_ID.plist"

echo "[files] Удаление бинарей..."
rm -rf "$APP_SUPPORT_DIR"

echo "[brew] (опционально) Сохранение Background Music — пропускаю"

echo "Готово. При необходимости вручную удалите Background Music из Login Items."


