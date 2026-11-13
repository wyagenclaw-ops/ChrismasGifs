export const initials = (name='') => name.trim().split(/\s+/).filter(Boolean).slice(0,2).map(x=>x[0]?.toUpperCase()).join('') || '?';
export const money = value => value == null ? 'Por definir' : new Intl.NumberFormat('es-MX',{style:'currency',currency:'MXN',maximumFractionDigits:0}).format(value);
export function getPhase(settings, now=new Date()) {
  if (!settings) return 'LOADING';
  if (settings.draw_completed) return 'DRAW_COMPLETED';
  const votingClosed = settings.force_voting_closed || now >= new Date(settings.voting_deadline);
  const wishlistClosed = settings.force_wishlist_closed || now >= new Date(settings.wishlist_deadline);
  if (!votingClosed) return 'VOTING';
  if (!wishlistClosed) return 'WISHLIST';
  return 'READY_FOR_DRAW';
}
export const phaseLabels = { VOTING:'Votación de presupuesto', WISHLIST:'Lista de deseos abierta', READY_FOR_DRAW:'Listas cerradas · Sorteo pendiente', DRAW_COMPLETED:'Sorteo realizado' };
export function countdown(target) { if (!target) return 'Fecha pendiente'; const ms=Math.max(0,new Date(target)-Date.now()); const d=Math.floor(ms/86400000),h=Math.floor(ms%86400000/3600000),m=Math.floor(ms%3600000/60000); return `${d} días · ${h} h · ${m} min`; }
