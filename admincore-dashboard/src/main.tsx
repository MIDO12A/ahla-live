import {StrictMode} from 'react';
import {createRoot} from 'react-dom/client';
import App from './App.tsx';
import './index.css';

// Suppress browser extension message channel disconnections
if (typeof window !== 'undefined') {
  window.addEventListener('unhandledrejection', (e) => {
    const msg = e?.reason?.message || String(e?.reason || '');
    if (
      msg.includes('message channel closed before a response was received') ||
      msg.includes('A listener indicated an asynchronous response') ||
      msg.includes('The play() request was interrupted') ||
      msg.includes('AbortError')
    ) {
      e.preventDefault();
      e.stopImmediatePropagation();
    }
  });

  window.addEventListener('error', (e) => {
    const msg = e?.message || '';
    if (
      msg.includes('message channel closed before a response was received') ||
      msg.includes('A listener indicated an asynchronous response') ||
      msg.includes('The play() request was interrupted')
    ) {
      e.preventDefault();
      e.stopImmediatePropagation();
    }
  });
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
