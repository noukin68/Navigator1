import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../voice_assistant/voice_responces.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late SpeechToText _speechToText;
  late FlutterTts _flutterTts;
  bool _isListening = false;
  String _assistantResponse = "";
  late AnimationController _animationController;
  late Animation<Color?> _colorAnimation;
  YandexMapController? yandexMapController;
  Point? userLocation;
  PlacemarkMapObject? userPlacemark;
  PlacemarkMapObject? startIconPlacemark; // New: Icon for start location
  PlacemarkMapObject? endIconPlacemark; // New: Icon for end location
  List<MapObject> mapObjects = [];

  @override
  void initState() {
    super.initState();
    _speechToText = SpeechToText();
    _flutterTts = FlutterTts();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _colorAnimation = ColorTween(
      begin: const Color.fromRGBO(66, 56, 46, 1),
      end: Colors.red,
    ).animate(_animationController);
    _requestMicrophonePermission();
    Geolocator.requestPermission();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _requestMicrophonePermission() async {
    PermissionStatus status = await Permission.microphone.request();
    if (status.isGranted) {
      print("Разрешение на использование микрофона получено!");
    } else {
      print("Разрешение на использование микрофона не получено!");
    }
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speechToText.initialize(
        onError: (error) {},
      );

      if (available) {
        setState(() {
          _isListening = true;
          _assistantResponse = "Говорите...";
        });

        _startListening();
      }
    }
  }

  void _startListening() {
    _speechToText.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      localeId: "ru_RU",
    );
  }

  Future<void> _stopListening() async {
    if (_isListening) {
      await Future.delayed(const Duration(seconds: 1));
      _speechToText.stop();
      setState(() {
        _isListening = false;
      });
      _speak(_assistantResponse);
    }
  }

  void _speak(String text) async {
    await _flutterTts.setVoice({
      "name": "ru-ru-x-rud-network",
      "locale": "ru-RU",
      "gender": "male",
    });
    await _flutterTts.speak(text);
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    String command = result.recognizedWords;
    setState(() {
      _assistantResponse = VoiceResponses.getResponseForCommand(command);
    });

    if (command.toLowerCase().contains("где я могу поесть")) {
      _showRestaurantOnMap();
    }

    if (command.toLowerCase().contains("построй маршрут")) {
      _routeFromCurrentLocation();
    }
  }

  Future<void> _showRestaurantOnMap() async {
    const latitude = 53.967838;
    const longitude = 38.323929;

    // Отправляем запрос на сервер Node.js для получения точки по заданным координатам
    final response = await http.get(
      Uri.parse(
          'http://62.217.182.138:3000/getPointPes?latitude=$latitude&longitude=$longitude'),
    );

    if (response.statusCode == 200) {
      // Если точка найдена, продолжаем отображение точки на карте
      final Map<String, dynamic> responseData = jsonDecode(response.body);
      // ignore: unused_local_variable
      final String id = responseData['id'] ??
          'Ресторан не найден'; // Используем значение по умолчанию

      // Создаем маркер для ресторана
      var restaurantPlacemark = PlacemarkMapObject(
        mapId: const MapObjectId('restaurant_placemark'),
        point: const Point(latitude: latitude, longitude: longitude),
        opacity: 0.8,
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromAssetImage(
              'assets/images/location.png',
            ),
          ),
        ),
      );

      // Добавляем маркер на карту
      mapObjects.add(restaurantPlacemark);

      // Перемещаем камеру к указанной точке (ресторану)
      await yandexMapController?.moveCamera(
        CameraUpdate.newCameraPosition(
          const CameraPosition(
            target: Point(
              latitude: latitude,
              longitude: longitude,
            ),
            zoom: 15.0,
          ),
        ), // Можете настроить зум по своему усмотрению
      );
    } else if (response.statusCode == 404) {
      // Если точка не найдена, обрабатываем ошибку
      // ignore: avoid_print
      print('Restaurant point not found.');
    } else {
      // Обработка ошибок при запросе данных с сервера
      // ignore: avoid_print
      print('Error fetching restaurant point: ${response.body}');
    }
  }

  void _routeFromCurrentLocation() async {
    Position position = await Geolocator.getCurrentPosition();

    yandexMapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: Point(
            latitude: position.latitude,
            longitude: position.longitude,
          ),
          zoom: 14.0,
        ),
      ),
    );

    var sessionResult = await YandexDriving.requestRoutes(
      points: [
        RequestPoint(
          point: Point(
            latitude: position.latitude,
            longitude: position.longitude,
          ),
          requestPointType: RequestPointType.wayPoint,
        ),
        const RequestPoint(
          point: Point(latitude: 53.967838, longitude: 38.323929),
          requestPointType: RequestPointType.wayPoint,
        ),
      ],
      drivingOptions: const DrivingOptions(
        initialAzimuth: 0,
        routesCount: 1,
        avoidTolls: true,
      ),
    );

    DrivingSessionResult result = await sessionResult.result;

    // Clear previous route and icons
    setState(() {
      mapObjects.clear();
    });

    // Add start and end icons to the map
    setState(() {
      userPlacemark = PlacemarkMapObject(
        mapId: const MapObjectId('user_placemark'),
        point: Point(
          latitude: position.latitude,
          longitude: position.longitude,
        ),
        opacity: 0.8,
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromAssetImage(
              'assets/images/location.png',
            ),
          ),
        ),
      );

      mapObjects.add(userPlacemark!);

      startIconPlacemark = PlacemarkMapObject(
        mapId: const MapObjectId('start_icon_placemark'),
        point: Point(
          latitude: position.latitude,
          longitude: position.longitude,
        ),
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromAssetImage(
              'assets/images/route_start.png',
            ),
            scale: 0.3,
          ),
        ),
      );
      endIconPlacemark = PlacemarkMapObject(
        mapId: const MapObjectId('end_icon_placemark'),
        point: const Point(latitude: 53.967838, longitude: 38.323929),
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromAssetImage(
              'assets/images/route_end.png',
            ),
            scale: 0.3,
          ),
        ),
      );

      mapObjects.add(startIconPlacemark!);
      mapObjects.add(endIconPlacemark!);
    });

    // Draw the route on the map
    setState(() {
      result.routes!.asMap().forEach((i, route) {
        mapObjects.add(
          PolylineMapObject(
            mapId: MapObjectId('route_${i}_polyline'),
            polyline: Polyline(points: route.geometry),
            strokeColor:
                Colors.primaries[Random().nextInt(Colors.primaries.length)],
            strokeWidth: 3,
          ),
        );
      });
    });
  }

  void _handleMapTap(double latitude, double longitude) {
    // Compare the tap coordinates with the restaurant's coordinates
    const restaurantLatitude = 53.967838;
    const restaurantLongitude = 38.323929;
    final double distanceThreshold = 0.001; // Adjust the threshold as needed

    if ((latitude - restaurantLatitude).abs() < distanceThreshold &&
        (longitude - restaurantLongitude).abs() < distanceThreshold) {
      // If the tap is within the threshold of the restaurant's location,
      // display the restaurant information.
      _showRestaurantInfo();
      _speakRestaurantInfo();
    }
  }

  void _speakRestaurantInfo() {
    // Replace the static strings with the actual restaurant information
    String restaurantDescription =
        'Три Пескаря - это разнообразное меню от фастфуда до традиционной кухни';

    // Combine the information to be spoken by the assistant
    String infoToSpeak = restaurantDescription;

    // Let the assistant speak the information
    _speak(infoToSpeak);
  }

  void _showRestaurantInfo() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          height: 250, // Adjust the height as needed
          decoration: const BoxDecoration(
            color: Color.fromRGBO(159, 182, 156, 1),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Align(
                  alignment: Alignment.center,
                  child: Text(
                    'Три Пескаря', // Replace with the actual restaurant name
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color.fromRGBO(66, 56, 46, 1),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/images/threepes.jpg', // Replace with the actual image path
                    height: 180, // Adjust the image height as needed
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromRGBO(226, 192, 128, 1),
        title: const Text(
          'Карта',
          style: TextStyle(
            color: Color.fromRGBO(66, 56, 46, 1),
          ),
        ),
        iconTheme: const IconThemeData(
          color: Color.fromRGBO(66, 56, 46, 1),
        ),
      ),
      body: Stack(
        children: [
          YandexMap(
            onMapCreated: (controller) {
              yandexMapController = controller;
              yandexMapController?.moveCamera(
                CameraUpdate.newCameraPosition(
                  const CameraPosition(
                    target: Point(
                      latitude: 53.97,
                      longitude: 38.33,
                    ),
                    zoom: 14.0,
                  ),
                ),
              );
            },
            mapObjects: mapObjects,
            onMapTap: (point) {
              // Handle map tap event here
              _handleMapTap(point.latitude, point.longitude);
            },
          ),
          Positioned(
            left: 16.0,
            bottom: 40.0,
            child: Container(
              width: 56.0,
              height: 56.0,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color.fromRGBO(226, 192, 128, 1),
              ),
              child: ElevatedButton(
                onPressed: () async {
                  Position position = await Geolocator.getCurrentPosition();
                  setState(() {
                    userPlacemark = PlacemarkMapObject(
                      mapId: const MapObjectId('user_placemark'),
                      point: Point(
                        latitude: position.latitude,
                        longitude: position.longitude,
                      ),
                      opacity: 0.8,
                      icon: PlacemarkIcon.single(
                        PlacemarkIconStyle(
                          image: BitmapDescriptor.fromAssetImage(
                            'assets/images/location.png',
                          ),
                        ),
                      ),
                    );
                  });

                  yandexMapController?.moveCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: Point(
                          latitude: position.latitude,
                          longitude: position.longitude,
                        ),
                        zoom: 14.0,
                      ),
                    ),
                  );
                  mapObjects.add(userPlacemark!);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromRGBO(226, 192, 128, 1),
                  foregroundColor: const Color.fromRGBO(66, 56, 46, 1),
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(16.0),
                  elevation: 0,
                ),
                child: const Icon(Icons.location_pin),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        color: const Color.fromRGBO(226, 192, 128, 1),
        shape: const CircularNotchedRectangle(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: _routeFromCurrentLocation,
              icon: const Icon(Icons.route),
              color: const Color.fromRGBO(66, 56, 46, 1),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.search),
              color: const Color.fromRGBO(66, 56, 46, 1),
            ),
          ],
        ),
      ),
      floatingActionButton: GestureDetector(
        onTapDown: (details) {
          if (!_isListening) {
            _animationController.forward();
            _listen();
          }
        },
        onTapUp: (details) {
          if (_isListening) {
            _animationController.reverse();
            _stopListening();
          }
        },
        onTapCancel: () {
          if (_isListening) {
            _animationController.reverse();
            _stopListening();
          }
        },
        child: AnimatedBuilder(
          animation: _colorAnimation,
          builder: (context, child) {
            return FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.mic_rounded),
              backgroundColor: _colorAnimation.value,
            );
          },
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
