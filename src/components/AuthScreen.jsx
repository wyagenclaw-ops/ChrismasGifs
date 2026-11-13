import { useState } from 'react';
import { Eye, EyeOff, Gift, LogIn, UserPlus, ArrowLeft, KeyRound, MailCheck } from 'lucide-react';
import WoodynetBrand from './WoodynetBrand';

export default function AuthScreen({ supabase, initialMode = 'login', onPasswordUpdated }) {
  const [mode, setMode] = useState(initialMode);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [show, setShow] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');

  function changeMode(nextMode) {
    setMode(nextMode);
    setError('');
    setInfo('');
    setPassword('');
    setConfirmPassword('');
  }

  async function submit(e) {
    e.preventDefault();
    setBusy(true);
    setError('');
    setInfo('');
    try {
      if (mode === 'signup') {
        const { data, error: authError } = await supabase.auth.signUp({
          email: email.trim(),
          password,
          options: { data: { full_name: name.trim() } },
        });
        if (authError) throw authError;
        if (!data.session) setInfo('Cuenta creada. Si Supabase solicita confirmación, revisa tu correo.');
      } else if (mode === 'login') {
        const { error: authError } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
        if (authError) throw authError;
      } else if (mode === 'forgot') {
        const { error: authError } = await supabase.auth.resetPasswordForEmail(email.trim(), {
          redirectTo: window.location.origin,
        });
        if (authError) throw authError;
        setInfo('Si existe una cuenta con ese correo, recibirás un enlace para restablecer tu contraseña. Revisa también tu carpeta de spam.');
      } else if (mode === 'recovery') {
        if (password.length < 6) throw new Error('La contraseña debe tener al menos 6 caracteres.');
        if (password !== confirmPassword) throw new Error('Las contraseñas no coinciden.');
        const { error: authError } = await supabase.auth.updateUser({ password });
        if (authError) throw authError;
        setInfo('Tu contraseña se actualizó correctamente. Ya puedes continuar.');
        setPassword('');
        setConfirmPassword('');
        window.setTimeout(() => onPasswordUpdated?.(), 900);
      }
    } catch (err) {
      setError(err.message || 'No fue posible completar la solicitud.');
    } finally {
      setBusy(false);
    }
  }

  const isRecovery = mode === 'recovery';
  const isForgot = mode === 'forgot';
  const isSignup = mode === 'signup';

  return (
    <main className="auth-wrap">
      <section className="auth-card">
        <div className="auth-brand">
          <WoodynetBrand />
          <span className="brand-divider" />
          <span className="event-mark"><Gift size={18} /> Christmas Gif-Office</span>
        </div>

        <div className="auth-intro">
          <span className="eyebrow">INTERCAMBIO DE OFICINA</span>
          <h1>{isRecovery ? <>Crea una contraseña <em>nueva.</em></> : isForgot ? <>Recupera tu <em>acceso.</em></> : <>La magia está en <em>compartir.</em></>}</h1>
          <p>{isRecovery
            ? 'Escribe y confirma tu nueva contraseña para recuperar el acceso a tu cuenta.'
            : isForgot
              ? 'Indica el correo con el que te registraste. Te enviaremos un enlace para restablecer tu contraseña.'
              : 'Organiza tus deseos, participa en el presupuesto y descubre a quién sorprenderás.'}</p>
        </div>

        {!isForgot && !isRecovery && (
          <div className="auth-tabs">
            <button type="button" className={mode === 'login' ? 'selected' : ''} onClick={() => changeMode('login')}><LogIn size={16} /> Iniciar sesión</button>
            <button type="button" className={mode === 'signup' ? 'selected' : ''} onClick={() => changeMode('signup')}><UserPlus size={16} /> Crear cuenta</button>
          </div>
        )}

        <form onSubmit={submit} className="form-stack">
          {isSignup && <label>Nombre completo<input value={name} onChange={e => setName(e.target.value)} required minLength={3} placeholder="Ej. Ana García" autoComplete="name" /></label>}

          {!isRecovery && <label>Correo electrónico<input type="email" value={email} onChange={e => setEmail(e.target.value)} required placeholder="nombre@empresa.com" autoComplete="email" /></label>}

          {(mode === 'login' || isSignup || isRecovery) && <label>{isRecovery ? 'Nueva contraseña' : 'Contraseña'}<span className="password-wrap"><input type={show ? 'text' : 'password'} value={password} onChange={e => setPassword(e.target.value)} required minLength={6} placeholder={isRecovery ? 'Mínimo 6 caracteres' : 'Mínimo 6 caracteres'} autoComplete={isSignup || isRecovery ? 'new-password' : 'current-password'} /><button type="button" className="eye-btn" onClick={() => setShow(!show)} aria-label={show ? 'Ocultar contraseña' : 'Mostrar contraseña'}>{show ? <EyeOff size={18} /> : <Eye size={18} />}</button></span></label>}

          {isRecovery && <label>Confirmar nueva contraseña<span className="password-wrap"><input type={showConfirm ? 'text' : 'password'} value={confirmPassword} onChange={e => setConfirmPassword(e.target.value)} required minLength={6} placeholder="Escribe nuevamente tu contraseña" autoComplete="new-password" /><button type="button" className="eye-btn" onClick={() => setShowConfirm(!showConfirm)} aria-label={showConfirm ? 'Ocultar contraseña' : 'Mostrar contraseña'}>{showConfirm ? <EyeOff size={18} /> : <Eye size={18} />}</button></span></label>}

          {error && <p className="alert error">{error}</p>}
          {info && <p className="alert success">{info}</p>}

          <button className="btn primary full" disabled={busy || (isRecovery && Boolean(info))}>
            {busy ? 'Procesando…' : isSignup ? 'Crear mi cuenta' : isForgot ? <><MailCheck size={16} /> Enviar enlace de recuperación</> : isRecovery ? <><KeyRound size={16} /> Guardar nueva contraseña</> : 'Entrar a la experiencia'}
          </button>
        </form>

        {mode === 'login' && <button type="button" className="auth-link" onClick={() => changeMode('forgot')}>¿Olvidaste tu contraseña?</button>}
        {(isForgot || isRecovery) && <button type="button" className="auth-link back-link" onClick={() => { if (isRecovery) supabase.auth.signOut().then(() => onPasswordUpdated?.()); else changeMode('login'); }}><ArrowLeft size={15} /> Volver al inicio de sesión</button>}
        {!isForgot && !isRecovery && <p className="auth-note">Acceso privado para participantes del intercambio.</p>}
      </section>
      <footer className="auth-footer">Christmas Gif-Office — Desarrollado por Woodynet © 2026</footer>
    </main>
  );
}
