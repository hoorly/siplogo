import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:siplogo/main.dart';

// Функция отправки тестового уведомления
Future<void> showTestNotification() async {
  const NotificationDetails notificationDetails = NotificationDetails(
    macOS: DarwinNotificationDetails(
      presentAlert: true, // Показывать баннер
      presentBadge: true, // Обновлять бейдж на иконке приложения
      presentSound: true, // Воспроизводить системный звук
    ),
  );

  await flutterLocalNotificationsPlugin.show(
    id: 0, // ID уведомления
    notificationDetails: notificationDetails,
    title: 'Заголовок из Flutter',
    body: 'Это тестовое уведомление для Центра уведомлений macOS.',
  );
}
