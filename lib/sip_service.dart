import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'pjsip_bindings.dart'; // сгенерированный файл биндингов

// Глобальная ссылка на биндинги, чтобы колбэки имели к ней доступ
late PjsipBindings _pjsipGlobal;

// Глобальный ID активного звонка (-1 означает, что звонков нет)
int _activeCallId = -1;

// Поток для отправки статуса регистрации в графический интерфейс
final StreamController<int> _regStatusStream = StreamController<int>.broadcast();
Stream<int> get sipRegistrationStatus => _regStatusStream.stream;

// ПОТОК ДЛЯ СТАТУСА ТЕКУЩЕГО ЗВОНКА
final StreamController<SipCallState> _callStateStream = StreamController<SipCallState>.broadcast();
Stream<SipCallState> get sipCallStateStream => _callStateStream.stream;

// ГЛОБАЛЬНЫЙ КОЛБЭК ДЛЯ КОММУТАЦИИ ЗВУКА В РАЗГОВОРЕ
void dartOnCallMediaState(int callId) {
  print("[🎧 PJSIP Media] Медиа-поток звонка изменился! Проверяем порты...");
  // 1. Выделяем память под структуру информации о звонке
  final callInfo = calloc<pjsua_call_info>();
  // 2. Наполняем структуру актуальными данными из ядра PJSIP
  final status = _pjsipGlobal.pjsua_call_get_info(callId, callInfo);
  if (status == 0) {
    // 3.Забираем ID аудио-слота прямо из структуры callInfo
    // ffigen маппит его как conf_slot (проверьте в биндингах, если будет ругаться, возможно conf_slot$1)
    final int callConfSlot = callInfo.ref.conf_slot;
    // В PJSIP pjsua_call_get_info может вернуть слот -1, если медиа еще не готово
    if (callConfSlot != -1) {
      print("[🎧 PJSIP Media] Звонок занял аудио-слот ID: $callConfSlot. Коммутируем звук...");
      // Слот под номером 0 — это системный микрофон и динамик Mac по умолчанию.
      // Соединяем: звук из АТС (звонка) -> направляем в динамики Mac
      _pjsipGlobal.pjsua_conf_connect(callConfSlot, 0);
      // Соединяем: звук с микрофона Mac -> направляем обратно в АТС (собеседнику)
      _pjsipGlobal.pjsua_conf_connect(0, callConfSlot);
      print("[✅ PJSIP Media] Звуковой мост успешно построен в обе стороны!");
    } else {
      print("[⚠️ PJSIP Media] Звонок активен, но аудио-слот еще не выделен.");
    }
  } else {
    print("[❌ PJSIP Media] Не удалось получить информацию о звонке ID: $callId, код ошибки: $status");
  }
  // Освобождаем выделенную память, чтобы избежать утечек
  calloc.free(callInfo);
}

// ГЛОБАЛЬНЫЙ КОЛБЭК ДЛЯ ОТСЛЕЖИВАНИЯ СТАТУСА ЗВОНКА
void dartOnCallState(int callId, ffi.Pointer<pjsip_rx_data> rdata) {
  final callInfo = calloc<pjsua_call_info>();
  final status = _pjsipGlobal.pjsua_call_get_info(callId, callInfo);
  if (status == 0) {
    // Получаем текущее состояние звонка (enum pjsip_inv_state)
    final state = callInfo.ref.state;
    print("[📞 PJSIP Call] Изменение статуса звонка. Состояние: ${state.value}");
    // pjsip_inv_state: 0 = NULL, 1 = INCOMING, 2 = EARLY, 3 = CALLING (идёт гудок), 4 = CONNECTING, 5 = CONFIRMED (разговор), 6 = DISCONNECTED (сброс)
    if (state.value == 1) {
      _callStateStream.add(SipCallState(state: "Входящий вызов...", statusCode: state.value));
      _activeCallId = callId;
    } else if (state.value == 3 || state.value == 4) {
      _callStateStream.add(SipCallState(state: "Вызываю...", statusCode: state.value));
      _activeCallId = callId;
    } else if (state.value == 5) {
      _callStateStream.add(SipCallState(state: "Разговор", statusCode: state.value));
      _activeCallId = callId;
    } else if (state.value == 6) {
      _callStateStream.add(SipCallState(state: "Завершен", statusCode: state.value));
      _activeCallId = -1; // Сбрасываем ID
    }
  } else {
    // Если PJSIP не смог прочитать инфо о звонке, значит ID уже невалиден (звонок уничтожен)
    print("[⚠️ PJSIP Call] Не удалось получить инфо для ID: $callId. Вероятно, вызов завершен АТС.");
    _callStateStream.add(SipCallState(state: "Завершен"));
    _activeCallId = -1;
  }
  calloc.free(callInfo);
}

// Тип второго аргумента вместо ffi.Pointer<pjsip_reg_info> info
// делаем ffi.Pointer<ffi.Void>
void dartOnRegState(int accId, ffi.Pointer<ffi.Void> info) {
  // Проверяем аккаунт
  final accIsValid = _pjsipGlobal.pjsua_acc_is_valid(accId);
  if (accIsValid == 1) {
    print("[🌐 PJSIP] Аккаунт корректный!");
    _regStatusStream.add(0);
  } else {
    print("[❌ PJSIP] Ошибка авторизации или потеря сети.");
    _regStatusStream.add(-1);
    return;
  }
  // Выделяем память под структуру информации об аккаунте
  final accInfo = calloc<pjsua_acc_info>();
  // Если не вызывать _pjsipGlobal.pjsua_acc_get_info, то accInfo.ref.statusAsInt будет 0
  // вызов pjsua_acc_get_info перед чтением полей обязателен — именно он наполняет Dart-структуру
  final status = _pjsipGlobal.pjsua_acc_get_info(accId, accInfo);
  final statusCode = accInfo.ref.statusAsInt;
  final statusCodeStr = accInfo.ref.status_text.ptr$1.cast<Utf8>().toDartString();
  print("[🌐 PJSIP Status] Сервер вернул код: status=$status, statusCode=$statusCode, statusCodeStr=$statusCodeStr");
  _regStatusStream.add(statusCode);
  if (statusCode == 200) {
    print("[✅ PJSIP] Успешно зарегистрирован на АТС ($statusCode=$statusCodeStr)!");
  } else if (statusCode >= 400 && statusCode < 500) {
  } else if (statusCode >= 500 && statusCode < 600) {
  } else if (statusCode >= 600) {
  } else {
  }
}

// ДЛЯ ОБРАБОТКИ ВХОДЯЩЕГО ЗВОНКА
// Она должна быть статической или глобальной, чтобы C-код мог её вызвать
void dartOnIncomingCall(int accId, int callId, ffi.Pointer<pjsip_rx_data> rdata) {
  // 1. Сохраняем ID прилетевшего звонка в глобальную переменную
  _activeCallId = callId;
  print("[🔔 PJSIP Callback] Обнаружен входящий вызов! ID звонка: $_activeCallId");
  // 2. Отправляем статус "180 Ringing" на АТС, чтобы у звонящего в трубке пошли правильные гудки
  final status = _pjsipGlobal.pjsua_call_answer(_activeCallId, 180, ffi.nullptr, ffi.nullptr);
  if (status == 0) {
    print("[📢] Отправлен статус 180 Ringing.");
  } else {
    print("[❌] Ошибка отправки 180 Ringing: $status");
  }
  // 3. Отправляем событие во Flutter UI, чтобы вывелась карточка вызова
  _callStateStream.add(SipCallState(state: "Входящий вызов...", statusCode: 180));
}

class SipCallState {
  final String state;       // "Вызываю...", "Разговор", "Завершен" и т.д.
  final int statusCode;     // SIP-код (например: 200, 486, 404, 603)

  SipCallState({
    required this.state,
    this.statusCode = 0,
  });

  String getReason() {
    switch (statusCode) {
      case 401: case 403: return "Ошибка авторизации (Запрещено АТС)";
      case 404: return "Неверный номер (Не существует)";
      case 408: return "Тайм-аут (Абонент не ответил)";
      case 480: return "Абонент временно недоступен";
      case 486: case 600: return "Линия занята";
      case 487: return "Вызов отменен";
      case 603: return "Звонок отклонен абонентом";
      default:
        if (statusCode >= 400 && statusCode < 500) return "Ошибка вызова ($statusCode)";
        if (statusCode >= 500) return "Ошибка сервера АТС ($statusCode)";
        return "Завершен";
    }
  }
}

class SipService {
  int _accId = -1;
  // ФЛАГ ИНИЦИАЛИЗАЦИИ
  static bool _isInitialized = false;
  // Метод для чистого закрытия PJSIP при выходе из приложения
  void terminate() {
    if (_accId != -1) {
      print("[🔄 PJSIP] Удаляем аккаунт перед выходом...");
      _pjsipGlobal.pjsua_acc_del(_accId);
      _accId = -1;
    }
    print("[🛑 PJSIP] Завершаем работу ядра и освобождаем память...");
    // pjsua_destroy() корректно выгрузит все модули и закроет UDP сокеты
    _pjsipGlobal.pjsua_destroy();
    _isInitialized = false;
    print("[👋 PJSIP] Библиотека успешно остановлена.");
  }
  // МЕТОД ДЛЯ АКТИВНОГО РАЗРЕГИСТРИРОВАНИЯ ПРИ НАЖАТИИ LOGOUT
  void logout() {
    if (_accId != -1) {
      print("[🔄 PJSIP] Удаляем аккаунт из АТС (Логаут)...");
      _pjsipGlobal.pjsua_acc_del(_accId);
      _accId = -1;
    }
  }

  void initAndStart() {
    // ЕСЛИ ЯДРО УЖЕ ЗАПУЩЕНО — НИЧЕГО НЕ ДЕЛАЕМ И ВЫХОДИМ
    if (_isInitialized) {
      print("[ℹ️ PJSIP] Ядро уже работает. Повторная инициализация пропущена.");
      // Сразу шлем статус готовности для нового экрана
      _regStatusStream.add(0);
      return;
    }
    // 1. Загружаем dylib
    final exePath = Platform.resolvedExecutable;
    final contentsDir = File(exePath).parent.parent.path;
    final libPath = '$contentsDir/Frameworks/libpjsua2.dylib';
    final dylib = ffi.DynamicLibrary.open(libPath);
    // 2. Инициализируем наш сгенерированный класс
    _pjsipGlobal = PjsipBindings(dylib);
    // 3. Создаем ядро PJSIP через нативную функцию
    final status = _pjsipGlobal.pjsua_create();
    if (status == 0) { // 0 = PJ_SUCCESS
      print("[✅] Ядро PJSIP успешно создано через Dart биндинги!");
    } else {
      print("[❌] Ошибка создания PJSIP: $status");
      return;
    }
    // Выделяем память под конфиги
    final uaCfg = calloc<pjsua_config>();
    final logCfg = calloc<pjsua_logging_config>();
    final mediaCfg = calloc<pjsua_media_config>();
    _pjsipGlobal.pjsua_config_default(uaCfg);
    _pjsipGlobal.pjsua_logging_config_default(logCfg);
    _pjsipGlobal.pjsua_media_config_default(mediaCfg);
    logCfg.ref.level = 2; // Умеренный уровень логов

    // =========================================================================
    // 2. ВСТРАИВАЕМ НАШ КОЛБЭК В КОНФИГУРАЦИЮ PJSIP
    // =========================================================================
    // NativeCallable.listener создает сишный указатель, безопасный для вызова из фоновых потоков
    final incomingCallCallable = ffi.NativeCallable<
        ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Pointer<pjsip_rx_data>)
    >.listener(dartOnIncomingCall);
    uaCfg.ref.cb.on_incoming_call = incomingCallCallable.nativeFunction.cast();

    // ПОДКЛЮЧАЕМ КОЛБЭК СТАТУСА РЕГИСТРАЦИИ ---
    final regStateCallable = ffi.NativeCallable<
        ffi.Void Function(ffi.Int32, ffi.Pointer<ffi.Void>)
    >.listener(dartOnRegState);
    uaCfg.ref.cb.on_reg_state2 = regStateCallable.nativeFunction.cast();

    // Записываем адрес нашей Dart-функции в структуру конфига PJSIP
    // ДОБАВЛЯЕМ .cast() при присвоении, чтобы Dart не ругался на типы pjsua_acc_id и pjsua_call_id
    // Метод .cast() превратит указатель на функцию в нужный тип в рантайме
    uaCfg.ref.cb.on_incoming_call = incomingCallCallable.nativeFunction.cast();
    // =========================================================================

    // ПОДКЛЮЧАЕМ КОЛБЭК ИЗМЕНЕНИЯ СОСТОЯНИЯ ЗВONKA
    final callStateCallable = ffi.NativeCallable<
        ffi.Void Function(ffi.Int32, ffi.Pointer<pjsip_rx_data>)
    >.listener(dartOnCallState);
    uaCfg.ref.cb.on_call_state = callStateCallable.nativeFunction.cast();

    // регистрация медиа-колбэка:
    final callMediaStateCallable = ffi.NativeCallable<
        ffi.Void Function(ffi.Int32)
    >.listener(dartOnCallMediaState);
    // Записываем указатель на функцию в структуру настроек pjsua
    uaCfg.ref.cb.on_call_media_state = callMediaStateCallable.nativeFunction.cast();

    // Инициализируем и запускаем стек
    _pjsipGlobal.pjsua_init(uaCfg, logCfg, mediaCfg);

    final transportCfg = calloc<pjsua_transport_config>();
    _pjsipGlobal.pjsua_transport_config_default(transportCfg);
    transportCfg.ref.port = 5060;

    final transportIdPtr = calloc<ffi.Int32>();
    // Метод .cast() превратит указатель в нужный тип
    _pjsipGlobal.pjsua_transport_create(pjsip_transport_type_e.PJSIP_TRANSPORT_UDP, transportCfg, transportIdPtr.cast());

    _pjsipGlobal.pjsua_start();
    print("[🚀] PJSIP запущен с поддержкой входящих вызовов!");
    _isInitialized = true;





    // =========================================================================
    // ШТАТНОЕ АРХИТЕКТУРНОЕ ОТКЛЮЧЕHИЕ ТЕКСТОВЫХ КАНАЛОВ ИЗ SDP
    // =========================================================================
    // Запрещаем кодеки t140 и red, выставляя их приоритет в 0.
    // Если приоритет кодека равен 0, PJSIP полностью исключает его из m= линий.
    final List<String> textCodecs = ["t140/8000", "red/1000", "t140", "t140/90000"];

    for (var codecName in textCodecs) {
      try {
        // 1. Переводим имя кодека в обычную C-строку
        final ffi.Pointer<ffi.Char> codecNameNative = codecName.toNativeUtf8().cast();

        // 2. Создаем структуру pj_str_t штатными средствами PJSIP.
        // В вашей библиотеке есть встроенная функция pj_str, которая принимает
        // обычный char* и возвращает правильную, готовую структуру pj_str_t.
        // Название функции в биндингах: pj_str или pj_str_t_from_char
        final pj_str_t pjCodecStr = _pjsipGlobal.pj_str(codecNameNative);

        // Выделяем память под структуру pj_str_t, чтобы передать её по указателю
        final ffi.Pointer<pj_str_t> pjStrPtr = calloc<pj_str_t>();
        pjStrPtr.ref = pjCodecStr;

        // 3. Вызываем функцию изменения приоритета.
        // Передаем указатель на pj_str_t. Значение 0 означает "disabled".
        final int status = _pjsipGlobal.pjsua_codec_set_priority(pjStrPtr, 0);

        if (status == 0) {
          print("[🧹 PJSIP] Текстовый кодек '$codecName' успешно отключен на уровне ядра.");
        } else {
          print("[⚠️ PJSIP] Ошибка отключения кодека '$codecName'. Код PJSIP: $status");
        }

        // Освобождаем выделенную память C
        calloc.free(pjStrPtr);
        calloc.free(codecNameNative);
      } catch (e) {
        print("[❌ PJSIP] Исключение при деактивации кодека $codecName: $e");
      }
    }
    print("[✅ PJSIP] Процедура очистки медиа-стека завершена.");





    // Чистим временную память
    calloc.free(uaCfg);
    calloc.free(logCfg);
    calloc.free(mediaCfg);
    calloc.free(transportCfg);
    calloc.free(transportIdPtr);
  }

  // Возвращает Pointer<pj_str_t> с заполненными данными
  ffi.Pointer<pj_str_t> _createPjsipString(String dartStr, List<ffi.Pointer> tracker) {
    final utf8Ptr = dartStr.toNativeUtf8();
    tracker.add(utf8Ptr); // Запоминаем указатель на текст, чтобы удалить потом
    final pjStrPtr = calloc<pj_str_t>();

    // Записываем указатель на строку в первые 8 байт
    final ffi.Pointer<ffi.Pointer<ffi.Char>> ptrLocation = pjStrPtr.cast();
    ptrLocation.value = utf8Ptr.cast<ffi.Char>();
    // Записываем длину
    try {
      (pjStrPtr as dynamic).slen = utf8Ptr.length;
    } catch (_) {
      final ffi.Pointer<ffi.Int64> slenLocation = ffi.Pointer.fromAddress(
          pjStrPtr.address + ffi.sizeOf<ffi.Pointer>()
      );
      slenLocation.value = dartStr.length;
    }
    return pjStrPtr;
  }

  void registerAccount(String server, String user, String password) {
    // ЕСЛИ АККАУНТ УЖЕ БЫЛ СОЗДАН РАНЕЕ — УДАЛЯЕМ ЕГО ИЗ PJSIP
    // Если создать аккаунтов больше чем слотов, будет ошибка
    // Assertion failed: (pjsua_var.acc_cnt < (sizeof(pjsua_var.acc)/sizeof(pjsua_var.acc[0]))), function pjsua_acc_add, file pjsua_acc.c, line 548.
    if (_accId != -1) {
      print("[🔄 PJSIP] Удаляем старую конфигурацию аккаунта ID: $_accId перед перезапуском...");
      _pjsipGlobal.pjsua_acc_del(_accId);
      _accId = -1; // Сбрасываем ID
    }

    // Создаем трекер для очистки
    final List<ffi.Pointer> stringsTracker = [];
    try {
      final accCfg = calloc<pjsua_acc_config>();
      _pjsipGlobal.pjsua_acc_config_default(accCfg);

      // Создаем временные строки в памяти C
      final idStr = _createPjsipString("sip:$user@$server", stringsTracker);
      final regStr = _createPjsipString("sip:$server", stringsTracker);
      // "digest" не сработает, нужно "*"
      // это скажет PJSIP использовать этот пароль для любого realm от АТС
      final realmStr = _createPjsipString("*", stringsTracker); // digest
      final userStr = _createPjsipString(user, stringsTracker);
      final passStr = _createPjsipString(password, stringsTracker);
      //final uaStr = _createPjsipString("$user@$server");
      //final uaStrKey = _createPjsipString("User-Agent");

      // ПРИСВАИВАЕМ НАПРЯМУЮ. Dart FFI скопирует содержимое структур в accCfg!
      accCfg.ref.id = idStr.ref;
      accCfg.ref.reg_uri = regStr.ref;
      accCfg.ref.cred_count = 1;
      final cred = accCfg.ref.cred_info[0];

      cred.realm = realmStr.ref;
      cred.username = userStr.ref;
      cred.data$1 = passStr.ref; // По-дурацки, смотрим в class pjsip_cred_info биндингов
      cred.data_type = 0; // Plain text password
      // user_id (для некоторых АТС типа Asterisk это критично)
      // TODO: заполнение user_id (для некоторых АТС типа Asterisk это критично)

      final accIdPtr = calloc<ffi.Int32>();
      // Можно добавлять ограниченное кол-во аккаунтов (например, 4)
      // Если закончатся слоты будет
      // Assertion failed: (pjsua_var.acc_cnt < (sizeof(pjsua_var.acc)/sizeof(pjsua_var.acc[0]))), function pjsua_acc_add, file pjsua_acc.c, line 548.
      final status = _pjsipGlobal.pjsua_acc_add(accCfg, 1, accIdPtr.cast());

      if (status == 0) {
        _accId = accIdPtr.value;
        print("[🌐] Аккаунт отправлен на АТС. Локальный ID: $_accId");
      } else {
        print("[❌] Ошибка добавления аккаунта: $status");
      }

      // Освобождаем выделенную память
      calloc.free(accCfg);
      calloc.free(accIdPtr);
      // Чистим указатели на строки
      calloc.free(idStr);
      calloc.free(regStr);
      calloc.free(realmStr);
      calloc.free(userStr);
      calloc.free(passStr);

      // Нельзя чистить, т/к вызовем поздже асинхронно
      //calloc.free(uaStr);
      //calloc.free(uaStrKey);
    } finally {
      // В САМОМ КОНЦЕ, когда pjsua_acc_add уже отработал,
      // мы удаляем массивы символов, которые насоздавал toNativeUtf8()
      for (final textPtr in stringsTracker) {
        calloc.free(textPtr);
      }
      print("[🧹] Текст строк успешно очищен из памяти. Утечек нет!");
    }
  }


  // Метод совершения исходящего звонка
  void makeCall(String number, String server) {
    if (_accId == -1) {
      print("[❌] Ошибка: Невозможно совершить звонок, аккаунт не зарегистрирован.");
      return;
    }
    // Создаем трекер для очистки
    final List<ffi.Pointer> stringsTracker = [];
    try {
      // Формируем целевой SIP URI: sip:102@192.168.1.100
      final targetUri = "sip:$number@$server";
      final pjStr = _createPjsipString(targetUri, stringsTracker);
      final callIdPtr = calloc<ffi.Int32>();

      // Создаем структуру настроек вызова
      final callSetting = calloc<pjsua_call_setting>();
      _pjsipGlobal.pjsua_call_setting_default(callSetting);
      // Явно указываем, что в звонке должен быть только 1 поток
      // Из-за m=text 4002 RTP/AVP 100 98
      // для ДСИ валится звонок с ошибкой 486 Busy here
      callSetting.ref.aud_cnt = 1;
      callSetting.ref.vid_cnt = 0;
      // Поле txt_cnt отвечает за Real-Time Text. Выставляем в 0.
      callSetting.ref.txt_cnt = 0;
      // Отключаем включение заблокированных/неактивных медиа-линий
      // По умолчанию там PJSUA_CALL_INCLUDE_DISABLED_MEDIA, меняем флаг на 0
      callSetting.ref.flag = 0;
      print("[🧹 PJSIP] Установлено жесткое ограничение: aud_cnt = 1 (Только Аудио).");

      print("[📞 PJSIP] Инициируем вызов на: $targetUri ...");
      _callStateStream.add(SipCallState(state: "Вызываю...", statusCode: 180)); // Сразу выставляем статус старта

      // Совершаем вызов через сгенерированные биндинги
      // Передаем заполненную структуру msgData четвертым аргументом (вместо ffi.nullptr)
      final status = _pjsipGlobal.pjsua_call_make_call(
          _accId,
          pjStr,
          callSetting, // настройки вызова по умолчанию
          ffi.nullptr, // Передаем нашу структуру с кастомным User-Agent
          ffi.nullptr,
          callIdPtr.cast(),
      );

      if (status == 0) {
        print("[✅ PJSIP] Звонок успешно запущен! Идентификатор звонка ID: ${callIdPtr.value}");
      } else {
        print("[❌ PJSIP] Ошибка инициализации звонка. Код: $status");
      }

      // Чистим память
      calloc.free(pjStr);
      calloc.free(callIdPtr);
    } finally {
      // В САМОМ КОНЦЕ, когда pjsua_acc_add уже отработал,
      // мы удаляем массивы символов, которые насоздавал toNativeUtf8()
      for (final textPtr in stringsTracker) {
        calloc.free(textPtr);
      }
      print("[🧹] Текст строк успешно очищен из памяти. Утечек нет!");
    }
  }

  // Получение данных по аккаунту
  Map<String, String> get account {
    if (_accId == -1) return {};
    final Map<String, String> result = {};
    final accInfo = calloc<pjsua_acc_info>();
    final status = _pjsipGlobal.pjsua_acc_get_info(_accId, accInfo);
    if (status == 0) {
      // Извлекаем reg_uri, который мы туда записывали: "sip:192.168.1.100"
      final pjStr = accInfo.ref.acc_uri;
      if (pjStr.ptr$1 != ffi.nullptr && pjStr.slen > 0) {
        final fullUri = pjStr.ptr$1.cast<Utf8>().toDartString(length: pjStr.slen);
        result['uri'] = fullUri;
        // Номер (между "sip:" и "@")
        final numMatch = RegExp(r'sip:(.*?)@').firstMatch(fullUri);
        result['number'] = numMatch?.group(1) ?? 'Unknown';
        result['server'] = fullUri.split("@").last;
        result['status_code'] = accInfo.ref.statusAsInt.toString();
        result['status_text'] = accInfo.ref.status_text.ptr$1.cast<Utf8>().toDartString();
      }
    }
    calloc.free(accInfo);
    return result;
  }

  // МЕТОД ДЛЯ СБРОСА/ОТМЕНЫ АКТИВНОГО ЗВONKA
  void hangup() {
    if (_activeCallId == -1) {
      print("[ℹ️] Нет активного звонка для сброса.");
      return;
    }
    print("[📴 PJSIP] Сбрасываем звонок ID: $_activeCallId ...");
    if (_pjsipGlobal.pjsua_call_is_active(_activeCallId) == 1) {
      // Функция pjsua_call_hangup принимает ID звонка, код ответа (обычно 0 для сброса)
      // и опциональные текстовые заголовки.
      final status = _pjsipGlobal.pjsua_call_hangup(
          _activeCallId, 0, ffi.nullptr, ffi.nullptr);
      if (status == 0) {
        print("[✅ PJSIP] Запрос на сброс отправлен.");
      } else {
        print("[❌ PJSIP] Ошибка сброса звонка: $status");
      }
    }
    _activeCallId = -1;
    _callStateStream.add(SipCallState(state: "Завершен"));
  }

  // ДОБАВЛЯЕМ МЕТОД ДЛЯ ПРИНЯТИЯ ВХОДЯЩЕГО ЗВОНКА
  void answer() {
    if (_activeCallId == -1) {
      print("[ℹ️ PJSIP] Нет активного вызова для ответа.");
      return;
    }
    print("[📞 PJSIP] Поднимаем трубку для звонка ID: $_activeCallId ...");
    // Отправляем SIP-код "200 OK" (поднятие трубки) на АТС
    // Третий и четвертый аргументы — настройки вызова и кастомные заголовки (нам не нужны)
    final status = _pjsipGlobal.pjsua_call_answer(_activeCallId, 200, ffi.nullptr, ffi.nullptr);
    if (status == 0) {
      print("[✅ PJSIP] Сигнал поднятия трубки (200 OK) отправлен.");
      _callStateStream.add(SipCallState(state: "Разговор", statusCode: 200));
    } else {
      print("[❌ PJSIP] Ошибка поднятия трубки. Код: $status");
    }
  }
}