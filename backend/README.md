# BankOS Backend

API REST para instituciones financieras independientes. Incluye autenticación, administración de usuarios y cuentas, depósitos, retiros, transferencias, conversión de moneda, auditoría y webhooks. La API usa el prefijo `/api/v1`.

La aplicación móvil está en [moke_bank](moke_bank/README.md).

## Inicio rápido

Requisitos locales: Docker con Compose v2. Para trabajar fuera de Docker, Node.js 22.17 o posterior, npm, PostgreSQL y Redis.

```sh
cp .env.example .env
docker compose up --build
```

- API y healthcheck en `http://localhost:3000/api/v1/health`.
- Swagger UI en `http://localhost:3000/api/docs`.
- El contenedor `migrate` crea el rol de aplicación si falta y aplica las migraciones antes de iniciar la API y el worker. Los datos de PostgreSQL y Redis se conservan en volúmenes.
- Compose publica la API en la interfaz local. La base de datos y Redis se comunican por la red de Compose.

Para instalar datos de demostración con el entorno en ejecución:

```sh
docker compose --profile demo run --rm seed
```

| Institución | Administrador | Cliente USD | Cliente COP | Cuentas USD y COP |
| --- | --- | --- | --- | --- |
| `demo-a` | `admin@demo-a.example` | `cliente01@demo-a.example` | `cliente02@demo-a.example` | `900000101`, `900000102` |
| `demo-b` | `admin@demo-b.example` | `cliente01@demo-b.example` | `cliente02@demo-b.example` | `900000201`, `900000202` |

La contraseña de demostración es `BankOS-demo-2026!`, configurable mediante `DEMO_PASSWORD`. Las cuentas nuevas comienzan en cero.

### Desarrollo local

Con PostgreSQL y Redis accesibles, configura `APP_DB_PASSWORD` para que `npm run migrate` cree el rol `bankos_app` si falta. Usa la misma contraseña en `DATABASE_URL`. Si el rol ya existe, la migración conserva sus credenciales. La conexión de migración requiere permisos para crear tablas, funciones, políticas y, al aprovisionar un rol nuevo, roles. Las funciones internas de consulta de tenants se crean con un propietario que puede atravesar RLS y devuelven únicamente identificadores para el login y el worker.

```sh
npm install
cp .env.example .env
npm run build
npm run migrate
ALLOW_DEMO_SEED=true npm run seed
npm start
```

Ejecuta `npm run worker` en otro proceso. `npm test` compila y ejecuta las pruebas unitarias. Después de aplicar migraciones a una base de pruebas con Redis disponible, ejecuta `npm run test:e2e`. Las pruebas de integración generan tenants independientes y deben ejecutarse contra una base dedicada.

Para ejecutar toda la suite con su propio PostgreSQL y Redis en Docker:

```sh
docker compose -p bankos-test --profile test run --build --rm test
docker compose -p bankos-test --profile test down --volumes
```

| Variables | Uso |
| --- | --- |
| `DATABASE_URL`, `MIGRATION_DATABASE_URL` | Conexiones de aplicación y de migración |
| `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `APP_DB_PASSWORD` | Inicialización de PostgreSQL en Compose. Codifica caracteres reservados de una contraseña cuando la uses en una URL |
| `REDIS_URL` | Coordinación de idempotencia y límites distribuidos |
| `PLATFORM_ADMIN_USERNAME`, `PLATFORM_ADMIN_PASSWORD` | Usuario y contraseña del superadmin. Configura ambos en el servidor. La contraseña necesita al menos 12 caracteres |
| `JWT_SECRET`, `PLATFORM_ADMIN_KEY` | Secretos separados de al menos 32 caracteres. Los valores de Compose son para uso local |
| `ACCESS_TOKEN_SECONDS`, `REFRESH_TOKEN_SECONDS` | Vigencia de las sesiones |
| `COOKIE_SECURE`, `CORS_ORIGINS`, `TRUST_PROXY_HOPS` | Cookies, orígenes web permitidos y número de proxies confiables |
| `PORT`, `RATE_LIMIT_IP`, `RATE_LIMIT_AUTH`, `RATE_LIMIT_TENANT`, `RATE_LIMIT_USER`, `RATE_LIMIT_MONEY` | Puerto y límites por minuto |
| `WEBHOOK_POLL_MS`, `WEBHOOK_MAX_ATTEMPTS` | Frecuencia de trabajo y máximo de intentos de entrega |
| `ALLOW_DEMO_SEED`, `DEMO_PASSWORD` | Datos ficticios opcionales |

## Arquitectura y reglas

- Los controladores NestJS validan entradas y delegan en servicios de dominio. MikroORM administra conexiones y transacciones. Las migraciones SQL versionadas crean políticas RLS, claves foráneas compuestas y restricciones que aplican incluso si una consulta omite el filtro explícito de tenant.
- El tenant se toma del JWT firmado. Cada transacción de base de datos recibe su contexto local con `set_config(..., true)`, equivalente parametrizable a `SET LOCAL`. El rol de aplicación no puede modificar ni eliminar auditorías ni transacciones. Cada cliente solo puede leer y operar sobre sus propias cuentas. Para transferir a otro titular del mismo tenant se usa su número de cuenta.
- El login recibe `tenant_slug`, `email` y `password`. El access token puede viajar por cookie HttpOnly o por `Authorization: Bearer …`. Los refresh tokens se rotan por cookie HttpOnly y en PostgreSQL solo se conserva su hash. `auth/register` exige un administrador del tenant y crea únicamente clientes.
- El dinero se recibe y devuelve como cadenas. La API admite COP, USD y EUR con dos decimales. Usa enteros de precisión arbitraria en memoria y `NUMERIC` en PostgreSQL. La comisión de una transferencia es fija más porcentaje del importe original, en moneda de origen. Se redondea al centavo con half-up. El límite de operación es un umbral numérico en la moneda de origen, antes de la comisión. Los depósitos y retiros no cobran comisión. Las tasas son direccionales y la transferencia guarda la tasa que usó.
- El débito, el crédito, el registro financiero, el outbox y la respuesta idempotente se confirman juntos. Las cuentas se bloquean en orden por UUID. Un rechazo esperado revierte los cambios financieros y guarda un movimiento `FAILED` con su código.
- Las operaciones financieras exigen `Idempotency-Key` con un UUID por intención. Redis coordina las solicitudes simultáneas y PostgreSQL protege la operación incluso si vence el bloqueo. El reintento válido devuelve durante 24 horas exactamente el estado HTTP y el cuerpo originales. Una clave usada y vencida se rechaza con `409` para impedir repetir la operación por accidente. El encabezado `X-Correlation-ID` identifica la solicitud actual y el cuerpo reproducido conserva el identificador original.
- El worker entrega los webhooks por HTTPS a destinos públicos, con DNS verificado y dirección fijada durante la conexión. No sigue redirecciones. Firma `timestamp + "." + cuerpo` con HMAC-SHA256 y envía `X-BankOS-Signature`, `X-BankOS-Timestamp`, `X-BankOS-Event-ID` y `X-Correlation-ID`. Un receptor puede deduplicar por ID del evento. Los intentos y resultados se guardan en PostgreSQL y un fallo de entrega no revierte el movimiento.
- El registro y la reactivación de instituciones requieren `X-Platform-Key`. Una institución suspendida rechaza sus sesiones y operaciones. El administrador de plataforma puede reactivarla con `PATCH /tenants/:id/status`.

## Endpoints

Los paths de la tabla son relativos a `/api/v1`.

| Método y ruta | Acceso |
| --- | --- |
| `GET /health` | Público |
| `POST /tenants/platform-login` | Intercambia el usuario y contraseña de superadmin por un token de plataforma de 15 minutos |
| `POST /tenants`, `PATCH /tenants/:id/status` | Token de plataforma o cabecera `X-Platform-Key` para clientes existentes |
| `GET /tenants/directory` | Público. Lista paginada de nombres e identificadores de bancos activos |
| `GET /tenants/config`, `PATCH /tenants/config` | ADMIN |
| `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout` | Credenciales, cookie de renovación o Bearer para cerrar sesión |
| `POST /auth/register` | ADMIN |
| `POST /auth/self-register` | Público. Crea un cliente y una cuenta activa de saldo cero en la moneda principal del banco |
| `GET /auth/me` | Autenticado |
| `GET /users`, `POST /users`, `GET /users/:id`, `PATCH /users/:id`, `PATCH /users/:id/status` | ADMIN |
| `POST /accounts`, `PATCH /accounts/:id`, `PATCH /accounts/:id/status` | ADMIN |
| `GET /accounts`, `GET /accounts/:id`, `GET /accounts/:id/transactions` | ADMIN o titular |
| `POST /transactions/deposit`, `POST /transactions/withdraw`, `POST /transactions/transfer` | Cliente titular de la cuenta de origen o de la cuenta operada |
| `GET /transactions/quote` | Cliente titular de la cuenta de origen |
| `GET /transactions`, `GET /transactions/:id` | ADMIN o participante |
| `GET /transactions/stats`, `GET /audit` | ADMIN |
| `GET /currencies`, `GET /currencies/rates` | Autenticado |
| `PUT /currencies/rates`, `GET /webhooks/config`, `POST /webhooks/config`, `PATCH /webhooks/config` | ADMIN |

El historial usa `page`, `limit` (máximo 100), `type`, `status`, `from`, `to`, `account_id` y `sort`. Las listas informan `has_more`. Usa fechas ISO 8601 con zona horaria.

El inicio de sesión aplica un límite por IP y otro por cuenta dentro de cada tenant. El límite por cuenta se configura con `RATE_LIMIT_LOGIN_ACCOUNT` y admite 10 solicitudes por minuto por defecto.

## Integración con Flutter

### Sesión

1. En el login, toma `data.access_token` para enviar `Authorization: Bearer …`. Conserva la cookie HttpOnly `bankos_refresh` recibida en `Set-Cookie` en un almacén respaldado por Keychain o Keystore si necesitas mantener la sesión entre reinicios.
2. Al renovar, envía `bankos_refresh` en `Cookie` a `POST /auth/refresh`. Guarda la nueva cookie y reemplaza el access token. Ejecuta una sola renovación a la vez para que las solicitudes concurrentes compartan la sesión renovada.
3. Para cerrar sesión, envía la cookie vigente o el access token vigente a `POST /auth/logout`. Un `200` confirma la revocación de la sesión y un `401` indica que la credencial presentada ya no identifica una sesión activa. Espera a que termine cualquier renovación en curso antes de cerrar sesión y elimina los tokens locales al salir.

Para Flutter Web, activa el envío de credenciales y configura el origen completo de la app en `CORS_ORIGINS`. Las cookies usan `SameSite=Strict`, así que sirve la app y la API desde el mismo sitio para utilizar esas cookies. Usa HTTPS con cookies seguras fuera del desarrollo local.

### Transferencia

1. Consulta `GET /transactions/quote` con `source_account_id`, `destination_account_number` y `amount`. Muestra `original_amount`, `fee`, `exchange_rate`, `total_debit`, `converted_amount` y sus monedas usando las cadenas que devuelve el backend. La cotización valida el límite, las cuentas y el saldo disponible.
2. Cuando el usuario confirme, envía los mismos datos a `POST /transactions/transfer` junto con `expected_quote` igual al objeto `data` de la cotización. El backend vuelve a calcular antes de debitar. Si el desglose o el límite cambiaron, responde `409 QUOTE_CHANGED`. Pide una cotización nueva y vuelve a solicitar confirmación.
3. Genera un UUID en `Idempotency-Key` al confirmar. Si se corta la conexión o recibes `409 OPERATION_PROCESSING`, repite con la misma clave y el mismo cuerpo. Si se confirmó un fallo y el usuario quiere iniciar otro intento después de corregirlo, genera una clave nueva. Una respuesta `429` indica en `Retry-After` cuántos segundos esperar para reintentar.

Los movimientos nuevos y las consultas devuelven fechas RFC3339 en UTC. Si reintentas una operación con una clave anterior al cambio de formato, la API conserva la respuesta original.

## Escenarios de demostración

Con el seed ejecutado, obtén un token de cliente y consulta su cuenta USD:

```sh
BASE=http://localhost:3000/api/v1
TOKEN=$(curl -fsS "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d '{"tenant_slug":"demo-a","email":"cliente01@demo-a.example","password":"BankOS-demo-2026!"}' |
  jq -r '.data.access_token')
USD_ID=$(curl -fsS "$BASE/accounts" -H "Authorization: Bearer $TOKEN" |
  jq -r '.data.items[] | select(.currency=="USD") | .id')
```

**Aislamiento.** Inicia sesión en `demo-b` para obtener su UUID de cuenta. Consulta ese UUID con el token de `demo-a`. La API devuelve `404`. Repite la consulta con el token titular de `demo-b` para verificar el acceso.

**Depósito e idempotencia.** Ejecuta el depósito con una clave nueva:

```sh
curl -fsS "$BASE/transactions/deposit" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $(uuidgen)" \
  -d "{\"account_id\":\"$USD_ID\",\"amount\":\"100.00\"}"
```

**Multimoneda.** Ejecuta este comando dos veces conservando la variable `TRANSFER_KEY`. La segunda respuesta reproduce la primera y el saldo solo se debita una vez.

```sh
TRANSFER_KEY=$(uuidgen)
curl -fsS "$BASE/transactions/transfer" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $TRANSFER_KEY" \
  -d "{\"source_account_id\":\"$USD_ID\",\"destination_account_number\":\"900000102\",\"amount\":\"25.00\"}"
```

En una base recién sembrada, el débito total es USD 26.38, incluida una comisión de USD 1.38. Con tasa 4.000 COP/USD, el destino recibe COP 100.000,00 y el origen queda en USD 73.62.
