import {StrictMode} from 'react';
import {createRoot} from 'react-dom/client';
import App from './App.tsx';
// Il grosso dello stile lo inietta Chakra a runtime con emotion, CSSReset
// incluso: qui restano solo le poche regole che il preflight di Tailwind
// copriva e Chakra no.
import './index.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
