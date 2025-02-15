import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

// 알람 기능을 담당하는 컨트롤러 입니다.
// main.dart 파일에서 초기화 함수를 호출 합니다.


// 독립적인 실행 환경인 백그라운드 핸들러
@pragma('vm: entry-point')
Future<void> _backgroundHandler(RemoteMessage remoteMessage) async {
  print('backgroundHand: $remoteMessage');
  NotificationController._showNotification(remoteMessage);
}

class NotificationController {
  static final NotificationController _notificationController = NotificationController
      ._privateConstructor();

  static NotificationController get instance => _notificationController;
  FirebaseMessaging messaging = FirebaseMessaging.instance; // FCM 객체

  // 포그라운드 상태 메시지 수신을 위한 로컬 알림 인스턴스
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // 안드로이드 알림 채널 설정(API26 이상부터 필수)
  // 포그라운드 상태에서 알람을 표시하려면 중요도를 high로 설정
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
      'channel', 'channel name',
      description: 'this is used for important notifications',
      importance: Importance.high);

  NotificationController._privateConstructor(); // 내부 생성자

  Future<void> initialize() async {
    await _requestPermission();

    // 푸시 알림 리스너 설정
    FirebaseMessaging.onMessage.listen(_foregroundHandler);
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenHandler); // 푸시 알림 클릭 시 설정

    if (!kIsWeb) {
      await _setupFlutterNotifications();
    }
  }

  // 포그라운드 상태: 라우팅 경로 전달해서 지정된 페이지로 이동하도록
  Future<void> _foregroundHandler(RemoteMessage remoteMessage) async {
    String? path = _getRoutePath(remoteMessage);
    print(path);
    _showNotification(remoteMessage, payload: path);
  }

  // 포그라운드 또는 백그라운드 상태에서 알람 표시
  static Future<void> _showNotification(RemoteMessage message, {String? payload}) async {
    RemoteNotification? notification = message.notification; // 공통으로 수신하는 푸시 알림 객체
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null && !kIsWeb) {
      NotificationController._localNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails( // 안드로이드에서 사용하는 추가 정보 객체
          android: AndroidNotificationDetails(
            NotificationController._channel.id, // 채널 정보
            NotificationController._channel.name,
            channelDescription: NotificationController._channel.description,
            icon: '@mipmap/launcher_icon',
          ),
        ),
        payload: payload ?? "", // 경로 전달
      );
    }
  }

  // 권한 요청 (ios / android API33 이상)
  Future<void> _requestPermission() async {
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
  }

  // 알람 서비스 초기화
  static Future<void> _setupFlutterNotifications() async {
    InitializationSettings initSettings = const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
      iOS: DarwinInitializationSettings(),
    );

    // 로컬 알림 객체 초기화
    _localNotificationsPlugin.initialize(initSettings,
        onDidReceiveNotificationResponse:
        instance._onForegroundMessageOpenHandler);

    // 안드로이드 알림 채널 생성
    await NotificationController._localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // ios 포그라운드 알림 허용
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  // 포그라운드 상태에서 알림 클릭 시 페이지 라우팅
  void _onForegroundMessageOpenHandler(
      NotificationResponse notificationResponse) {
    String? payload = notificationResponse.payload;

    switch (notificationResponse.notificationResponseType) {
      case NotificationResponseType.selectedNotification:
        if (payload == null) {
          return;
        }
        _onClickPush(payload);
        break;
      case NotificationResponseType.selectedNotificationAction:
        break;
    }
  }

  // 백그라운드 상태에서 알림 클릭 시
  void _onMessageOpenHandler(RemoteMessage message) {
    String? path = _getRoutePath(message);
    if (path == null) {
      return;
    }
    _onClickPush(path);
  }

  String? _getRoutePath(RemoteMessage message) {
    if (!message.data.containsKey("path")) {
      return null;
    }
    return message.data['path'] as String;
  }

  void _onClickPush(String appLink, {Map<String, dynamic>? parameters}) async {
    Uri uri = Uri.parse(appLink);
    await launchUrl(uri);
  }
}