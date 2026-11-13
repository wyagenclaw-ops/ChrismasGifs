# Corrección de sesión y perfil

Se corrigió `src/App.jsx` para que los eventos `TOKEN_REFRESHED` y otros eventos de autenticación que mantienen al mismo usuario no borren `profile`. El perfil solo se reinicia cuando cambia el ID de usuario o cuando se cierra sesión.

Esto evita que la aplicación desmonte el área de participación y pierda el estado temporal del formulario cuando Supabase renueva el token al volver a una pestaña. La persistencia de borradores ante una recarga completa del navegador es una mejora separada; los formularios todavía deben guardarse antes de recargar/cerrar la página.
