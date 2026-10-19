import { createContext, useContext, useState, ReactNode } from 'react';

export type DashboardMode = 'admin' | 'designer';

interface DashboardModeContextType {
  mode: DashboardMode;
  setMode: (mode: DashboardMode) => void;
  toggleMode: () => void;
  isDesigner: boolean;
}

export const DashboardModeContext = createContext<DashboardModeContextType>({
  mode: 'admin',
  setMode: () => {},
  toggleMode: () => {},
  isDesigner: false,
});

export function DashboardModeProvider({ children }: { children: ReactNode }) {
  const [mode, setModeState] = useState<DashboardMode>(() => {
    try {
      const saved = localStorage.getItem('dashboard_mode');
      return saved === 'designer' ? 'designer' : 'admin';
    } catch {
      return 'admin';
    }
  });

  const setMode = (m: DashboardMode) => {
    setModeState(m);
    try {
      localStorage.setItem('dashboard_mode', m);
    } catch {}
  };

  const toggleMode = () => {
    setMode(mode === 'designer' ? 'admin' : 'designer');
  };

  return (
    <DashboardModeContext.Provider
      value={{
        mode,
        setMode,
        toggleMode,
        isDesigner: mode === 'designer',
      }}
    >
      {children}
    </DashboardModeContext.Provider>
  );
}

export function useDashboardMode() {
  return useContext(DashboardModeContext);
}
