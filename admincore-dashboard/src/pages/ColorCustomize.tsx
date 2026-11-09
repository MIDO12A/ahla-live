import { useEffect, useRef, useState } from 'react';
import { AppConfig } from '../types';
import { getAppConfig, updateAppConfig } from '../lib/db';
import { Save, Palette, RotateCcw } from 'lucide-react';
import { to6Hex } from '../lib/colors';

const defaultColors = {
  primaryBg: '#FFFFFF',
  textPrimary: '#16151A',
  textSecondary: '#9BA1B6',
  goldColor: '#DE880F',
  buttonColor: '#6366F1',
  buttonTextColor: '#FFFFFF',
  headerColor: '#FFFFFF',
  tabBarColor: '#FFFFFF',
};

const defaultIdColors = [
  { id: 'golden', name: 'ذهبي ملكي', colorsText: '#FFD700,#FFF8DC,#FFA500,#FFD700', animated: true, isActive: true },
  { id: 'rainbow', name: 'طيف متحرك', colorsText: '#FF0055,#FFAA00,#00FFCC,#0088FF,#FF00CC,#FF0055', animated: true, isActive: true },
  { id: 'neon', name: 'نيون سايبر', colorsText: '#00E5FF,#76FF03,#00E5FF', animated: true, isActive: true },
  { id: 'fire', name: 'لهب متوهج', colorsText: '#FF1744,#FF9100,#FFEA00,#FF1744', animated: true, isActive: true },
  { id: 'purple', name: 'بنفسجي', colorsText: '#9C27B0,#E040FB,#7C4DFF,#9C27B0', animated: true, isActive: true },
  { id: 'ice', name: 'ثلجي', colorsText: '#E1F5FE,#81D4FA,#4FC3F7,#E1F5FE', animated: true, isActive: true },
  { id: 'emerald', name: 'زمردي', colorsText: '#00E676,#A7FFEB,#00BFA5,#00E676', animated: true, isActive: true },
];

function parseHexList(text: string): string[] {
  return (text || '')
    .split(',')
    .map(s => s.trim())
    .filter(s => /^#?[0-9a-fA-F]{3,8}$/.test(s))
    .map(s => (s.startsWith('#') ? s : `#${s}`));
}

export default function ColorCustomizePage() {
  const [config, setConfig] = useState<AppConfig>({});
  const [loading, setLoading] = useState(true);
  const [idColors, setIdColors] = useState<any[]>([]);
  const idColorsLoaded = useRef(false);

  useEffect(() => {
    getAppConfig().then(data => { if (data) setConfig(data); setLoading(false); });
  }, []);

  useEffect(() => {
    if (idColorsLoaded.current) return;
    const raw = (config as any).idColors ?? (config as any).id_colors;
    if (Array.isArray(raw)) {
      setIdColors(raw.map((e: any) => ({
        id: e?.id ?? e?.key ?? '',
        name: e?.name ?? '',
        colorsText: Array.isArray(e?.colors) ? e.colors.join(',') : '',
        animated: e?.animated !== false,
        isActive: e?.isActive !== false && e?.is_active !== false,
      })));
      idColorsLoaded.current = true;
    }
  }, [config]);

  const updateIdColor = (idx: number, field: string, value: any) => {
    setIdColors(p => p.map((c, i) => (i === idx ? { ...c, [field]: value } : c)));
  };

  const handleSaveIdColors = async () => {
    const cleaned = idColors
      .filter(c => c.id && c.id.trim())
      .map(c => ({
        id: c.id.trim(),
        name: (c.name || c.id).trim(),
        colors: parseHexList(c.colorsText),
        animated: c.animated !== false,
        isActive: c.isActive !== false,
      }))
      .filter(c => c.colors.length > 0);
    const next = { ...config, idColors: cleaned } as AppConfig;
    setConfig(next);
    await updateAppConfig({ idColors: cleaned });
    alert('Special ID colors saved!');
  };

  const handleSave = async () => {
    await updateAppConfig(config);
    alert('Colors saved! App will use new theme on next load.');
  };

  const resetToDefaults = () => {
    if (confirm('Reset all colors to defaults?')) {
      setConfig(defaultColors);
    }
  };

  const updateColor = (field: string, value: string) => setConfig(p => ({ ...p, [field]: value }));

  const colorFields: { key: string; label: string; default: string }[] = [
    { key: 'primaryBg', label: 'Background', default: '#FFFFFF' },
    { key: 'textPrimary', label: 'Primary Text', default: '#16151A' },
    { key: 'textSecondary', label: 'Secondary Text', default: '#9BA1B6' },
    { key: 'goldColor', label: 'Gold / Accent', default: '#DE880F' },
    { key: 'buttonColor', label: 'Button Color', default: '#6366F1' },
    { key: 'buttonTextColor', label: 'Button Text', default: '#FFFFFF' },
    { key: 'headerColor', label: 'Header Background', default: '#FFFFFF' },
    { key: 'tabBarColor', label: 'Tab Bar Background', default: '#FFFFFF' },
  ];

  if (loading) return <div className="text-slate-500 text-xs">Loading...</div>;

  return (
    <div className="space-y-6 max-w-2xl">
      <div>
        <h2 className="text-white text-lg font-semibold">Color Customization</h2>
        <p className="text-slate-500 text-xs mt-0.5">Customize all app colors. Changes are saved to Supabase and applied on next app load.</p>
      </div>

      <div className="bg-[#141417] rounded-2xl border border-white/5 p-6 space-y-4">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {colorFields.map(({ key, label, default: def }) => (
            <div key={key}>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1.5">{label}</label>
              <div className="flex gap-2 items-center">
                <input
                  type="color"
                  value={to6Hex((config[key as keyof AppConfig] as string) || def)}
                  onChange={e => updateColor(key, e.target.value)}
                  className="w-10 h-10 rounded cursor-pointer bg-transparent border border-white/10 shrink-0"
                />
                <input
                  type="text"
                  value={config[key as keyof AppConfig] as string || def}
                  onChange={e => updateColor(key, e.target.value)}
                  className="flex-1 bg-[#161618] border border-white/10 rounded-lg py-2 px-3 text-xs text-white font-mono"
                />
                <button
                  onClick={() => updateColor(key, def)}
                  className="text-[10px] text-slate-500 hover:text-white p-1"
                  title="Reset to default"
                >
                  <RotateCcw className="w-3 h-3" />
                </button>
              </div>
              <div className="mt-1 flex items-center gap-2">
                <div className="w-full h-2 rounded" style={{ backgroundColor: config[key as keyof AppConfig] as string || def }} />
              </div>
            </div>
          ))}
        </div>

        <div className="flex gap-3 pt-2">
          <button onClick={handleSave} className="px-5 py-2 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1.5">
            <Palette className="w-3.5 h-3.5" /> Save Colors
          </button>
          <button onClick={resetToDefaults} className="px-5 py-2 border border-white/10 text-xs text-slate-400 rounded-lg hover:bg-white/5">
            Reset to Defaults
          </button>
        </div>
      </div>

      <div className="bg-[#141417] rounded-2xl border border-white/5 p-6">
        <h3 className="text-white text-sm font-semibold mb-4">Screen Titles Customization</h3>
        <p className="text-[10px] text-slate-500 mb-4">Customize the title of each screen in the app</p>
        <div className="grid grid-cols-2 gap-3">
          {[
            { key: 'home', label: 'Home' },
            { key: 'rooms', label: 'Rooms' },
            { key: 'store', label: 'Store' },
            { key: 'profile', label: 'Profile' },
            { key: 'gifts', label: 'Gifts' },
            { key: 'ranking', label: 'Ranking' },
            { key: 'unions', label: 'Unions' },
            { key: 'vip', label: 'VIP' },
            { key: 'settings', label: 'Settings' },
            { key: 'chat', label: 'Chat' },
          ].map(({ key, label }) => (
            <div key={key}>
              <label className="block text-[10px] uppercase text-slate-400 font-bold mb-1">{label}</label>
              <input
                type="text"
                value={config.screenTitles?.[key] || label}
                onChange={e => setConfig(p => ({
                  ...p,
                  screenTitles: { ...(p.screenTitles || {}), [key]: e.target.value },
                }))}
                className="w-full bg-[#161618] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
              />
            </div>
          ))}
        </div>
        <button onClick={handleSave} className="mt-4 px-4 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg">Save Titles</button>
      </div>

      {/* Special ID Colors & Effects (app_config.idColors) */}
      <div className="bg-[#141417] rounded-2xl border border-white/5 p-6">
        <h3 className="text-white text-sm font-semibold mb-1">ألوان وتأثيرات الآيديهات المميزة</h3>
        <p className="text-[10px] text-slate-500 mb-4">
          يدير قائمة التدرجات اللونية التي تُطبَّق على أسماء المستخدمين أصحاب الآيديهات المميزة في كل الشاشات.
          يُحفَظ في app_config.idColors ويقرأه التطبيق مباشرة.
        </p>

        <div className="space-y-3">
          {idColors.map((c, idx) => (
            <div key={idx} className="bg-[#161618] border border-white/10 rounded-xl p-3 space-y-2">
              <div className="flex gap-2 items-center">
                <input
                  type="text"
                  value={c.id}
                  onChange={e => updateIdColor(idx, 'id', e.target.value)}
                  placeholder="id (مثل golden)"
                  className="flex-1 bg-[#0f0f11] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono"
                />
                <input
                  type="text"
                  value={c.name}
                  onChange={e => updateIdColor(idx, 'name', e.target.value)}
                  placeholder="الاسم (مثل ذهبي ملكي)"
                  className="flex-1 bg-[#0f0f11] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white"
                />
                <label className="flex items-center gap-1 text-[10px] text-slate-400">
                  <input
                    type="checkbox"
                    checked={c.animated !== false}
                    onChange={e => updateIdColor(idx, 'animated', e.target.checked)}
                  />
                  متحرك
                </label>
                <label className="flex items-center gap-1 text-[10px] text-slate-400">
                  <input
                    type="checkbox"
                    checked={c.isActive !== false}
                    onChange={e => updateIdColor(idx, 'isActive', e.target.checked)}
                  />
                  مفعّل
                </label>
                <button
                  onClick={() => setIdColors(p => p.filter((_, i) => i !== idx))}
                  className="text-red-400 hover:text-red-300 text-xs px-2"
                >
                  ✕
                </button>
              </div>
              <div>
                <label className="block text-[10px] uppercase text-slate-500 font-bold mb-1">الألوان (hex مفصولة بفاصلة — أول وآخر لون يحددان التدرج)</label>
                <input
                  type="text"
                  value={c.colorsText}
                  onChange={e => updateIdColor(idx, 'colorsText', e.target.value)}
                  placeholder="#FFD700,#FFF8DC,#FFA500"
                  className="w-full bg-[#0f0f11] border border-white/10 rounded-lg py-1.5 px-2 text-xs text-white font-mono"
                />
                {(() => {
                  const stops = parseHexList(c.colorsText);
                  if (stops.length === 0) return null;
                  return (
                    <div className="mt-1.5 h-3 rounded" style={{ background: `linear-gradient(90deg, ${stops.join(',')})` }} />
                  );
                })()}
              </div>
            </div>
          ))}
        </div>

        <div className="flex gap-2 mt-4 flex-wrap">
          <button
            onClick={() => setIdColors(p => [...p, { id: '', name: '', colorsText: '#FFD700,#FFA500', animated: true, isActive: true }])}
            className="px-4 py-1.5 border border-white/10 text-xs text-slate-300 rounded-lg hover:bg-white/5"
          >
            + إضافة تأثير
          </button>
          <button
            onClick={() => setIdColors(defaultIdColors.map(c => ({ ...c })))}
            className="px-4 py-1.5 border border-white/10 text-xs text-slate-400 rounded-lg hover:bg-white/5"
          >
            استعادة الافتراضي
          </button>
          <button
            onClick={handleSaveIdColors}
            className="px-4 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-xs text-white font-semibold rounded-lg flex items-center gap-1.5"
          >
            <Save className="w-3.5 h-3.5" /> حفظ ألوان الآيديهات
          </button>
        </div>
      </div>
    </div>
  );
}
