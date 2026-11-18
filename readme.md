# Moke Bank

Aplicación móvil de banca multitenant desarrollada con Flutter. Cada cliente inicia sesión en su banco para consultar sus cuentas, revisar movimientos y realizar operaciones en el entorno de demostración de BankOS.

## Funcionalidades

- Inicio de sesión por banco y almacenamiento seguro del token en Android e iOS.
- Consulta de saldos, estado de cuentas e historial con filtros.
- Depósitos, retiros y transferencias multimoneda con desglose de comisión y tasa de cambio.
- Confirmación mediante PIN de demostración o huella en Android para retiros y transferencias.
- Reintento de operaciones con la misma clave de idempotencia.
- Panel de administración para gestionar clientes y cuentas.

## Tecnologías

Flutter, Dart, Riverpod y GoRouter. La app consume la API REST de BankOS.

## Ejecutar localmente

Necesitas Flutter, una instancia del backend BankOS y un dispositivo o emulador.

```bash
flutter pub get
flutter devices
flutter run --dart-define=BANKOS_API=https://TU_DOMINIO/api/v1
```

Para usar tu backend local desde el emulador de Android, ejecuta `flutter run --dart-define=BANKOS_API=http://10.0.2.2:3000/api/v1`.

## Pruebas

```bash
flutter analyze
flutter test
```

## Backend

El servidor y sus instrucciones de instalación están en el repositorio [bankos-backend](https://github.com/ronyrdl/bankos-backend).