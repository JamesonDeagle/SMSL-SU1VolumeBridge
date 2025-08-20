## SU1VolumeBridge

Набор утилит для включения системной регулировки громкости (F11/F12) с ЦАП SMSL SU-1 на macOS через прослойку Background Music.

### Что внутри
- `su1-volume-bridge/` — Swift CLI-демон (SPM), следит за появлением/пропаданием SU-1, включает Background Music как `Default Output` и (в дальнейшем) настраивает его вывод на SU-1. Есть режим Bypass.
- `launchagents/com.deagle.su1volumebridge.plist` — LaunchAgent для автозапуска демона при логине.
- `scripts/install.sh` / `scripts/uninstall.sh` — установка и удаление (brew + login item + LaunchAgent + сборка CLI).
- `task.md` — постановка задачи.

### Установка
```bash
./scripts/install.sh
```

Требования: Xcode Command Line Tools, Homebrew. Скрипт проверит и подскажет, если чего-то не хватает.

После установки:
- В System Settings → Sound активным станет устройство `Background Music`.
- Демон будет запущен и добавлен в автозапуск.

### Управление
После установки бинарь ставится в `~/Library/Application Support/SU1VolumeBridge/bin/su1-volume-bridge`.

Примеры:
```bash
su1-volume-bridge --bypass on     # дефолтный выход: SMSL SU-1 (бит-перфект, системные клавиши не работают)
su1-volume-bridge --bypass off    # дефолтный выход: Background Music (системные клавиши работают)
su1-volume-bridge --bypass toggle # переключить режим
su1-volume-bridge --daemon        # запустить в фоне (обычно делает launchd)
```

### Статус интеграции с Background Music
- Запуск и установка как Default Output — готово.
- Программный выбор выходного устройства внутри Background Music — используется AppleScript API (`BGMApp.sdef`):
  - перечисление устройств: `tell application "Background Music" to get name of every output device`
  - выбор SU-1: `tell application "Background Music" to set selected output device to (output device "SMSL USB AUDIO")`
  - на macOS 15 возможен пробел в конце имени: используйте точное имя из перечисления.

### Удаление
```bash
./scripts/uninstall.sh
```

### Panic button
Если пропал звук:
- В System Settings → Sound вручную выберите «MacBook Pro Speakers» или свои наушники.
- Запустите «Background Music» из /Applications заново.
- Дайте доступ «Микрофон» приложению Background Music в System Settings → Privacy & Security → Microphone.

### Сборка BGM из исходников (опционально)
Если требуется форк/фикс для системной громкости на macOS 15:
```bash
cd third_party/BackgroundMusic
xcodebuild -runFirstLaunch
./build_and_install.sh -n
```
Скрипт поставит драйвер, BGM.app и перезапустит coreaudiod.

### Релиз и структура
- Лицензия: MIT (этот репозиторий). Файлы в `third_party/BackgroundMusic` — GPLv2 (сохранена лицензия апстрима).
- Структура:
  - `su1-volume-bridge/` — CLI демон (SwiftPM)
  - `scripts/` — установщик и деинсталлятор
  - `launchagents/` — LaunchAgent plist
  - `third_party/BackgroundMusic/` — исходники BGM (опционально, для форка/фиксов)
  - `README.md`, `LICENSE`, `task.md`

### Release checklist
- Собрать `su1-volume-bridge` (Release) и проверить на macOS 14/15.
- Проверить автостарт агента и переключение SU-1 ↔ встроенные динамики.
- Провести тесты: Safari/YouTube/Spotify, Sleep/Wake, смена sample rate.
- Создать GitHub Release и приложить `.pkg` (опционально) или инструкции по установке.


