mkdir thirdparty && cd thirdparty

## Собираем TLS

curl -O -L https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.7/mbedtls-3.6.7.tar.bz2

tar -xf mbedtls-3.6.7.tar.bz2
cd mbedtls-3.6.7
make no_test -j
make install DESTDIR=$HOME/opt/mbedtls

Когда собрали тлс в папку, указываем ее при сборки пжсип

--with-mbedtls=$HOME/opt/mbedtls

## making pjsip

curl -O -L https://github.com/pjsip/pjproject/archive/refs/tags/2.17.tar.gz
tar -xzf 2.17.tar.gz
cd pjproject-2.17

Забиваем на установку openssl, gnutls! Зашиваем mbedtls внутрь
Ставим библиотеки для видео
`brew install openh264 ffmpeg libvpx sdl2 pkg-config`

```bash
make distclean

./configure --enable-shared \
--disable-libyuv \
--disable-ffmpeg \
--enable-video \
--with-openh264=/opt/homebrew/opt/openh264 \
--with-vpx=/opt/homebrew/opt/libvpx \
--with-mbedtls=$HOME/opt/mbedtls

make dep && make
```

## собираем все скомпилиные статичные библиотеки в одну жирную

Путь до библиотеки в приложений
@loader_path/../Framework/libpjsua2.dylib

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
-L/opt/homebrew/lib -lSDL2 -lSDL2main \
-L/opt/homebrew/opt/openh264/lib -lopenh264 \
-L/opt/homebrew/opt/libvpx/lib -lvpx \
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

