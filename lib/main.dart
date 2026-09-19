import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:siplogo/notifications/test_notification.dart';
import 'package:siplogo/pjsip_binder.dart';
import 'package:siplogo/screens/register_screen.dart';
import 'package:siplogo/sip_service.dart' show SipService;

// Создаем глобальный экземпляр плагина
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Настройка инициализации для macOS
  const InitializationSettings initializationSettings = InitializationSettings(
    macOS: DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    ),
  );

  await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}
// Добавляем WidgetsBindingObserver для отслеживания жизненного цикла приложения
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final SipService _sipService = SipService();

  @override
  void initState() {
    super.initState();
    // Регистрируем наблюдатель за состоянием приложения
    WidgetsBinding.instance.addObserver(this);

    showTestNotification();
  }

  @override
  void dispose() {
    // Удаляем наблюдатель
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Если приложение закрывается
    if (state == AppLifecycleState.detached) {
      print("[🖥️] Зафиксировано закрытие приложения.");
      _sipService.terminate(); // Вызываем чистую очистку PJSIP
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIPLOGO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      //home: const MyHomePage(title: 'Flutter Demo Home Page'),
      home: const RegisterScreen(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final PjsipMacBinder _pjsip = PjsipMacBinder();
  String _status = "Библиотека не загружена";

  void _initSip() {
    try {
      _pjsip.loadLibrary();
      _pjsip.initCore();
      setState(() {
        _status = "PJSIP запущен на macOS!";
      });
    } catch (e) {
      print('$e');
      setState(() {
        _status = "Ошибка: ${e.toString()}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: .center,
          children: [
            Text(
              _status,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _initSip,
        tooltip: 'Load sip',
        child: const Icon(Icons.add),
      ),
    );
  }
}
