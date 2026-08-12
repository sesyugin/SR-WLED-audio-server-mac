#!/usr/bin/env bash
# Собирает Auralis.app. Xcode не нужен — достаточно Command Line Tools.
#
# Бандл обязателен не для красоты: macOS показывает диалоги разрешений только
# приложению с Info.plist и подписью. Голый бинарник из swift build прав на
# запись системного звука не получит.
#
# Переменные окружения:
#   SRWLED_SIGN_IDENTITY  имя сертификата для подписи (иначе ad-hoc)
#   SRWLED_BUNDLE_ID      идентификатор бандла
#   SRWLED_ARCHIVE=1      собрать ещё и архив для страницы релизов
set -euo pipefail
cd "$(dirname "$0")/.."

# Имя приложения — одно слово: его видно в Dock, в Finder и в /Applications.
APP_NAME="Auralis"
# Имя файла на странице релизов — длинное и с платформой: по нему архив
# находят поиском рядом с оригинальной Windows-версией.
ARCHIVE_NAME="SR-WLED-Server-Auralis-macos"
BUNDLE_ID="${SRWLED_BUNDLE_ID:-io.github.srwled.auralis.mac}"
DEST="dist/${APP_NAME}.app"

# Версия живёт в Sources/SRWLEDCore/Version.swift — одно место на весь проект,
# откуда её берёт и консольная версия по --version. Пустое значение здесь
# означало бы бандл с версией «» в списке программ, поэтому падаем сразу.
VERSION_FILE="Sources/SRWLEDCore/Version.swift"
VERSION="$(sed -n 's/.*static let current = "\([^"]*\)".*/\1/p' "$VERSION_FILE")"
BUILD="$(sed -n 's/.*static let build = "\([^"]*\)".*/\1/p' "$VERSION_FILE")"
if [ -z "$VERSION" ] || [ -z "$BUILD" ]; then
    echo "не удалось прочитать версию из $VERSION_FILE" >&2
    exit 1
fi
echo "==> Версия ${VERSION} (${BUILD})"

echo "==> Сборка релизной версии"
swift build -c release --product SRWLEDMenuBar

echo "==> Сборка бандла ${DEST}"
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"

cp .build/release/SRWLEDMenuBar "$DEST/Contents/MacOS/${APP_NAME}"

echo "==> Иконка"
# Знак рисуется кодом: SRWLEDPreview раскладывает его по размерам, iconutil
# собирает .icns. Каталог свой на каждую сборку — из общего /tmp прежде
# подбиралась иконка от прошлого прогона, даже если рендер только что упал.
ICONSET="$(mktemp -d)/Auralis.iconset"
mkdir -p "$ICONSET"
swift build -c release --product SRWLEDPreview
SRWLED_ICONSET="$ICONSET" swift run -c release --quiet SRWLEDPreview --icon-only
iconutil -c icns "$ICONSET" -o "$DEST/Contents/Resources/${APP_NAME}.icns"
rm -rf "$(dirname "$ICONSET")"
echo "    иконка собрана"

cat > "$DEST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
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

    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Zakhar Sesyugin. GPL-3.0</string>

    <!-- Языки, на которых приложение умеет говорить. Без этого списка macOS
         считает бандл одноязычным и берёт строки разрешений из корневого
         Info.plist, игнорируя .lproj. -->
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string><string>zh</string><string>hi</string><string>es</string>
        <string>fr</string><string>ar</string><string>bn</string><string>ru</string>
        <string>pt</string><string>ur</string><string>id</string><string>de</string>
        <string>uk</string><string>it</string><string>sv</string><string>be</string>
    </array>

    <!-- Без этой строки macOS не покажет запрос и захват вернёт одни нули.
         Перевод на каждый язык лежит в Resources/<код>.lproj/InfoPlist.strings;
         здесь — английский запасной вариант. -->
    <key>NSAudioCaptureUsageDescription</key>
    <string>Reads what is playing on this Mac to turn the sound into a spectrum for LED strips. The audio itself is never transmitted or stored.</string>

    <!-- macOS 15 и новее спрашивает отдельное разрешение на локальную сеть. -->
    <key>NSLocalNetworkUsageDescription</key>
    <string>Sends the audio spectrum to LED strips running WLED on your home network.</string>

    <key>CFBundleIconFile</key>
    <string>${APP_NAME}</string>

    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Переводы строк разрешений"
# Системный диалог разрешений читает InfoPlist.strings того языка, на котором
# работает система, а не язык, выбранный внутри программы. Диалог показывается
# до первого запуска интерфейса — выбрать там ещё нечего.
scripts/make-infoplist-strings.sh "$DEST/Contents/Resources"

echo "==> Проверка Info.plist"
plutil -lint "$DEST/Contents/Info.plist"

echo "==> Подпись"
# Самоподписанный сертификат из связки ключей даёт стабильную подпись, и разрешение
# на запись звука не слетает при каждой пересборке. Если его нет — подписываем ad-hoc,
# но тогда macOS будет спрашивать разрешение заново после каждой сборки.
if [ -n "${SRWLED_SIGN_IDENTITY:-}" ]; then
    # Права обязательны вместе с --options runtime: hardened runtime без них
    # отбирает доступ к звуку молча — разрешение выдано, а в буфере одни нули.
    codesign --force --options runtime \
             --entitlements scripts/Auralis.entitlements \
             --sign "$SRWLED_SIGN_IDENTITY" "$DEST"
    echo "    подписано сертификатом: $SRWLED_SIGN_IDENTITY"
else
    codesign --force --sign - "$DEST"
    echo "    подписано ad-hoc (задай SRWLED_SIGN_IDENTITY для стабильной подписи)"
fi

codesign --verify --verbose=1 "$DEST" 2>&1 | sed 's/^/    /'

if [ -n "${SRWLED_ARCHIVE:-}" ]; then
    ARCHIVE="dist/${ARCHIVE_NAME}-${VERSION}.zip"
    echo "==> Архив для страницы релизов"
    rm -f "$ARCHIVE"
    # ditto, а не zip: только он сохраняет подпись и расширенные атрибуты бандла.
    ditto -c -k --sequesterRsrc --keepParent "$DEST" "$ARCHIVE"
    echo "    $ARCHIVE"
fi

echo
echo "Готово: $DEST"
echo "Запуск:   open \"$DEST\""
echo "Установка: cp -R \"$DEST\" /Applications/"
