mkdir thirdparty && cd thirdparty

## making pjsip

curl -O -L https://github.com/pjsip/pjproject/archive/refs/tags/2.17.tar.gz
tar -xzf 2.17.tar.gz
cd pjproject-2.17

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

->

Makefile:1: build.mak: No such file or directory
Makefile:2: build/host-.mak: No such file or directory
make: *** No rule to make target `build/host-.mak'.  Stop.

--with-ssl=DIR          Specify alternate SSL library prefix. This option
                           will try to find OpenSSL first, then if not found,
                           GnuTLS. To skip OpenSSL finding, use --with-gnutls
                           option instead.
Откуда =internal?


brew install gnutls
Иначе на сможет сип инициализировать
--with-gnutls=DIR       Specify alternate GnuTLS prefix

  Reason: tried: '/opt/homebrew/opt/mbedtls/lib/libmbedtls.21.dylib' (no such file), '/System/Volumes/Preboot/Cryptexes/OS/opt/homebrew/opt/mbedtls/lib/libmbedtls.21.dylib' (no such file), '/opt/homebrew/opt/mbedtls/lib/libmbedtls.21.dylib' (no such file)

make distclean
./configure --enable-shared --disable-ffmpeg --disable-sdl --disable-openh264 --disable-libyuv
make dep && make

flutter build macos --release

Exception has occurred.
LateError (LateInitializationError: Field '_pjsipGlobal@146064482' has not been initialized.

otool -L pjsua2.dylib
/opt/homebrew/opt/gnutls/lib/libgnutls.30.dylib (compatibility version 71.0.0, current version 71.3.0)
/opt/homebrew/opt/mbedtls/lib/libmbedtls.21.dylib (compatibility version 21.0.0, current version 3.6.3)

brew install mbedtls не работает, он ставит 4 версию
ставить 3 версию тоже не работает

Забиваем на установку openssl, gnutls! Зашиваем mbedtls внутрь

## Собираем TLS

curl -O -L https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.7/mbedtls-3.6.7.tar.bz2

tar -xf mbedtls-3.6.7.tar.bz2
cd mbedtls-3.6.7
make no_test -j
make install DESTDIR=$HOME/opt/mbedtls

Когда собрали тлс в папку, указываем ее при сборки пжсип

--with-mbedtls=$HOME/opt/mbedtls


./configure --enable-shared --disable-ffmpeg --disable-sdl --disable-openh264 --disable-libyuv --with-mbedtls=$HOME/opt/mbedtls
make dep && make

## собираем все скомпилиные статичные библиотеки в одну жирную

libtool -static -o ./pjpkg.a pjsip/lib/libpjsua2-aarch64-apple-darwin24.5.0.a pjsip/lib/libpjsua-aarch64-apple-darwin24.5.0.a pjsip/lib/libpjsip-ua-aarch64-apple-darwin24.5.0.a pjsip/lib/libpjsip-simple-aarch64-apple-darwin24.5.0.a pjsip/lib/libpjsip-aarch64-apple-darwin24.5.0.a pjmedia/lib/libpjmedia-audiodev-aarch64-apple-darwin24.5.0.a pjmedia/lib/libpjmedia-videodev-aarch64-apple-darwin24.5.0.a pjmedia/lib/libpjmedia-codec-aarch64-apple-darwin24.5.0.a pjmedia/lib/libpjmedia-aarch64-apple-darwin24.5.0.a pjmedia/lib/libpjsdp-aarch64-apple-darwin24.5.0.a pjnath/lib/libpjnath-aarch64-apple-darwin24.5.0.a pjlib-util/lib/libpjlib-util-aarch64-apple-darwin24.5.0.a pjlib/lib/libpj-aarch64-apple-darwin24.5.0.a third_party/lib/libsrtp-aarch64-apple-darwin24.5.0.a third_party/lib/libresample-aarch64-apple-darwin24.5.0.a third_party/lib/libgsmcodec-aarch64-apple-darwin24.5.0.a third_party/lib/libspeex-aarch64-apple-darwin24.5.0.a third_party/lib/libilbccodec-aarch64-apple-darwin24.5.0.a third_party/lib/libg7221codec-aarch64-apple-darwin24.5.0.a third_party/lib/libwebrtc-aarch64-apple-darwin24.5.0.a

## Переводим жирную библиотеку в динамическую

libtool -arch_only arm64 -dynamic -o pj-all-arm64.dylib -install_name /usr/local/lib/pj-all.dylib -compatibility_version 1 -current_version 1 ./pjpkg.a -framework CoreAudio -framework AudioUnit -framework AudioToolbox -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework Metal -framework MetalKit -framework VideoToolbox -framework CoreGraphics -framework QuartzCore -framework Foundation -framework AppKit -framework CoreServices -lc++ -lobjc -lSystem

ld: unknown options: -force_cpusubtype_ALL 
fatal error: /Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/libtool: internal link edit command failed
Хз почему так не работает

Путь до библиотеки в приложений
@loader_path/../Framework/libpjsua2.dylib

clang -dynamiclib -o libpj-all.dylib -install_name @loader_path/../Framework/pj-all.dylib -compatibility_version 1 -current_version 1 ./pjpkg.a -framework CoreAudio -framework AudioUnit -framework AudioToolbox -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework Metal -framework MetalKit -framework VideoToolbox -framework CoreGraphics -framework QuartzCore -framework Foundation -framework AppKit -framework CoreServices -lc++ -lobjc -lSystem

## Все в одну команду

```bash
clang -dynamiclib \
  -o macos/libs/libpjsua2.dylib \
  -install_name @loader_path/../Framework/libpjsua2.dylib \
  -compatibility_version 1 -current_version 1 \
  -Wl,-force_load,thirdparty/pjproject-2.17/pjlib/lib/libpj-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/pjlib-util/lib/libpjlib-util-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/pjnath/lib/libpjnath-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/third_party/lib/libspeex-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/third_party/lib/libgsmcodec-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/third_party/lib/libilbccodec-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/third_party/lib/libg7221codec-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/third_party/lib/libresample-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/third_party/lib/libsrtp-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/third_party/lib/libwebrtc-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/pjmedia/lib/libpjmedia-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/pjmedia/lib/libpjmedia-audiodev-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/pjmedia/lib/libpjmedia-videodev-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/pjmedia/lib/libpjmedia-codec-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/pjsip/lib/libpjsip-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/pjsip/lib/libpjsip-ua-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/pjsip/lib/libpjsip-simple-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/pjsip/lib/libpjsua-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,thirdparty/pjproject-2.17/pjsip/lib/libpjsua2-aarch64-apple-darwin24.5.0.a \
  -Wl,-force_load,$HOME/opt/mbedtls/lib/libmbedtls.a \
  -Wl,-force_load,$HOME/opt/mbedtls/lib/libmbedx509.a \
  -Wl,-force_load,$HOME/opt/mbedtls/lib/libmbedcrypto.a \
  -framework CoreAudio \
  -framework AudioUnit \
  -framework AudioToolbox \
  -framework AVFoundation \
  -framework CoreMedia \
  -framework CoreVideo \
  -framework Metal \
  -framework MetalKit \
  -framework VideoToolbox \
  -framework CoreGraphics \
  -framework QuartzCore \
  -framework Foundation \
  -framework AppKit \
  -framework CoreServices \
  -lc++ \
  -lobjc
```

Проверяем 

```bash
python3 -c "
import ctypes
h = ctypes.CDLL('macos/libs/libpjsua2.dylib')
r = h.pjsua_create()
print(f'return={r}  (0 = success)')
"
```
flutter build macos --release

