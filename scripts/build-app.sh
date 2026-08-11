#!/usr/bin/env bash
# Собирает SR-WLED.app. Xcode не нужен — достаточно Command Line Tools.
#
# Бандл обязателен не для красоты: macOS показывает диалоги разрешений только
# приложению с Info.plist и подписью. Голый бинарник из swift build прав на
# запись системного звука не получит.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Auralis"
BUNDLE_ID="${SRWLED_BUNDLE_ID:-io.github.auralis.mac}"
VERSION="0.3.0"
BUILD="3"
DEST="dist/${APP_NAME}.app"

echo "==> Сборка релизной версии"
swift build -c release --product SRWLEDMenuBar

echo "==> Сборка бандла ${DEST}"
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"

cp .build/release/SRWLEDMenuBar "$DEST/Contents/MacOS/${APP_NAME}"

echo "==> Иконка"
# Знак рисуется кодом: SRWLEDPreview раскладывает его по размерам, iconutil собирает .icns.
swift build -c release --product SRWLEDPreview >/dev/null 2>&1
swift run -c release --quiet SRWLEDPreview >/dev/null 2>&1 || true
if [ -d /tmp/Auralis.iconset ]; then
    iconutil -c icns /tmp/Auralis.iconset -o "$DEST/Contents/Resources/${APP_NAME}.icns" 2>/dev/null \
        && echo "    иконка собрана" || echo "    иконку собрать не удалось"
fi

cat > "$DEST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Auralis</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.2</string>


    <!-- Без этой строки macOS не покажет запрос и захват вернёт одни нули. -->
    <key>NSAudioCaptureUsageDescription</key>
    <string>Читает то, что играет на компьютере, чтобы превратить звук в спектр для светодиодных лент. Сам звук никуда не передаётся и нигде не сохраняется.</string>

    <!-- macOS 15 и новее спрашивает отдельное разрешение на локальную сеть. -->
    <key>NSLocalNetworkUsageDescription</key>
    <string>Отправляет спектр звука на светодиодные ленты с прошивкой WLED в домашней сети.</string>

    <key>CFBundleIconFile</key>
    <string>${APP_NAME}</string>

    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Проверка Info.plist"
plutil -lint "$DEST/Contents/Info.plist"

echo "==> Подпись"
# Самоподписанный сертификат из связки ключей даёт стабильную подпись, и разрешение
# на запись звука не слетает при каждой пересборке. Если его нет — подписываем ad-hoc,
# но тогда macOS будет спрашивать разрешение заново после каждой сборки.
if [ -n "${SRWLED_SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --sign "$SRWLED_SIGN_IDENTITY" "$DEST"
    echo "    подписано сертификатом: $SRWLED_SIGN_IDENTITY"
else
    codesign --force --sign - "$DEST"
    echo "    подписано ad-hoc (задай SRWLED_SIGN_IDENTITY для стабильной подписи)"
fi

codesign --verify --verbose=1 "$DEST" 2>&1 | sed 's/^/    /'

echo
echo "Готово: $DEST"
echo "Запуск:   open \"$DEST\""
echo "Установка: cp -R \"$DEST\" /Applications/"
