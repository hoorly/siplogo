import 'dart:ffi' as ffi;
import 'dart:io';


// Описываем сигнатуру базовой функции инициализации PJSIP для проверки
typedef PjsuaCreateC = ffi.Int32 Function();
typedef PjsuaCreateDart = int Function();

class PjsipMacBinder {
  late ffi.DynamicLibrary _pjsipLib;
  late PjsuaCreateDart pjsuaCreate;

  void loadLibrary() {
    String libPath;
    if (Platform.isMacOS) {
      // Когда приложение запущено, все dylib лежат в папке Frameworks
      // которая находится на одном уровне с папкой MacOS (где лежит бинарник)
      // Путь к исполняемому файлу приложения: .../Runner.app/Contents/MacOS/Runner
      final exePath = Platform.resolvedExecutable;
      final contentsDir = File(exePath)
          .parent
          .parent
          .path; // .../Runner.app/Contents

      // Итоговый путь к встроенной библиотеке
      libPath = '$contentsDir/Frameworks/libpjsua2.dylib';
    } else {
      throw UnsupportedError("Не поддерживаемая платформа");
    }

    if (!File(libPath).existsSync()) {
      throw Exception("Библиотека PJSIP не найдена по пути $libPath");
    }

    // 2. Загружаем динамическую библиотеку в память процесса
    _pjsipLib = ffi.DynamicLibrary.open(libPath);
    print("[🍏] PJSIP библиотека успешно загружена в память macOS!");

    // 3. Биндим простейшую сишную функцию pjsua_create для проверки
    // В PJSIP pjsua_create() возвращает статус (0 = PJ_SUCCESS)
    pjsuaCreate = _pjsipLib
        .lookup<ffi.NativeFunction<PjsuaCreateC>>('pjsua_create')
        .asFunction<PjsuaCreateDart>();
  }

  void initCore() {
    final status = pjsuaCreate();
    if (status == 0) {
      print("[✅] Ядро PJSIP успешно проинициализировано внутри Flutter!");
    } else {
      print("[❌] Ошибка инициализации PJSIP. Код статуса: $status");
    }
  }
}
