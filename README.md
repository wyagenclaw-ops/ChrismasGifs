# Christmas Gif-Office · Woodynet

Aplicación mobile-first para organizar el intercambio de regalos de oficina (objetivo aproximado: 15 participantes). Frontend React + Vite, servidor Express para Render y Supabase Auth/PostgreSQL/Storage.

## Incluye

- Acceso con correo y contraseña; alta de perfil automática al registrarse.
- Estados VOTING, WISHLIST, READY_FOR_DRAW y DRAW_COMPLETED.
- Votación de presupuesto ($200, $300 o $500 MXN) y resultados en tiempo real.
- Lista de hasta 3 deseos por participante, con imagen comprimida en navegador y enlaces de producto.
- Formularios en solo lectura al cerrar las listas.
- Panel de administrador: fechas, cierres anticipados, presupuesto, avance de participantes y sorteo.
- Asignación secreta con RPC PostgreSQL, ciclo único, Fisher-Yates y sin autoasignaciones.
- PWA instalable en Android Chrome y navegación inferior táctil.

## 1. Requisitos

- Node.js 20 o superior y npm.
- Proyecto Supabase.
- Cuenta GitHub y cuenta Render.

## 2. Configurar Supabase

1. Crea un proyecto en [Supabase](https://supabase.com/).
2. Abre **SQL Editor → New query**, pega el contenido completo de `supabase/schema.sql` y ejecútalo.
3. Antes de crear las cuentas de usuarios, configura el correo administrador en SQL (reemplaza el correo):

   ```sql
   update public.app_config
   set admin_email = lower('admin@tuempresa.com')
   where id = 1;
   ```

   El primer usuario que se registre también queda como administrador automáticamente. El correo configurado se promueve a admin al registrarse. No se confía en `VITE_ADMIN_EMAIL` ni en valores enviados desde el navegador para conceder privilegios.

4. En **Authentication → Sign In / Providers → Email**, desactiva **Confirm email** para permitir acceso inmediato después del registro. Si mantienes confirmación activada, el usuario deberá completar el flujo de confirmación antes de iniciar sesión.
5. En **Project Settings → API**, copia Project URL y la clave `anon` (o publishable key). Nunca coloques `service_role` en variables `VITE_` ni en el navegador.
6. El script crea el bucket público `wishlist-images` y sus políticas de Storage. Si el proyecto no permite esa operación desde SQL, créalo desde **Storage → New bucket**, con nombre exacto `wishlist-images`, opción **Public** activada y límite de 3 MB; vuelve a ejecutar las políticas Storage del final de `schema.sql`.
7. En **Database → Replication**, habilita Realtime para `budget_votes`, `wishlist_items`, `event_settings` y `profiles` (si no están ya en `supabase_realtime`).
8. Configura las fechas iniciales del evento desde el panel Admin después de iniciar sesión.

### Seguridad y administrador

- `profiles.is_admin` solo se asigna por trigger SQL (primer registro o coincidencia con `app_config.admin_email`). Los usuarios no pueden elevar sus propios privilegios.
- `assignments` no tiene política de lectura global. Cada participante solo puede leer la fila cuyo `giver_id` coincide con su `auth.uid()`.
- Las asignaciones solo se insertan dentro de `execute_secret_santa_draw()`; no se expone INSERT directo mediante RLS.
- La RPC bloquea la configuración del evento, valida administrador y cierre, rechaza un segundo sorteo, mezcla Fisher-Yates y crea un ciclo único.
- Las operaciones del cliente están sujetas a RLS y a las ventanas de tiempo evaluadas con el reloj del servidor.

> Importante: la cuenta de administrador inicial debe registrarse primero si no configuraste `app_config.admin_email` antes del primer registro.

## 3. Ejecutar localmente

```bash
cp .env.example .env
# Edita .env con las credenciales de Supabase
npm install
npm run dev
```

Abre la URL que indique Vite (normalmente `http://localhost:5173`). Para probar el servidor de producción:

```bash
npm run build
npm start
```

## 4. Variables de entorno

Crea `.env` localmente o define estas variables en Render:

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_ANON_OR_PUBLISHABLE_KEY
VITE_ADMIN_EMAIL=admin@tuempresa.com
```

`VITE_ADMIN_EMAIL` es una referencia para la configuración inicial/documentación. La autorización efectiva se realiza en PostgreSQL usando `public.app_config.admin_email`; configura ese valor mediante el SQL indicado arriba. Las variables `VITE_` quedan visibles en el bundle público: nunca almacenes secretos en ellas.

## 5. Publicar en GitHub

1. Descomprime o copia la carpeta completa `christmas-gif-office`.
2. Inicializa Git y sube el repositorio:

   ```bash
   git init
   git add .
   git commit -m "Initial Christmas Gif-Office app"
   git branch -M main
   git remote add origin https://github.com/TU_USUARIO/christmas-gif-office.git
   git push -u origin main
   ```

3. Confirma que `.env` no se suba. El archivo `.gitignore` ya lo excluye.

## 6. Desplegar en Render

1. En Render selecciona **New → Web Service** y conecta el repositorio GitHub.
2. Configura:
   - **Runtime:** Node
   - **Build Command:** `npm install && npm run build`
   - **Start Command:** `npm start`
   - **Instance:** plan acorde al uso esperado.
3. En **Environment**, agrega `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` y `VITE_ADMIN_EMAIL`.
4. Pulsa **Create Web Service**. Render asignará `PORT`; `server.js` escucha `process.env.PORT || 3000` y sirve `dist` con fallback SPA.
5. En Supabase, revisa **Authentication → URL Configuration** y agrega la URL pública de Render a **Site URL** y a las Redirect URLs permitidas (por ejemplo `https://tu-app.onrender.com/**`). Aunque el flujo actual usa email/contraseña, esta configuración evita problemas de redirección de Auth.

## 7. Reemplazar los SVG de Woodynet

Sustituye los archivos manteniendo exactamente estos nombres y rutas:

- `public/brand/logo-horizontal-color.svg`
- `public/brand/logo-horizontal-dark.svg`
- `public/brand/isotype-color.svg`
- `public/favicon.svg`

El componente `WoodynetBrand` los consume por ruta estática; no necesitas cambiar el código. Conserva las proporciones, área de protección y colores de marca. Los PNG `icon-192.png` e `icon-512.png` del manifest deben agregarse con esos nombres antes de publicar para que la instalación PWA muestre iconos definitivos. Los placeholders vectoriales incluidos cubren favicon y logos; genera los dos PNG desde el isotipo oficial antes del lanzamiento público.

## 8. Flujo del evento

- **VOTING:** votación de presupuesto; se puede cambiar el voto hasta el cierre.
- **WISHLIST:** alta/edición/borrado de hasta 3 deseos propios.
- **READY_FOR_DRAW:** listas cerradas y solo lectura; el botón de sorteo se habilita en Admin.
- **DRAW_COMPLETED:** aparece la pestaña Mi Amigo; el usuario ve únicamente su destinatario y sus deseos (o una invitación a sorprenderlo si no publicó lista).

El estado se evalúa en el cliente para la navegación y se vuelve a validar en PostgreSQL para autorizar las escrituras y el sorteo. Para esta versión, el ciclo del sorteo incluye a todos los perfiles registrados al momento de ejecutarlo.

## 9. Comprobaciones antes de anunciar el intercambio

- [ ] Ejecutar `supabase/schema.sql` sin errores.
- [ ] Configurar el correo admin en `app_config` antes de registrar participantes.
- [ ] Desactivar Confirm email si se desea acceso inmediato.
- [ ] Probar dos cuentas normales y una admin.
- [ ] Confirmar que cada usuario solo ve su asignación.
- [ ] Probar cierre de votación/listas y modo solo lectura.
- [ ] Verificar imágenes, enlaces y Realtime.
- [ ] Ejecutar el sorteo una sola vez en una prueba controlada.
- [ ] Añadir los iconos PNG PWA de 192 y 512 px.

## Licencia

Proyecto preparado para uso interno de Woodynet. © 2026 Woodynet.
