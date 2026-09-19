# siplogo

Voip softphone

# pjsip
- Установите консольные инструменты Xcode
  xcode-select --install
  brew install swig

- Скачайте pjsip
  wget https://github.com/pjsip/pjproject/archive/refs/tags/2.17.tar.gz
  tar -xzf 2.17.tar.gz

# Сборка libpjsua2.dylib на macOs в один файл (нов)
cd /Users/jocker/Downloads/pjproject-2.17 && \
make distclean && \
export CFLAGS="-I/usr/include -fPIC" && \
export LDFLAGS="" && \
./configure --enable-shared \
--disable-ffmpeg \
--disable-sdl \
--disable-openh264 \
--disable-libyuv \
--with-ssl=internal && \
make dep && make

# Перенос в проект
После успешного завершения команды make
скомпилированная библиотека будет находиться в папке:
./pjsip/lib/libpjsua2.dylib

При попытке загрузить в приложении собранную библиотеку
будет ошибка
flutter: Invalid argument(s): Failed to load dynamic library '/Users/jocker/Downloads/pjproject-2.17/pjsip/lib/libpjsua2.dylib': dlopen(/Users/jocker/Downloads/pjproject-2.17/pjsip/lib/libpjsua2.dylib, 0x0001): Library not loaded: ../lib/libpjsua.dylib.2
Reason: tried: '../lib/libpjsua.dylib.2' (no such file), '/System/Volumes/Preboot/Cryptexes/OS../lib/libpjsua.dylib.2' (no such file), '../lib/libpjsua.dylib.2' (no such file)

- Для исправления относительных путей на абсолютные,
необходимо указать их, чтобы можно было загрузить dylib в приложение
install_name_tool -change "../lib/libpjsua.dylib.2" "/Users/jocker/Downloads/pjproject-2.17/pjsip/lib/libpjsua.dylib.2" /Users/jocker/Downloads/pjproject-2.17/pjsip/lib/libpjsua2.dylib
- Для проверки изменений:
```
otool -L /Users/jocker/Downloads/pjproject-2.17/pjsip/lib/libpjsua2.dylib
```
который покажет, что там дохуа зависимостей по размным путям,
поэтому болт на install_name_tool и надо собрать всех вместе в одной папке
```
# Из flutter папки проекта
mkdir -p macos/libs && \
find /Users/jocker/Downloads/pjproject-2.17 -type f \( -name "*.dylib" -o -name "*.dylib.*" \) -exec cp -v {} macos/libs/ \;
```
и поправить их
```
cd macos/libs/
for file in *.dylib*; do
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    echo "Processing $file..."
    # Находим все относительные зависимости внутри файла и меняем их на @loader_path
    otool -L "$file" | grep -E '(\.\./\.\./lib/|\.\./lib/)' | awk '{print $1}' | while read -r dep; do
      base_dep=$(basename "$dep")
      install_name_tool -change "$dep" "@loader_path/$base_dep" "$file"
    done
  fi
done
```
- Создание символических ссылок .dylib
```
for file in *.dylib.2; do
  # Проверяем, что файл существует
  if [ -f "$file" ]; then
    # Получаем имя без ".2" (например, libpjsua2.dylib)
    link_name="${file%.2}"
    # Создаем символическую ссылку
    ln -sf "$file" "$link_name"
    echo "Создана ссылка: $link_name -> $file"
  fi
done
```

Откройте нативную часть проекта в Xcode.
Для этого в терминале (в корне проекта) выполните:
open macos/Runner.xcworkspace
В левой панели Xcode нажмите на корневой проект Runner.
Выберите таргет Runner в списке (в разделе Targets).
Перейдите на вкладку Build Phases (вверху).
Разверните пункт Embed Frameworks
(если его нет, нажмите сверху + -> New Copy Files Phase,
переименуйте в Embed Frameworks и выберите Destination: Frameworks).
Нажмите на иконку + внизу этого раздела.
В появившемся окне нажмите Add Other... -> Add Files...
и выберите все .dylib* файлы
Важно: Убедитесь, что в столбце Code Sign On Copy
(рядом с добавленным файлом) стоит галочка.
macOS заблокирует запуск приложения на другом компьютере,
если встроенная библиотека не будет подписана тем же сертификатом,
что и само приложение.
Указание путей поиска:
Чтобы Flutter-приложение знало,
где искать библиотеку во время написания кода (Dart кода через DynamicLibrary.open),
и где искать её во время работы программы:
В том же окне Xcode перейдите на соседнюю вкладку Build Settings.
Убедитесь, что выбраны режимы All и Combined (под вкладками).
В строке поиска справа введите: 
Runpath Search Paths.
Дважды кликните на значение этого параметра и проверьте,
чтобы там была строка: @executable_path/../Frameworks
Если её нет, нажмите «+» и добавьте

- Для генерации биндингов
dart run ffigen --config ffigen.yaml

# Сборка dmg
brew install create-dmg

flutter build macos --release
Building macOS application...                                           
✓ Built build/macos/Build/Products/Release/siplogo.app (53.4MB)

Смотрим, что во фреймворках
ls -l build/macos/Build/Products/Release/siplogo.app/Contents/Frameworks/

Проверяем, что не осталось зависимостей на /opt/homebrew... если есть, тогда на другом компе
будут ошибки (елси что-то не будет установлено из этих зависимостей)
otool -L /Users/jocker/StudioProjects/siplogo/siplogo/build/macos/Build/Products/Release/siplogo.app/Contents/Frameworks/libpjsua2.dylib

rm -f build/macos/Build/Products/Release/siplogo.dmg && \
create-dmg \
--volname "Установка SIPLOGO" \
--volicon "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png" \
--window-pos 200 120 \
--window-size 600 400 \
--icon-size 100 \
--icon "siplogo.app" 175 190 \
--app-drop-link 425 190 \
"build/macos/Build/Products/Release/siplogo.dmg" \
"build/macos/Build/Products/Release/siplogo.app"

cp \
  /Users/jocker/StudioProjects/siplogo/siplogo/build/macos/Build/Products/Release/siplogo.dmg \
  /Users/jocker/Downloads/

Кидаем на другой комп
rsync -a /Users/jocker/Downloads/siplogo.dmg jocker@192.168.0.100:/Users/jocker/Downloads/

После установки на другом компьютере нужно при возникновении проблем
запускать через терминал
/Applications/siplogo.app/Contents/MacOS/siplogo
чтобы посмотреть ошибки