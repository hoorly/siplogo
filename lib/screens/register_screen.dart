import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:siplogo/screens/dialpad_screen.dart';
import 'package:siplogo/sip_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final SipService _sipService = SipService();
  StreamSubscription<int>? _statusSubscription;

  // Контроллеры полей ввода
  final TextEditingController _serverController = TextEditingController(text: "192.168.1.100");
  final TextEditingController _userController = TextEditingController(text: "test");
  final TextEditingController _passwordController = TextEditingController(text: "test");

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _serverController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Инициализируем и запускаем ядро PJSIP при открытии приложения
    try {
      _sipService.initAndStart();
    } catch (e) {
      print("Ошибка старта PJSIP: $e");
    }
    // Подписываемся на стрим статуса, чтобы поймать успешный вход
    _statusSubscription = sipRegistrationStatus.listen((status) {
      final account = _sipService.account;
      if (account['status_code'] == "200") {
        // Переходим на экран номеронабирателя БЕЗ возможности вернуться назад
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DialpadScreen(
              sipService: _sipService,
            ),
          ),
        );
      }
    });
    // Загружаем сохраненные настройки при старте экрана
    _loadSavedSettings();
  }

  // Метод для загрузки данных из памяти устройства
  Future<void> _loadSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        // Если данных в памяти нет, подставятся ваши дефолтные значения
        _serverController.text = prefs.getString('sip_server') ?? "192.168.1.100";
        _userController.text = prefs.getString('sip_user') ?? "test";
        _passwordController.text = prefs.getString('sip_password') ?? "test";
      });
      print("[💾] Настройки авторизации успешно загружены из памяти устройства.");
    } catch (e) {
      print("[❌] Ошибка загрузки быстрых настроек: $e");
    }
  }

  // Метод для сохранения данных в память устройства
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sip_server', _serverController.text.trim());
      await prefs.setString('sip_user', _userController.text.trim());
      await prefs.setString('sip_password', _passwordController.text.trim());
      print("[💾] Новые настройки авторизации успешно сохранены.");
    } catch (e) {
      print("[❌] Ошибка сохранения быстрых настроек: $e");
    }
  }

  void _onConnectPressed() {
    // Сначала сохраняем введенные данные в быстрые настройки
    _saveSettings();
    // Вызываем метод регистрации из нашего сервиса
    _sipService.registerAccount(
      _serverController.text.trim(),
      _userController.text.trim(),
      _passwordController.text.trim(),
    );
  }

  // Вспомогательный метод для определения цвета индикатора статуса
  Color _getStatusColor(int status) {
    switch (status) {
      case 200:
        return Colors.green;
      case 0:
        return Colors.orange;
      case 403:
      case 401:
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Авторизация SIP'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Стрим-виджет, который автоматически перерисовывает статус при ответах от C++ PJSIP
                StreamBuilder<int>(
                  stream: sipRegistrationStatus,
                  initialData: 0,
                  builder: (context, snapshot) {
                    final statusText = snapshot.data ?? 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: _getStatusColor(statusText).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _getStatusColor(statusText)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 6,
                            backgroundColor: _getStatusColor(statusText),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Статус: $statusText',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _getStatusColor(statusText),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),
          
                TextField(
                  controller: _serverController,
                  decoration: const InputDecoration(
                    labelText: 'SIP-Сервер (IP или Домен)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.dns),
                  ),
                ),
                const SizedBox(height: 16),
          
                TextField(
                  controller: _userController,
                  decoration: const InputDecoration(
                    labelText: 'Внутренний номер (Логин)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
          
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 24),
          
                ElevatedButton(
                  onPressed: _onConnectPressed,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Подключиться',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}