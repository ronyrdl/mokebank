import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moke_bank/themes/app_colors.dart';

class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondo,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/favicon.png', width: 86),
                const SizedBox(height: 24),
                const Text(
                  'Tu banco,\nsiempre contigo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textoPrincipal,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Consulta tus cuentas y realiza tus operaciones '
                  'de forma simple y segura',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textoSecundario50, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),

      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Image.asset('assets/logo.png', width: 125),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: naranja,
                    foregroundColor: colorTextoBoton,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => context.go('/login'),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Comenzar'),
                      SizedBox(width: 8),
                      Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
              if (kIsWeb)
                TextButton(
                  onPressed: () => context.push('/operador'),
                  child: const Text('Portal de operador'),
                ),
              const SizedBox(height: 12),
              const Text(
                'Moke protege tus operaciones.',
                style: TextStyle(color: textoSecundario50, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
