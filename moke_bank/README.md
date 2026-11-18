# Moke Bank

Aplicación Flutter para clientes y administradores de BankOS, con administración de plataforma en móvil y web.

## Ejecutar

```sh
flutter pub get
flutter run
flutter run -d web-server --web-port 8080
```

La app usa la API de BankOS en AWS. Para cambiarla, usa `--dart-define=BANKOS_API=https://tu-api/api/v1`. Para ejecutar en web, registra el origen exacto del frontend en `CORS_ORIGINS` del backend. El acceso de plataforma usa `PLATFORM_ADMIN_USERNAME` y `PLATFORM_ADMIN_PASSWORD` configurados en el servidor. La app conserva el token de plataforma en memoria mientras el portal está abierto.

## Probar

1. En **Administración de plataforma**, ingresa como superadmin con tu usuario y contraseña y crea un banco con su administrador inicial. En el comprobante, pulsa **Copiar credenciales del administrador** para compartirlas por un canal privado.
2. En **Comenzar**, selecciona ese banco e inicia sesión con las credenciales del administrador. Desde el panel puedes seguir gestionando clientes y cuentas.
3. Para registrarte como cliente, abre **Registrarme en un banco**, selecciona un banco activo y llena el formulario. Se abre una cuenta de saldo cero en la moneda principal del banco. Inicia sesión con tu correo y contraseña.
4. Como cliente, revisa las cuentas, consulta los movimientos y prueba las operaciones solo con datos de demostración. El PIN local de la demo es `2580`. Sirve para mostrar el flujo del reto y no constituye una autorización en el servidor.
5. Si se interrumpe una operación, usa **Reintentar** en esa misma pantalla. Se conserva el cuerpo y se reutiliza la clave de idempotencia mientras la pantalla permanezca abierta.

En Android e iOS, la app restaura el token de sesión desde almacenamiento seguro hasta su vencimiento. En web y escritorio la sesión vive en memoria. Inicio consulta saldos y movimientos cada 10 segundos mientras está visible, y actualiza al completar una operación. El catálogo de registro se carga desde la API. La pantalla de ingreso también admite bancos configurados mediante `BANKOS_BANKS` y el ingreso manual del identificador.
