import { Link, useLocation } from 'react-router-dom';
import { Gift, Tag, Sparkles, SlidersHorizontal } from 'lucide-react';

const tabs = [
  { to: '/gifts', label: 'إدارة الهدايا', icon: Gift },
  { to: '/gift-categories', label: 'تصنيفات الهدايا', icon: Tag },
  { to: '/lucky-gifts', label: 'هدايا الحظ', icon: Sparkles },
  { to: '/gift-banner-configs', label: 'بانرات الهدايا', icon: SlidersHorizontal },
];

export default function GiftNavTabs() {
  const location = useLocation();

  return (
    <div className="flex flex-wrap items-center gap-2 border-b border-white/10 pb-3 mb-5">
      {tabs.map(tab => {
        const isActive = location.pathname === tab.to;
        const Icon = tab.icon;
        return (
          <Link
            key={tab.to}
            to={tab.to}
            className={`px-3.5 py-2 rounded-xl text-xs font-bold transition-all flex items-center gap-2 ${
              isActive
                ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-600/30'
                : 'bg-white/5 text-slate-400 hover:text-white hover:bg-white/10'
            }`}
          >
            <Icon className="w-4 h-4" />
            <span>{tab.label}</span>
          </Link>
        );
      })}
    </div>
  );
}
