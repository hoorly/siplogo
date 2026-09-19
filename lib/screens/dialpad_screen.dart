import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:siplogo/screens/register_screen.dart';
import 'package:siplogo/sip_service.dart';
import 'package:siplogo/utils/phone_number_manager.dart';

class DialpadScreen extends StatefulWidget {
  final SipService sipService;

  const DialpadScreen({super.key, required this.sipService});

  @override
  State<DialpadScreen> createState() => _DialpadScreenState();
}

class _DialpadScreenState extends State<DialpadScreen> {
  String _inputNumber = "";
  late Map<String, String> account;
  StreamSubscription<SipCallState>? _callStatusSubscription;
  // ДОБАВЛЯЕМ ФЛАГ, ЧТОБЫ ОКНО НЕ ОТКРЫВАЛОСЬ ДВАЖДЫ
  bool _isDialogShowing = false;
  // ДОБАВЛЯЕМ FOCUS NODE ДЛЯ КЛАВИАТУРЫ
  final FocusNode _focusNode = FocusNode();
  // ДОБАВЛЯЕМ ФЛАГ БЛОКИРОВКИ ПОВТОРНЫХ ЗВОНКОВ
  bool _isCallingInProgress = false;

  @override
  void initState() {
    super.initState();
    account = widget.sipService.account;
    // СЛУШАЕМ СТАТУС ЗВОНКА. Если пошел вызов — открываем карточку управления звонком
    _callStatusSubscription = sipCallStateStream.listen((callStatus) {
      // ПРОВЕРЯЕМ, ЧТО ВИДЖЕТ СУЩЕСТВУЕТ В ДЕРЕВЕ
      if (!mounted) return;
      if (callStatus.state == "Вызываю..." ||
          callStatus.state == "Входящий вызов...") {
        _showCallDialog(context);
      } else if (callStatus.state == "Завершен") {
        setState(() {
          _isCallingInProgress = false;
        });
      }
    });
    // Запрашиваем фокус сразу после отрисовки первого кадра
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _callStatusSubscription?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    // Реагируем только на нажатие клавиши (KeyDownEvent),
    // чтобы не дублировать ввод при отпускании (KeyUpEvent)
    if (event is KeyDownEvent) {
    } else {
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      // Если нажат Backspace (удаление)
      _backspace();
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      // Если нажат Enter / Return (совершить звонок)
      _handleCall();
    } else if (event.character != null) {
      _pressKey(event.character!);
    }
  }

  // ФУНКЦИЯ ОТОБРАЖЕНИЯ ОКНА АКТИВНОГО ВЫЗОВА
  void _showCallDialog(BuildContext context) {
    if (_isDialogShowing) {
      return; // Не открываем повторно
    }
    // Выставляем флаг, что окно открыто
    _isDialogShowing = true;
    showModalBottomSheet(
      context: context,
      isDismissible: false, // Пользователь не может закрыть окно свайпом, только кнопкой сброса
      enableDrag: false,
      backgroundColor: Colors.indigo.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext dialogContext) {
        // dialogContext чтобы не путаться
        return StreamBuilder<SipCallState>(
          stream: sipCallStateStream,
          initialData: SipCallState(state: "Вызываю...", statusCode: 180),
          builder: (context, snapshot) {
            final callState = snapshot.data;
            final currentCallState = callState?.state ?? "Завершен";
            // Если звонок завершился на стороне АТС/собеседника — автоматически закрываем окно
            if (currentCallState == "Завершен") {
              // Используем Future.microtask вместо addPostFrameCallback.
              // Это гарантирует выполнение pop() сразу после завершения текущего цикла сборки виджета.
              Future.microtask(() async {
                // Для надежности используем Navigator.pop с контекстом диалога,
                // проверяя, что он еще активен в дереве виджетов.
                if (dialogContext.mounted && _isDialogShowing) {
                  // Даем пользователю время прочитать результат звонка
                  await Future.delayed(const Duration(seconds: 1));
                  _isDialogShowing = false;
                  Navigator.of(dialogContext).pop();
                }
              });
              /*
              if (_isDialogShowing && mounted) {
                _isDialogShowing = false; // Сбрасываем флаг
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  // Закрываем окно, используя правильный контекст диалога
                  if (Navigator.canPop(dialogContext)) {
                    Navigator.of(dialogContext).pop();
                  }
                });
              }
              */
            }
            // Проверяем, является ли звонок входящим в данный момент
            final bool isIncoming = currentCallState == "Входящий вызов...";
            return Container(
              padding: const EdgeInsets.all(32),
              height: 320,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isIncoming
                        ? "Входящий звонок"
                        : (_inputNumber.isEmpty
                              ? "Разговор"
                              : formatPhoneNumber(_inputNumber)),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    currentCallState,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.indigo.shade100,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  /*
                  callState?.state == "Завершен"
                      ? Text(
                          callState?.getReason() ?? '',
                          style: TextStyle(
                            fontSize: 18,
                            color: (callState?.statusCode ?? 0) >= 400
                                ? Colors.red.shade300
                                : Colors.indigo.shade100,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      : SizedBox(),

                  */
                  const SizedBox(height: 40),
                  // РЯД С КНОПКАМИ УПРАВЛЕНИЯ ЗВOНКОМ
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // КНОПКА СБРОСА (Отображается ВСЕГДА)
                      IconButton(
                        icon: const Icon(Icons.call_end, size: 36),
                        color: Colors.white,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.all(20),
                        ),
                        onPressed: () {
                          if (_isDialogShowing && mounted) {
                            _isDialogShowing = false;
                            setState(() {
                              _isCallingInProgress = false;
                            });
                            widget.sipService
                                .hangup(); // Отклонить или положить трубку
                            Navigator.of(dialogContext).pop();
                          }
                        },
                      ),
                      // КНОПКА ОТВЕТА (Появляется ТОЛЬКО при входящем звонке)
                      if (isIncoming) ...[
                        const SizedBox(width: 40), // Отступ между кнопками
                        IconButton(
                          icon: const Icon(Icons.call, size: 36),
                          color: Colors.white,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.all(20),
                          ),
                          onPressed: () {
                            if (mounted) {
                              widget.sipService
                                  .answer(); // Поднять трубку в PJSIP
                              // Окно НЕ закрываем, так как статус сменится на "Разговор"
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      // СТРАХОВКА: если окно закрылось любым другим образом, сбрасываем флаг
      _isDialogShowing = false;
    });
  }

  void _pressKey(String value) {
    setState(() {
      _inputNumber += value;
    });
  }

  void _backspace() {
    if (_inputNumber.isNotEmpty) {
      setState(() {
        _inputNumber = _inputNumber.substring(0, _inputNumber.length - 1);
      });
    }
  }

  void _handleCall() {
    if (_isCallingInProgress ||
        _inputNumber.isEmpty ||
        account['server'] == null) {
      return;
    }
    setState(() {
      _isCallingInProgress = true;
    });
    widget.sipService.makeCall(_inputNumber, account['server']!);
  }

  // Вспомогательный виджет для отрисовки круглых кнопок диалпада
  Widget _buildDialButton(String text) {
    return Container(
      margin: const EdgeInsets.all(8),
      child: InkWell(
        onTap: () => _pressKey(text),
        borderRadius: BorderRadius.circular(40),
        child: Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey.withValues(alpha: 0.15),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    /* На экране диалпада можно набирать с клавиатуры,
       нажатие на экран GestureDetector возвращает фокус ввода,
       слушаем клавиатуру, поэтому KeyboardListener
    */
    return GestureDetector(
      onTap: () {
        if (!_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      },
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent, // Наш обработчик нажатий
        child: Scaffold(
          appBar: AppBar(
            title: Text('Линия: ${account['number']}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.red),
                onPressed: () {
                  // Сначала безопасно удаляем SIP-аккаунт из памяти PJSIP
                  widget.sipService.logout();
                  // Возврат на экран авторизации
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RegisterScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                vertical: 24.0,
                horizontal: 16.0,
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Дисплей набранного номера
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            _inputNumber.isEmpty
                                ? "Введите номер"
                                : formatPhoneNumber(_inputNumber),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 31,
                              fontWeight: FontWeight.bold,
                              color: _inputNumber.isEmpty
                                  ? Colors.grey
                                  : Colors.black,
                            ),
                          ),
                        ),
                        if (_inputNumber.isNotEmpty)
                          IconButton(
                            icon: const Icon(
                              Icons.backspace_outlined,
                              size: 28,
                            ),
                            onPressed: _backspace,
                          ),
                      ],
                    ),
                    const SizedBox(height: 40),

                    //Сетка кнопок 3х4
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildDialButton("1"),
                            _buildDialButton("2"),
                            _buildDialButton("3"),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildDialButton("4"),
                            _buildDialButton("5"),
                            _buildDialButton("6"),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildDialButton("7"),
                            _buildDialButton("8"),
                            _buildDialButton("9"),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildDialButton("*"),
                            _buildDialButton("0"),
                            _buildDialButton("#"),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Кнопка вызова
                    IconButton(
                      icon: const Icon(Icons.call, size: 40),
                      color: Colors.green,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.green.withValues(alpha: 0.2),
                        padding: const EdgeInsets.all(20),
                      ),
                      onPressed: _handleCall,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
