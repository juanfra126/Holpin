# Activar notificaciones push de Holpin

La app ya guarda las suscripciones en `public.push_subscriptions`. Para recibir avisos con Holpin cerrada también hace falta desplegar la función emisora y crear un Database Webhook.

## 1. Generar un par de claves VAPID

En una terminal con Node.js ejecutá:

```bash
npx web-push generate-vapid-keys
```

Guardá las dos claves que devuelve (Public Key y Private Key). No compartas la privada.

## 2. Usar la misma clave pública en la app

En `index.html`, buscá `const VAPID_PUBLIC=` y reemplazá su valor por la nueva Public Key. Al volver a iniciar sesión y activar la campanita, Holpin detecta si la suscripción anterior usa otra clave y la vuelve a registrar.

## 3. Configurar los secretos en Supabase

Desde la carpeta del proyecto, iniciá sesión en Supabase CLI y vinculá el proyecto. Después ejecutá:

```bash
supabase secrets set VAPID_PUBLIC_KEY="TU_PUBLIC_KEY" VAPID_PRIVATE_KEY="TU_PRIVATE_KEY" VAPID_SUBJECT="mailto:TU_EMAIL_REAL" HOLPIN_WEBHOOK_SECRET="UNA_CADENA_ALEATORIA_LARGA"
supabase functions deploy holpin-push --no-verify-jwt
```

- `VAPID_PUBLIC_KEY`: exactamente la misma clave pública del paso 2.
- `VAPID_PRIVATE_KEY`: clave privada correspondiente.
- `VAPID_SUBJECT`: un mail real de contacto en formato `mailto:`.
- `HOLPIN_WEBHOOK_SECRET`: inventá una contraseña aleatoria larga; usá exactamente el mismo valor en el webhook del paso siguiente.

No pongas la clave privada en `index.html`, GitHub ni en el navegador.

## 4. Crear el webhook de mensajes

En Supabase Dashboard:

1. Abrí **Database → Webhooks → Create a new webhook**.
2. Nombre: `holpin-new-message-push`.
3. Tabla: `public.messages`.
4. Evento: solamente **INSERT**.
5. Método: **POST**.
6. URL: `https://ufymsapavinnuulnpftq.supabase.co/functions/v1/holpin-push`.
7. Agregá el header:
   - Name: `x-holpin-webhook-secret`
   - Value: el mismo `HOLPIN_WEBHOOK_SECRET` configurado en el paso 3.
8. Guardá y habilitá el webhook.

El webhook debe enviar el payload estándar de Supabase Database Webhooks, que incluye `type`, `table` y `record`.

## 5. Volver a suscribir cada dispositivo y probar

En cada celular y computadora:

1. Abrí Holpin desde el navegador o desde el acceso instalado.
2. Iniciá sesión.
3. Permití las notificaciones del sitio en los permisos del navegador/sistema.
4. Tocá la campanita de Holpin hasta que indique que los avisos están activados.
5. Enviá un mensaje de prueba desde otra cuenta.

Cada dispositivo debe registrarse por separado. En iPhone, las notificaciones web push requieren iOS/iPadOS 16.4 o posterior y que la web esté agregada a la pantalla de inicio. En Android, usá Chrome (o un navegador compatible) y permití las notificaciones del sitio.

## Diagnóstico

- En **Edge Functions → holpin-push → Logs**, buscá ejecuciones cuando se inserta un mensaje.
- Una respuesta `No subscriptions for recipient` significa que el destinatario todavía no registró ese dispositivo.
- Errores 401 indican que el header secreto no coincide.
- Errores 403/404/410 de los servicios push suelen indicar clave VAPID incorrecta o suscripción vencida. Las suscripciones vencidas se eliminan automáticamente.
