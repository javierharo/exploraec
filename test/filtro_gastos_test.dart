import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:exploraec/controllers/auth_controller.dart';
import 'package:exploraec/controllers/gastos_controller.dart';
import 'package:exploraec/screens/gastos_screen.dart';
import 'package:exploraec/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Servidor falso mínimo: login y una lista fija de gastos de dos categorías.
class _Servidor implements HttpClientAdapter {
  final gastos = <Map<String, dynamic>>[
    {'id': 1, 'descripcion': 'Almuerzo', 'monto': 8.5, 'categoria': 'comida', 'fecha': '2026-11-01'},
    {'id': 2, 'descripcion': 'Taxi', 'monto': 4, 'categoria': 'transporte', 'fecha': '2026-11-01'},
    {'id': 3, 'descripcion': 'Cena', 'monto': 12, 'categoria': 'comida', 'fecha': '2026-11-02'},
  ];

  ResponseBody _json(Object cuerpo, int codigo) => ResponseBody.fromString(jsonEncode(cuerpo), codigo,
      headers: {Headers.contentTypeHeader: ['application/json']});

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? cuerpo, Future<void>? cancelar) async {
    switch (o.path) {
      case '/usuarios/token':
        return _json({'access_token': 'tok-a@b.com', 'token_type': 'bearer'}, 200);
      case '/usuarios/me':
        return _json({'id': 1, 'email': 'a@b.com'}, 200);
      case '/gastos/categorias':
        return _json({'categorias': ['comida', 'transporte', 'entretenimiento', 'otros'], 'limite_por_categoria': 500.0}, 200);
      case '/gastos/':
        return _json(gastos, 200);
    }
    return _json({'detail': 'ruta no prevista en la prueba: ${o.path}'}, 404);
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _esperar(bool Function() condicion) async {
  for (var i = 0; i < 200 && !condicion(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUpAll(() => Hive.init(Directory.systemTemp.createTempSync('hive_filtro').path));

  /// Monta la pantalla Gastos con sesión iniciada y los gastos ya cargados.
  /// Por qué `runAsync`: Hive hace E/S real, que no avanza con el reloj falso
  /// de `testWidgets`.
  Future<void> montarPantalla(WidgetTester tester) async {
    await tester.runAsync(() async {
      Get.reset();
      Get.testMode = true;
      await Hive.deleteFromDisk();
      FlutterSecureStorage.setMockInitialValues({});
      Get.put(ApiClient(dio: Dio(BaseOptions(baseUrl: 'http://prueba'))..httpClientAdapter = _Servidor()));
      final auth = Get.put(AuthController());
      await _esperar(() => !auth.restaurando.value);
      await auth.iniciarSesion('a@b.com', 'clave-1234');
      final gastos = Get.put(GastosController());
      await _esperar(() => gastos.gastos.isNotEmpty && gastos.estado.value.name == 'exito');
    });
    await tester.pumpWidget(const GetMaterialApp(home: GastosScreen()));
    await tester.pump();
  }

  testWidgets('Al elegir «comida» solo se ven los gastos de comida', (tester) async {
    await montarPantalla(tester);
    expect(find.text('Taxi'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'comida'));
    await tester.pump();

    expect(find.text('Almuerzo'), findsOneWidget);
    expect(find.text('Cena'), findsOneWidget);
    expect(find.text('Taxi'), findsNothing);
  });

  testWidgets('«Todas» vuelve a mostrar todos los gastos', (tester) async {
    await montarPantalla(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'comida'));
    await tester.pump();
    expect(find.text('Taxi'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Todas'));
    await tester.pump();

    expect(find.text('Almuerzo'), findsOneWidget);
    expect(find.text('Cena'), findsOneWidget);
    expect(find.text('Taxi'), findsOneWidget);
  });
}
