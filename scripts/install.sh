#!/bin/zsh
set -euo pipefail

echo "[SU1VolumeBridge] Установка..."

if ! xcode-select -p >/dev/null 2>&1; then
  echo "[!] Требуются Xcode Command Line Tools. Устанавливаю..."
  xcode-select --install || true
  echo "Запустите скрипт повторно после установки CLT."; exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "[!] Homebrew не найден. Установите с https://brew.sh и повторите."; exit 1
fi

echo "[brew] Установка Background Music..."
brew install --cask background-music || true

APP_SUPPORT_DIR="$HOME/Library/Application Support/SU1VolumeBridge"
BIN_DIR="$APP_SUPPORT_DIR/bin"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)/launchagents"

mkdir -p "$BIN_DIR"
mkdir -p "$LAUNCH_AGENTS_DIR"

echo "[swift] Сборка CLI..."
pushd "$(cd "$(dirname "$0")/.." && pwd)/su1-volume-bridge" >/dev/null
swift build -c release
cp -f .build/release/su1-volume-bridge "$BIN_DIR/"
popd >/dev/null

echo "[launchd] Установка LaunchAgent..."
PLIST_ID="com.deagle.su1volumebridge"
sed "s#/Users/jamesondeagle#$HOME#g" "$PLIST_SRC_DIR/$PLIST_ID.plist" > "$LAUNCH_AGENTS_DIR/$PLIST_ID.plist"
launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_ID.plist" >/dev/null 2>&1 || true
launchctl load -w "$LAUNCH_AGENTS_DIR/$PLIST_ID.plist"

echo "[login items] Добавление Background Music в автозапуск (через macOS)..."
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Background Music.app", hidden:true}' || true

echo "[perm] Сделаю скрипты исполняемыми..."
chmod +x "$(cd "$(dirname "$0")" && pwd)/install.sh" || true
chmod +x "$(cd "$(dirname "$0")" && pwd)/uninstall.sh" || true

echo "[done] Демон будет запущен launchd автоматически."

echo "Готово. Перейдите в System Settings → Sound и убедитесь, что активен «Background Music»."


