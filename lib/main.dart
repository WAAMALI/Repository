import 'package:flutter/material.dart';
import 'app/tvexp_app.dart';
import 'core/services/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance.initialize();
  runApp(const TvexpApp());
}
