import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() => runApp(const TicketApp());

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
    String? idGuardado = prefs.getString('mi_id_unico_sasma');
    if (idGuardado == null) {
      var uuid = const Uuid();
      idGuardado = uuid.v4();
      await prefs.setString('mi_id_unico_sasma', idGuardado);
    }
    imei = idGuardado;
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
