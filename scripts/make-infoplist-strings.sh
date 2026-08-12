#!/usr/bin/env bash
# Раскладывает переводы строк разрешений по <код>.lproj/InfoPlist.strings.
#
# Почему отдельно от таблицы переводов в Swift: этот текст читает не программа,
# а сама macOS — в диалоге, который показывается до первого запуска интерфейса.
# Язык там системный, и выбрать его внутри программы человек ещё не мог.
# Достать строки из скомпилированной таблицы в момент сборки бандла нечем,
# поэтому они живут здесь, рядом со скриптом, который их и раскладывает.
#
# Bash на маке до сих пор 3.2 — ассоциативных массивов нет, отсюда case.
set -euo pipefail

RESOURCES="${1:?укажи каталог Contents/Resources}"

LANGUAGES="en ru zh hi es fr ar bn pt ur id de uk it sv be"

audio_text() {
    case "$1" in
    en) echo "Reads what is playing on this Mac to turn the sound into a spectrum for LED strips. The audio itself is never transmitted or stored." ;;
    ru) echo "Читает то, что играет на компьютере, чтобы превратить звук в спектр для светодиодных лент. Сам звук никуда не передаётся и нигде не сохраняется." ;;
    zh) echo "读取这台 Mac 正在播放的声音，将其转换为频谱发送给灯带。声音本身不会被传输，也不会被保存。" ;;
    hi) echo "इस Mac पर बज रही ध्वनि को पढ़कर उसे एलईडी स्ट्रिप्स के लिए स्पेक्ट्रम में बदलता है। ध्वनि स्वयं न कहीं भेजी जाती है, न सहेजी जाती है।" ;;
    es) echo "Lee lo que suena en este Mac para convertir el sonido en un espectro para tiras LED. El sonido en sí no se transmite ni se guarda." ;;
    fr) echo "Lit ce qui joue sur ce Mac pour transformer le son en spectre destiné aux rubans LED. Le son lui-même n'est ni transmis ni conservé." ;;
    ar) echo "يقرأ ما يُشغَّل على هذا الـMac لتحويل الصوت إلى طيف لشرائط LED. الصوت نفسه لا يُنقل ولا يُحفظ." ;;
    bn) echo "এই Mac-এ যা বাজছে তা পড়ে শব্দকে এলইডি স্ট্রিপের জন্য স্পেকট্রামে পরিণত করে। শব্দ নিজে কোথাও পাঠানো বা সংরক্ষণ করা হয় না।" ;;
    pt) echo "Lê o que está tocando neste Mac para transformar o som em espectro para fitas de LED. O som em si não é transmitido nem guardado." ;;
    ur) echo "اس Mac پر چلنے والی آواز پڑھ کر اسے ایل ای ڈی سٹرپس کے لیے سپیکٹرم میں بدلتی ہے۔ آواز خود نہ بھیجی جاتی ہے نہ محفوظ ہوتی ہے۔" ;;
    id) echo "Membaca apa yang diputar di Mac ini untuk mengubah suara menjadi spektrum bagi strip LED. Suaranya sendiri tidak dikirim ke mana pun dan tidak disimpan." ;;
    de) echo "Liest, was auf diesem Mac läuft, um den Ton in ein Spektrum für LED-Streifen zu verwandeln. Der Ton selbst wird weder übertragen noch gespeichert." ;;
    uk) echo "Читає те, що грає на цьому Mac, щоб перетворити звук на спектр для світлодіодних стрічок. Сам звук нікуди не передається і ніде не зберігається." ;;
    it) echo "Legge ciò che suona su questo Mac per trasformare il suono in uno spettro per le strisce LED. L'audio stesso non viene trasmesso né conservato." ;;
    sv) echo "Läser det som spelas på den här Macen för att göra ljudet till ett spektrum för LED-slingor. Ljudet självt varken skickas vidare eller sparas." ;;
    be) echo "Чытае тое, што грае на гэтым Mac, каб ператварыць гук у спектр для святлодыёдных стужак. Сам гук нікуды не перадаецца і нідзе не захоўваецца." ;;
    *)  return 1 ;;
    esac
}

network_text() {
    case "$1" in
    en) echo "Sends the audio spectrum to LED strips running WLED on your home network." ;;
    ru) echo "Отправляет спектр звука на светодиодные ленты с прошивкой WLED в домашней сети." ;;
    zh) echo "将音频频谱发送到家庭网络中运行 WLED 的灯带。" ;;
    hi) echo "आपके घरेलू नेटवर्क पर WLED चला रही एलईडी स्ट्रिप्स को ऑडियो स्पेक्ट्रम भेजता है।" ;;
    es) echo "Envía el espectro de audio a tiras LED con WLED en tu red doméstica." ;;
    fr) echo "Envoie le spectre audio aux rubans LED sous WLED de votre réseau domestique." ;;
    ar) echo "يرسل طيف الصوت إلى شرائط LED التي تعمل ببرنامج WLED في شبكتك المنزلية." ;;
    bn) echo "আপনার বাড়ির নেটওয়ার্কে WLED চালানো এলইডি স্ট্রিপে অডিও স্পেকট্রাম পাঠায়।" ;;
    pt) echo "Envia o espectro de áudio para fitas de LED com WLED na sua rede doméstica." ;;
    ur) echo "آپ کے گھریلو نیٹ ورک پر WLED چلانے والی ایل ای ڈی سٹرپس کو آڈیو سپیکٹرم بھیجتی ہے۔" ;;
    id) echo "Mengirim spektrum audio ke strip LED dengan WLED di jaringan rumah Anda." ;;
    de) echo "Sendet das Audiospektrum an LED-Streifen mit WLED in Ihrem Heimnetzwerk." ;;
    uk) echo "Надсилає спектр звуку на світлодіодні стрічки з прошивкою WLED у домашній мережі." ;;
    it) echo "Invia lo spettro audio alle strisce LED con WLED nella tua rete domestica." ;;
    sv) echo "Skickar ljudspektrumet till LED-slingor med WLED i ditt hemnätverk." ;;
    be) echo "Адпраўляе спектр гуку на святлодыёдныя стужкі з прашыўкай WLED у хатняй сетцы." ;;
    *)  return 1 ;;
    esac
}

count=0
for language in $LANGUAGES; do
    audio="$(audio_text "$language")"
    network="$(network_text "$language")"

    # Пустой перевод хуже отсутствующего: система показала бы диалог без объяснения.
    if [ -z "$audio" ] || [ -z "$network" ]; then
        echo "нет перевода для языка $language" >&2
        exit 1
    fi

    directory="${RESOURCES}/${language}.lproj"
    mkdir -p "$directory"
    cat > "${directory}/InfoPlist.strings" <<STRINGS
/* Диалог разрешения на запись системного звука */
"NSAudioCaptureUsageDescription" = "${audio}";

/* Диалог разрешения на доступ в локальную сеть */
"NSLocalNetworkUsageDescription" = "${network}";
STRINGS
    count=$((count + 1))
done

echo "    переводы разрешений разложены: $count языков"
