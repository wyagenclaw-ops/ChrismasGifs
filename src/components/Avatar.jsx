import { initials } from '../lib/helpers';
export default function Avatar({name,size='md'}) { return <span className={`avatar avatar-${size}`} aria-label={name}>{initials(name)}</span>; }
