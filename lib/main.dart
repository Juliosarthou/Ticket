import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:io';


@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Manejo de notificaciones en 2do plano
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint("Firebase ya estaba inicializado o falló: $e");
  }
  runApp(const TicketApp());
}

class TicketApp extends StatelessWidget {
  const TicketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ticket',
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF954C45), // Azul institucional sugerido para Ticket
      ),
      home: const WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  WebViewController? _controller;
  bool _hasError = false;
  bool _isLoading = true;
  String imei = "buscando...";

  @override
  void initState() {
    super.initState();
    _inicializarApp();
  }

  Future<void> _reintentar() async {
    setState(() {
      _hasError = false;
      _isLoading = true;
    });
    _controller?.loadRequest(Uri.parse('https://sau.faa.unicen.edu.ar/app/index.php?imei=$imei'));
  }

  Future<void> _inicializarApp() async {
    await _obtenerOgenerarIdPersistente();
    _configurarNotificaciones(); // Iniciar configuración de notificaciones push
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white) 
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            // Manejo de errores de red
            if (error.errorCode < 0) {
              setState(() {
                _hasError = true;
                _isLoading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('https://sau.faa.unicen.edu.ar/app/index.php?imei=$imei'));
    
    setState(() {});
  }

  Future<void> _obtenerOgenerarIdPersistente() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    // Usamos la misma clave si queremos compartir el ID entre apps del mismo usuario, 
    // pero aquí usaremos una propia para Ticket.
    String? idGuardado = prefs.getString('mi_id_unico_ticket');
    if (idGuardado == null) {
      var uuid = const Uuid();
      idGuardado = uuid.v4();
      await prefs.setString('mi_id_unico_ticket', idGuardado);
    }
    imei = idGuardado;
  }

  // --- LÓGICA DE NOTIFICACIONES PUSH ---
  Future<void> _configurarNotificaciones() async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;

      // Pedir permisos (crucial en iOS)
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('Estado de autorización: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized || 
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        
        // En iOS, necesitamos asegurar que el token APNS esté listo
        // Incrementamos reintentos y tiempo de espera para redes lentas
        if (Platform.isIOS) {
          String? apnsToken;
          int maxReintentos = 15; // 30 segundos en total
          int reintentos = 0;
          
          while (apnsToken == null && reintentos < maxReintentos) {
            apnsToken = await messaging.getAPNSToken();
            if (apnsToken == null) {
              debugPrint("Llamando a getAPNSToken... (reintento $reintentos de $maxReintentos)");
              await Future.delayed(const Duration(seconds: 2));
              reintentos++;
            }
          }

          if (apnsToken == null) {
            debugPrint("ADVERTENCIA: No se obtuvo token APNS tras 30s. Las notificaciones push NO funcionarán en este arranque.");
            // No nos detenemos, intentaremos con getToken de todas formas por si acaso
          } else {
            debugPrint("TOKEN APNS FINAL: $apnsToken");
          }
        }

        // Obtener el Token FCM (Firebase)
        String? fcmToken = await messaging.getToken();
        if (fcmToken != null) {
          debugPrint("TOKEN FCM FINAL: $fcmToken");
          await _enviarTokenAlServidor(fcmToken);
        }

        // Refresco automático del token
        messaging.onTokenRefresh.listen((newToken) async {
          debugPrint("FCM Token refrescado automáticamente: $newToken");
          await _enviarTokenAlServidor(newToken);
        });

        // Configuración para mostrar notificaciones con la app abierta
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        // Debug de recepción en primer plano
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          debugPrint("Mensaje recibido (Foreground): ${message.notification?.title}");
        });
      }
    } catch (e) {
      debugPrint("Error crítico configurando notificaciones: $e");
    }
  }


  Future<void> _enviarTokenAlServidor(String fcmToken) async {
    try {
      final url = Uri.parse('https://sau.faa.unicen.edu.ar/app/g_token.php');
      final response = await http.post(
        url,
        body: {
          'imei': imei,
          'token': fcmToken,
        },
      );

      if (response.statusCode == 200) {
        debugPrint("Respuesta servidor g_token: ${response.body}");
      } else {
        debugPrint("Error al enviar token al servidor. Status: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Excepción al enviar token: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (imei == "buscando..." || _controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF954C45))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Opacity(
              opacity: (_hasError || _isLoading) ? 0.0 : 1.0,
              child: WebViewWidget(controller: _controller!),
            ),
            
            if (_hasError) _buildErrorView(),
            
            if (_isLoading && !_hasError)
              Container(
                color: Colors.white,
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF954C45)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Container(
      color: const Color(0xFF954C45), 
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 100, color: Colors.white),
          const SizedBox(height: 30),
          const Text(
            'Sin conexión',
            style: TextStyle(
              fontSize: 28, 
              fontWeight: FontWeight.bold, 
              color: Colors.white,
              fontStyle: FontStyle.italic
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'No se puede establecer comunicación con el servidor',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.white70),
          ),
          const SizedBox(height: 50),
          ElevatedButton.icon(
            onPressed: _reintentar,
            icon: const Icon(Icons.refresh),
            label: const Text('REINTENTAR CONEXIÓN', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF954C45),
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
          ),
        ],
      ),
    );
  }
}
