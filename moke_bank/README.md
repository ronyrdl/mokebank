# Moke Bank

Aplicación Flutter para clientes y administradores de BankOS, con portal de operador en web.

## Ejecutar

```sh
flutter pub get
flutter run
flutter run -d web-server --web-port 8080
```

La app usa la API de BankOS en AWS. Para cambiarla, usa `--dart-define=BANKOS_API=https://tu-api/api/v1`. Para ejecutar en web, registra el origen exacto del frontend en `CORS_ORIGINS` del backend. El portal de operador está en `/#/operador` y solicita la clave de plataforma al crear un banco. La clave no se incluye en la compilación.

## Probar

1. Abre **Comenzar**, elige un banco e inicia sesión con el usuario sembrado en ese banco. Para un banco nuevo, elige **Otro banco** e ingresa su identificador. Puedes configurar los bancos visibles con `--dart-define="BANKOS_BANKS=demo-a=Banco Demo A,demo-b=Banco Demo B"`.
2. Como administrador, crea un cliente, abre una cuenta para él y verifica que aparezca en **Cuentas**.
3. Como cliente, revisa las cuentas, consulta los movimientos y prueba las operaciones solo con datos de demostración. El PIN local de la demo es `2580`. Sirve para mostrar el flujo del reto y no constituye una autorización en el servidor.
4. Si se interrumpe una operación, usa **Reintentar** en esa misma pantalla. Se conserva el cuerpo y se reutiliza la clave de idempotencia mientras la pantalla permanezca abierta.

En Android e iOS, la app restaura el token de sesión desde almacenamiento seguro hasta su vencimiento. En web y escritorio la sesión vive en memoria. Inicio consulta saldos y movimientos cada 10 segundos mientras está visible, y actualiza al completar una operación. El selector usa un catálogo configurable porque la API actual no ofrece una lista pública de bancos.
