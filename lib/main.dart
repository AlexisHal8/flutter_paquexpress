import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// --- CONFIGURACIÓN GLOBAL ---
// CAMBIA ESTO: Usa 'http://10.0.2.2:8000' para Emulador Android
// Usa 'http://127.0.0.1:8000' para iOS Simulator o Web
// Usa tu IP local (ej 'http://192.168.1.50:8000') para celular físico
const String BASE_URL = 'http://127.0.0.1:8000'; 

void main() {
  runApp(const PaquexpressApp());
}

// --- TEMA Y COLORES (Estilo Amazon) ---
class AppColors {
  static const Color primary = Color(0xFF232F3E); // Gris Oscuro Amazon
  static const Color secondary = Color(0xFFFF9900); // Naranja Amazon
  static const Color background = Color(0xFFEAEDED); // Gris Claro Fondo
  static const Color text = Color(0xFF111111);
}

class PaquexpressApp extends StatelessWidget {
  const PaquexpressApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paquexpress',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.black, // Texto negro en botón naranja
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

// --- SERVICIO DE API ---
class ApiService {
  final Dio _dio = Dio(BaseOptions(baseUrl: BASE_URL));
  final _storage = const FlutterSecureStorage();

  // Login
  // Login corregido
Future<String?> login(String username, String password) async {
    try {
      // Usamos FormData que es lo que FastAPI suele procesar bien si no es estricto con el content-type
      // OJO: Añadimos 'grant_type': 'password' que era lo que faltaba en tu primer error.
      final formData = FormData.fromMap({
        'username': username,
        'password': password,
        'grant_type': 'password', // <--- ESTO ES LA CLAVE
      });

      final response = await _dio.post(
        '/token',
        data: formData,
        options: Options(
          // Esto ayuda a que Dio no lance excepción si la API devuelve 401 (no autorizado)
          validateStatus: (status) => status! < 500,
        ),
      );

      print("Código de respuesta: ${response.statusCode}");
      print("Datos de respuesta: ${response.data}");

      if (response.statusCode == 200) {
        final token = response.data['access_token'];
        await _storage.write(key: 'jwt_token', value: token);
        return null; // Login exitoso
      } else {
        // Si hay error, intentamos leer el mensaje 'detail'
        final msg = response.data['detail'];
        if (msg is List) {
            // A veces FastAPI devuelve una lista de errores
            return "Error: ${msg[0]['msg']}"; 
        }
        return "Error: $msg";
      }

    } catch (e) {
      // IMPORTANTE: Mira la consola de "Run" en Flutter para ver qué dice aquí
      print("ERROR EXCEPCIÓN: $e");
      if (e is DioException) {
        print("Mensaje Dio: ${e.message}");
        print("Respuesta Servidor: ${e.response}");
      }
      return 'Error de conexión: Revisa tu IP';
    }
  }

  // Obtener Paquetes
  Future<List<dynamic>> getPackages() async {
    String? token = await _storage.read(key: 'jwt_token');
    _dio.options.headers['Authorization'] = 'Bearer $token';
    
    try {
      final response = await _dio.get('/deliveries/assigned');
      return response.data;
    } catch (e) {
      throw Exception('Error al cargar paquetes');
    }
  }

  // Confirmar Entrega
  Future<void> confirmDelivery(int packageId, File photo, double lat, double lng) async {
    String? token = await _storage.read(key: 'jwt_token');
    _dio.options.headers['Authorization'] = 'Bearer $token';

    String fileName = photo.path.split('/').last;
    
    FormData formData = FormData.fromMap({
      "file": await MultipartFile.fromFile(photo.path, filename: fileName),
      "lat": lat,
      "lng": lng,
    });

    await _dio.post('/deliveries/$packageId/confirm', data: formData);
  }

  Future<void> logout() async {
    await _storage.delete(key: 'jwt_token');
  }
}

// --- PANTALLA 1: LOGIN ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final _api = ApiService();
  bool _isLoading = false;

  void _doLogin() async {
    setState(() => _isLoading = true);
    final error = await _api.login(_userController.text, _passController.text);
    setState(() => _isLoading = false);

    if (error == null) {
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const DeliveryListScreen()));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo Simulado
              Icon(Icons.local_shipping, size: 80, color: AppColors.primary),
              const SizedBox(height: 10),
              const Text("PAQUEXPRESS", 
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              const Text("App Agentes", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 40),
              
              // Formulario
              TextField(
                controller: _userController,
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 30),
              
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _doLogin,
                  child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text("INICIAR SESIÓN"),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// --- PANTALLA 2: LISTA DE ENTREGAS ---
class DeliveryListScreen extends StatefulWidget {
  const DeliveryListScreen({super.key});

  @override
  State<DeliveryListScreen> createState() => _DeliveryListScreenState();
}

class _DeliveryListScreenState extends State<DeliveryListScreen> {
  final _api = ApiService();
  late Future<List<dynamic>> _packagesFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _packagesFuture = _api.getPackages();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Rutas"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
               _api.logout();
               Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          )
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _packagesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.secondary));
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          final packages = snapshot.data ?? [];
          if (packages.isEmpty) {
            return const Center(child: Text("No tienes entregas pendientes hoy."));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(10),
            itemCount: packages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final pkg = packages[index];
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.secondary,
                    child: Icon(Icons.inventory_2, color: Colors.black),
                  ),
                  title: Text(pkg['tracking_number'], 
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(pkg['destination_address'], maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () async {
                    // Navegar al detalle y esperar retorno para recargar lista si se entregó
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PackageDetailScreen(package: pkg),
                      ),
                    );
                    if (result == true) _loadData();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// --- PANTALLA 3: DETALLE, MAPA Y CONFIRMACIÓN ---
class PackageDetailScreen extends StatefulWidget {
  final dynamic package;
  const PackageDetailScreen({super.key, required this.package});

  @override
  State<PackageDetailScreen> createState() => _PackageDetailScreenState();
}

class _PackageDetailScreenState extends State<PackageDetailScreen> {
  final _api = ApiService();
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  bool _isSubmitting = false;

  // Mapa
  final MapController _mapController = MapController();

  Future<void> _takePhoto() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 50);
    if (photo != null) {
      setState(() {
        _imageFile = File(photo.path);
      });
    }
  }

  Future<void> _confirmDelivery() async {
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Debes tomar una foto primero")));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // 1. Obtener ubicación actual del agente
      Position position = await _determinePosition();
      
      // 2. Enviar a backend
      await _api.confirmDelivery(
        widget.package['id'],
        _imageFile!,
        position.latitude,
        position.longitude
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("¡Entrega registrada con éxito!"), backgroundColor: Colors.green));
        Navigator.pop(context, true); // Regresar true para actualizar lista
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // Permisos y obtención de GPS
  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('El GPS está desactivado.');

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return Future.error('Permisos de ubicación denegados');
    }
    
    return await Geolocator.getCurrentPosition();
  }

  @override
  Widget build(BuildContext context) {
    // Coordenadas del destino (del paquete)
    final destLat = widget.package['dest_lat'] ?? 0.0;
    final destLng = widget.package['dest_lng'] ?? 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text("Detalle de Entrega")),
      body: Column(
        children: [
          // SECCIÓN 1: MAPA (Mitad superior)
          Expanded(
            flex: 4,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(destLat, destLng),
                initialZoom: 15.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.paquexpress.app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(destLat, destLng),
                      width: 80,
                      height: 80,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // SECCIÓN 2: INFO Y ACCIONES (Mitad inferior)
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Guía: ${widget.package['tracking_number']}", 
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.map, size: 16, color: Colors.grey),
                      const SizedBox(width: 5),
                      Expanded(child: Text(widget.package['destination_address'], style: const TextStyle(fontSize: 14))),
                    ],
                  ),
                  const Divider(height: 30),

                  // Área de Foto
                  const Text("Evidencia de Entrega", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 100,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade100,
                          ),
                          child: _imageFile == null
                              ? const Center(child: Text("Sin foto", style: TextStyle(color: Colors.grey)))
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(_imageFile!, fit: BoxFit.cover),
                                ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Column(
                        children: [
                          IconButton.filled(
                            onPressed: _takePhoto,
                            icon: const Icon(Icons.camera_alt),
                            style: IconButton.styleFrom(backgroundColor: AppColors.primary),
                          ),
                          const Text("Cámara", style: TextStyle(fontSize: 12))
                        ],
                      )
                    ],
                  ),

                  const Spacer(),

                  // Botón Final
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _confirmDelivery,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.secondary, // Naranja
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: Colors.black)
                          : const Text("CONFIRMAR ENTREGA", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}