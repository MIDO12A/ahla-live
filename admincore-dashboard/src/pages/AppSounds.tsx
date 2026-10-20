import React, { useEffect, useState, useRef } from 'react';
import { AppAssetRecord, AppAssetType } from '../types';
import { getAppAssets, upsertAppAsset, deleteAppAsset, updateAppAsset } from '../lib/db';
import { uploadSound } from '../lib/storage';
import {
  Volume2, VolumeX, Play, Pause, Upload, Trash2, Edit3, Copy, Check,
  Search, RefreshCw, Music, Sparkles, Bell, DoorOpen, Radio, Gamepad2,
  FolderPlus, Filter, Sliders, ExternalLink, HardDrive, Info
} from 'lucide-react';

const AUDIO_CATEGORIES = [
  { id: 'all', label: 'الكل', labelEn: 'All', icon: Sparkles, color: 'text-indigo-400 bg-indigo-500/10 border-indigo-500/20' },
  { id: 'gift_sound', label: '🎁 هدايا ومؤثرات', labelEn: 'Gifts & Effects', icon: Sparkles, color: 'text-amber-400 bg-amber-500/10 border-amber-500/20' },
  { id: 'room_sound', label: '🎙️ الغرف والميكروفون', labelEn: 'Room & Mic', icon: Radio, color: 'text-emerald-400 bg-emerald-500/10 border-emerald-500/20' },
  { id: 'bgm', label: '🎵 موسيقى وخلفيات (BGM)', labelEn: 'BGM & Music', icon: Music, color: 'text-purple-400 bg-purple-500/10 border-purple-500/20' },
  { id: 'games', label: '🎲 ألعاب وتفاعل', labelEn: 'Games & Interactive', icon: Gamepad2, color: 'text-rose-400 bg-rose-500/10 border-rose-500/20' },
  { id: 'notifications', label: '🔔 تنبيهات وإشعارات', labelEn: 'Notifications', icon: Bell, color: 'text-yellow-400 bg-yellow-500/10 border-yellow-500/20' },
  { id: 'entrance', label: '🚪 دخوليات ومؤثرات VIP', labelEn: 'VIP Entrances', icon: DoorOpen, color: 'text-cyan-400 bg-cyan-500/10 border-cyan-500/20' },
  { id: 'custom', label: '✨ أصوات أخرى ومخصصة', labelEn: 'Custom & Other', icon: FolderPlus, color: 'text-slate-400 bg-slate-500/10 border-slate-500/20' },
];

export default function AppSounds() {
  const [sounds, setSounds] = useState<AppAssetRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('all');

  // Modal states
  const [isUploadOpen, setIsUploadOpen] = useState(false);
  const [isEditOpen, setIsEditOpen] = useState(false);
  const [editingSound, setEditingSound] = useState<AppAssetRecord | null>(null);

  // Upload form state
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [soundName, setSoundName] = useState('');
  const [soundKey, setSoundKey] = useState('');
  const [soundCategory, setSoundCategory] = useState('gift_sound');
  const [soundSubcategory, setSoundSubcategory] = useState('');
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);

  // Audio Playback state
  const [activePlayingId, setActivePlayingId] = useState<string | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(0.9);
  const [isMuted, setIsMuted] = useState(false);
  const [isLooping, setIsLooping] = useState(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  // Toast / Copy state
  const [copiedKey, setCopiedKey] = useState<string | null>(null);

  const loadSounds = async () => {
    try {
      setLoading(true);
      const res = await getAppAssets({ limit: 2000 });
      // Filter out assets that are audio or in sound categories
      const soundList = (res.data || []).filter(a => {
        const isAudioType = ['mp3', 'wav', 'ogg', 'm4a', 'aac', 'audio'].includes(a.type?.toLowerCase() || '') ||
          (a.remoteUrl && /\.(mp3|wav|ogg|m4a|aac)(\?.*)?$/i.test(a.remoteUrl)) ||
          AUDIO_CATEGORIES.some(c => c.id !== 'all' && c.id === a.category) ||
          a.category === 'sound' ||
          a.category === 'sounds' ||
          a.key?.startsWith('sound_') ||
          a.key?.includes('_sound');
        return isAudioType;
      });
      setSounds(soundList);
    } catch (err) {
      console.error('Error loading sounds:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadSounds();
  }, []);

  // Audio lifecycle handler
  const handleTogglePlay = (sound: AppAssetRecord) => {
    if (!sound.remoteUrl) return;

    if (activePlayingId === sound.id) {
      if (audioRef.current) {
        if (isPlaying) {
          audioRef.current.pause();
          setIsPlaying(false);
        } else {
          audioRef.current.play().catch(() => {});
          setIsPlaying(true);
        }
      }
    } else {
      if (audioRef.current) {
        audioRef.current.pause();
      }
      const audio = new Audio(sound.remoteUrl);
      audio.volume = isMuted ? 0 : volume;
      audio.loop = isLooping;

      audio.ontimeupdate = () => {
        setCurrentTime(audio.currentTime);
      };
      audio.onloadedmetadata = () => {
        setDuration(audio.duration || 0);
      };
      audio.onended = () => {
        if (!isLooping) {
          setIsPlaying(false);
          setCurrentTime(0);
        }
      };
      audio.onerror = () => {
        setIsPlaying(false);
        alert('تعذر تشغيل الملف الصوتي');
      };

      audioRef.current = audio;
      setActivePlayingId(sound.id);
      audio.play().then(() => {
        setIsPlaying(true);
      }).catch(() => {
        setIsPlaying(false);
      });
    }
  };

  const handleSeek = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = parseFloat(e.target.value);
    if (audioRef.current) {
      audioRef.current.currentTime = val;
      setCurrentTime(val);
    }
  };

  const handleVolumeChange = (newVol: number) => {
    setVolume(newVol);
    if (audioRef.current) {
      audioRef.current.volume = isMuted ? 0 : newVol;
    }
  };

  const handleToggleMute = () => {
    const nextMuted = !isMuted;
    setIsMuted(nextMuted);
    if (audioRef.current) {
      audioRef.current.volume = nextMuted ? 0 : volume;
    }
  };

  const handleToggleLoop = () => {
    const nextLoop = !isLooping;
    setIsLooping(nextLoop);
    if (audioRef.current) {
      audioRef.current.loop = nextLoop;
    }
  };

  const formatTime = (secs: number) => {
    if (isNaN(secs) || secs < 0) return '0:00';
    const m = Math.floor(secs / 60);
    const s = Math.floor(secs % 60);
    return `${m}:${s.toString().padStart(2, '0')}`;
  };

  const formatFileSize = (bytes: number) => {
    if (!bytes || bytes <= 0) return '—';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
  };

  const handleCopy = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedKey(id);
    setTimeout(() => setCopiedKey(null), 2000);
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setSelectedFile(file);

    // Auto set name from file name without extension
    const cleanName = file.name.replace(/\.[^/.]+$/, "");
    if (!soundName) {
      setSoundName(cleanName);
    }
    if (!soundKey) {
      const generatedKey = `sound_${cleanName.toLowerCase().replace(/[^a-z0-9_]/g, '_')}_${Date.now().toString().slice(-4)}`;
      setSoundKey(generatedKey);
    }
  };

  const handleSaveUpload = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedFile) {
      alert('يرجى اختيار ملف صوتي');
      return;
    }
    if (!soundKey.trim()) {
      alert('يرجى إدخال مفتاح تعريف الصوت (Key)');
      return;
    }

    try {
      setUploading(true);
      setUploadProgress(10);

      const url = await uploadSound(selectedFile, soundKey, (pct) => {
        setUploadProgress(Math.max(10, pct));
      });

      const ext = selectedFile.name.split('.').pop()?.toLowerCase() || 'mp3';
      const soundType: AppAssetType = (['mp3', 'wav', 'ogg', 'm4a', 'aac'].includes(ext) ? ext : 'mp3') as AppAssetType;

      const record: AppAssetRecord = {
        id: crypto.randomUUID(),
        key: soundKey.trim(),
        name: soundName.trim() || selectedFile.name,
        type: soundType,
        category: soundCategory,
        subcategory: soundSubcategory.trim(),
        localPath: `assets/audio/${selectedFile.name}`,
        remoteUrl: url,
        defaultValue: '',
        mimeType: selectedFile.type || 'audio/mpeg',
        fileSize: selectedFile.size,
        width: null,
        height: null,
        sortOrder: 0,
        isActive: true,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };

      await upsertAppAsset(record);
      await loadSounds();

      // Reset form
      setIsUploadOpen(false);
      setSelectedFile(null);
      setSoundName('');
      setSoundKey('');
      setSoundSubcategory('');
      setUploadProgress(0);
    } catch (err: any) {
      alert('فشل رفع الملف الصوتي: ' + (err.message || String(err)));
    } finally {
      setUploading(false);
    }
  };

  const handleSaveEdit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingSound) return;

    try {
      await updateAppAsset(editingSound.id, {
        name: editingSound.name,
        category: editingSound.category,
        subcategory: editingSound.subcategory,
        isActive: editingSound.isActive,
        remoteUrl: editingSound.remoteUrl,
      });
      await loadSounds();
      setIsEditOpen(false);
      setEditingSound(null);
    } catch (err: any) {
      alert('فشل حفظ التعديل: ' + (err.message || String(err)));
    }
  };

  const handleDelete = async (sound: AppAssetRecord) => {
    if (!confirm(`هل أنت متأكد من حذف الملف الصوتي "${sound.name}"؟`)) return;
    try {
      if (activePlayingId === sound.id && audioRef.current) {
        audioRef.current.pause();
        setActivePlayingId(null);
        setIsPlaying(false);
      }
      await deleteAppAsset(sound.id);
      await loadSounds();
    } catch (err: any) {
      alert('فشل الحذف: ' + (err.message || String(err)));
    }
  };

  const handleToggleActive = async (sound: AppAssetRecord) => {
    try {
      const nextActive = !sound.isActive;
      await updateAppAsset(sound.id, { isActive: nextActive });
      setSounds(prev => prev.map(s => s.id === sound.id ? { ...s, isActive: nextActive } : s));
    } catch (err: any) {
      alert('فشل تحديث الحالة: ' + (err.message || String(err)));
    }
  };

  // Filtered sounds
  const filteredSounds = sounds.filter(s => {
    const matchesCategory = selectedCategory === 'all' || s.category === selectedCategory;
    const matchesSearch = searchQuery === '' ||
      s.name?.toLowerCase().includes(searchQuery.toLowerCase()) ||
      s.key?.toLowerCase().includes(searchQuery.toLowerCase()) ||
      s.subcategory?.toLowerCase().includes(searchQuery.toLowerCase());
    return matchesCategory && matchesSearch;
  });

  // Calculate statistics
  const totalSoundsCount = sounds.length;
  const activeSoundsCount = sounds.filter(s => s.isActive).length;
  const totalSizeBytes = sounds.reduce((acc, s) => acc + (s.fileSize || 0), 0);

  const activePlayingSound = sounds.find(s => s.id === activePlayingId);

  return (
    <div className="space-y-6 max-w-7xl mx-auto pb-24" dir="rtl">
      {/* Header Section */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-[#111114] p-6 rounded-2xl border border-white/5 shadow-xl relative overflow-hidden">
        <div className="absolute top-0 right-0 w-96 h-96 bg-indigo-500/5 rounded-full blur-3xl -mr-20 -mt-20 pointer-events-none"></div>
        <div className="space-y-1 z-10">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center shadow-lg shadow-indigo-500/20">
              <Volume2 className="w-5 h-5 text-white" />
            </div>
            <div>
              <h1 className="text-xl font-bold text-white tracking-wide flex items-center gap-2">
                مكتبة الملفات الصوتية والمؤثرات (Audio Manager)
                <span className="text-xs font-normal px-2.5 py-0.5 rounded-full bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                  {totalSoundsCount} ملف
                </span>
              </h1>
              <p className="text-slate-400 text-xs mt-0.5">
                إدارة ورفع ومعاينة أصوات الهدايا، مؤثرات الغرف الصوتية، موسيقى الخلفية (BGM)، ونغمات الدخول والإشعارات.
              </p>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-3 z-10">
          <button
            onClick={loadSounds}
            className="p-2.5 rounded-xl bg-[#1A1A1E] text-slate-400 hover:text-white hover:bg-white/5 border border-white/5 transition-all"
            title="تحديث القائمة"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          </button>
          <button
            onClick={() => setIsUploadOpen(true)}
            className="px-4 py-2.5 bg-gradient-to-r from-indigo-600 to-purple-600 hover:from-indigo-500 hover:to-purple-500 text-white text-xs font-bold rounded-xl flex items-center gap-2 shadow-lg shadow-indigo-500/25 transition-all transform active:scale-95"
          >
            <Upload className="w-4 h-4" />
            رفع ملف صوتي جديد
          </button>
        </div>
      </div>

      {/* Stats Bar */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="bg-[#141417] p-4 rounded-xl border border-white/5 flex items-center justify-between">
          <div>
            <p className="text-slate-500 text-xs font-medium">إجمالي الأصوات</p>
            <p className="text-xl font-bold text-white mt-1">{totalSoundsCount}</p>
          </div>
          <div className="w-10 h-10 rounded-lg bg-indigo-500/10 flex items-center justify-center text-indigo-400">
            <Music className="w-5 h-5" />
          </div>
        </div>
        <div className="bg-[#141417] p-4 rounded-xl border border-white/5 flex items-center justify-between">
          <div>
            <p className="text-slate-500 text-xs font-medium">الأصوات النشطة</p>
            <p className="text-xl font-bold text-emerald-400 mt-1">{activeSoundsCount}</p>
          </div>
          <div className="w-10 h-10 rounded-lg bg-emerald-500/10 flex items-center justify-center text-emerald-400">
            <Sparkles className="w-5 h-5" />
          </div>
        </div>
        <div className="bg-[#141417] p-4 rounded-xl border border-white/5 flex items-center justify-between">
          <div>
            <p className="text-slate-500 text-xs font-medium">إجمالي حجم الملفات</p>
            <p className="text-xl font-bold text-purple-400 mt-1">{formatFileSize(totalSizeBytes)}</p>
          </div>
          <div className="w-10 h-10 rounded-lg bg-purple-500/10 flex items-center justify-center text-purple-400">
            <HardDrive className="w-5 h-5" />
          </div>
        </div>
      </div>

      {/* Filters & Search Bar */}
      <div className="space-y-3 bg-[#141417] p-4 rounded-xl border border-white/5">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-3">
          {/* Search Box */}
          <div className="relative flex-1">
            <Search className="w-4 h-4 text-slate-500 absolute right-3 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="ابحث بالاسم، المفتاح (Key)، أو التصنيف الفرعي..."
              className="w-full bg-[#1A1A1E] text-white text-xs rounded-xl pl-4 pr-9 py-2.5 border border-white/5 focus:border-indigo-500/50 focus:outline-none placeholder:text-slate-600 transition-all"
            />
            {searchQuery && (
              <button
                onClick={() => setSearchQuery('')}
                className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-500 hover:text-white text-xs"
              >
                مسح
              </button>
            )}
          </div>
        </div>

        {/* Category Badges */}
        <div className="flex items-center gap-2 overflow-x-auto pb-1 scrollbar-thin scrollbar-thumb-white/10">
          {AUDIO_CATEGORIES.map(cat => {
            const count = cat.id === 'all'
              ? sounds.length
              : sounds.filter(s => s.category === cat.id).length;
            const isSelected = selectedCategory === cat.id;
            return (
              <button
                key={cat.id}
                onClick={() => setSelectedCategory(cat.id)}
                className={`flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium whitespace-nowrap border transition-all ${
                  isSelected
                    ? `${cat.color} font-bold shadow-sm`
                    : 'bg-[#1A1A1E] text-slate-400 border-white/5 hover:text-white hover:bg-white/5'
                }`}
              >
                <cat.icon className="w-3.5 h-3.5" />
                <span>{cat.label}</span>
                <span className={`px-1.5 py-0.2 rounded-full text-[10px] ${isSelected ? 'bg-white/20' : 'bg-black/30 text-slate-500'}`}>
                  {count}
                </span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Sounds Grid */}
      {loading ? (
        <div className="flex flex-col items-center justify-center py-20 bg-[#111114] rounded-2xl border border-white/5">
          <RefreshCw className="w-8 h-8 text-indigo-500 animate-spin mb-3" />
          <p className="text-slate-400 text-sm font-medium">جاري تحميل مكتبة الأصوات...</p>
        </div>
      ) : filteredSounds.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 bg-[#111114] rounded-2xl border border-dashed border-white/10 text-center px-4">
          <div className="w-16 h-16 rounded-2xl bg-indigo-500/10 flex items-center justify-center text-indigo-400 mb-4">
            <Volume2 className="w-8 h-8" />
          </div>
          <h3 className="text-white font-bold text-base mb-1">لا توجد ملفات صوتية مطابقة</h3>
          <p className="text-slate-500 text-xs max-w-sm mb-5">
            {searchQuery || selectedCategory !== 'all'
              ? 'لم يتم العثور على أي ملفات تطابق معايير البحث الحالية.'
              : 'لم تقم برفع أي ملفات صوتية بعد. ابدأ برفع أول مؤثر صوتي لتطبيقه في التطبيق!'}
          </p>
          <button
            onClick={() => setIsUploadOpen(true)}
            className="px-4 py-2 bg-indigo-600 hover:bg-indigo-700 text-white text-xs font-bold rounded-xl flex items-center gap-2 transition-colors"
          >
            <Upload className="w-4 h-4" />
            رفع أول ملف صوتي
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filteredSounds.map(sound => {
            const isThisPlaying = activePlayingId === sound.id && isPlaying;
            const categoryObj = AUDIO_CATEGORIES.find(c => c.id === sound.category) || AUDIO_CATEGORIES[AUDIO_CATEGORIES.length - 1];

            return (
              <div
                key={sound.id}
                className={`bg-[#141417] hover:bg-[#18181D] rounded-2xl border transition-all p-4 flex flex-col justify-between group ${
                  isThisPlaying ? 'border-indigo-500/50 shadow-lg shadow-indigo-500/10 bg-[#171720]' : 'border-white/5'
                }`}
              >
                <div>
                  {/* Top Bar: Category & Status */}
                  <div className="flex items-center justify-between gap-2 mb-3">
                    <span className={`text-[11px] font-semibold px-2.5 py-0.5 rounded-full border ${categoryObj.color} flex items-center gap-1.5`}>
                      <categoryObj.icon className="w-3 h-3" />
                      {categoryObj.label.split(' ')[0]} {categoryObj.label.split(' ')[1]}
                    </span>

                    <div className="flex items-center gap-2">
                      <span className="text-[10px] text-slate-500 uppercase font-mono px-1.5 py-0.5 rounded bg-black/40 border border-white/5">
                        {sound.type || 'MP3'}
                      </span>
                      <button
                        onClick={() => handleToggleActive(sound)}
                        title={sound.isActive ? 'مفعل (اضغط للتعطيل)' : 'معطل (اضغط للتفعيل)'}
                        className={`w-2.5 h-2.5 rounded-full transition-all ${
                          sound.isActive ? 'bg-emerald-500 shadow-sm shadow-emerald-500/50 ring-2 ring-emerald-500/20' : 'bg-slate-600'
                        }`}
                      />
                    </div>
                  </div>

                  {/* Sound Info & Player Trigger */}
                  <div className="flex items-start gap-3 mb-3">
                    <button
                      onClick={() => handleTogglePlay(sound)}
                      className={`w-12 h-12 rounded-xl flex items-center justify-center shrink-0 transition-all shadow-md ${
                        isThisPlaying
                          ? 'bg-gradient-to-br from-indigo-500 to-purple-600 text-white scale-105 shadow-indigo-500/30 ring-2 ring-indigo-400/40'
                          : 'bg-[#1F1F24] group-hover:bg-indigo-600/20 text-indigo-400 group-hover:text-indigo-300 border border-white/5'
                      }`}
                    >
                      {isThisPlaying ? (
                        <Pause className="w-5 h-5 fill-white" />
                      ) : (
                        <Play className="w-5 h-5 fill-current ml-0.5" />
                      )}
                    </button>

                    <div className="flex-1 min-w-0">
                      <h4 className="text-sm font-bold text-white truncate" title={sound.name}>
                        {sound.name || 'بدون اسم'}
                      </h4>
                      <div className="flex items-center gap-2 mt-1">
                        <button
                          onClick={() => handleCopy(sound.key, sound.id + '_key')}
                          className="text-[11px] font-mono text-slate-400 hover:text-indigo-300 bg-black/30 hover:bg-indigo-500/10 px-2 py-0.5 rounded border border-white/5 flex items-center gap-1.5 truncate max-w-full"
                          title="انقر لنسخ المفتاح (Key)"
                        >
                          <span className="truncate">{sound.key}</span>
                          {copiedKey === sound.id + '_key' ? (
                            <Check className="w-3 h-3 text-emerald-400 shrink-0" />
                          ) : (
                            <Copy className="w-3 h-3 opacity-60 shrink-0" />
                          )}
                        </button>
                      </div>
                    </div>
                  </div>

                  {/* Mini Progress / Live status if playing */}
                  {activePlayingId === sound.id && (
                    <div className="bg-[#101014] p-2.5 rounded-xl border border-indigo-500/20 mb-3 space-y-1.5 animate-fadeIn">
                      <div className="flex items-center justify-between text-[10px] text-slate-400 font-mono">
                        <span>{formatTime(currentTime)}</span>
                        <span>{formatTime(duration)}</span>
                      </div>
                      <input
                        type="range"
                        min="0"
                        max={duration || 100}
                        step="0.01"
                        value={currentTime}
                        onChange={handleSeek}
                        className="w-full h-1 bg-white/10 rounded-lg appearance-none cursor-pointer accent-indigo-500"
                      />
                    </div>
                  )}

                  {/* Metadata tags */}
                  <div className="flex items-center justify-between text-[11px] text-slate-500 pt-2 border-t border-white/5">
                    <span className="truncate max-w-[140px]" title={sound.subcategory || 'عام'}>
                      {sound.subcategory ? `🏷️ ${sound.subcategory}` : 'عام'}
                    </span>
                    <span>{formatFileSize(sound.fileSize)}</span>
                  </div>
                </div>

                {/* Footer Action Buttons */}
                <div className="flex items-center justify-between pt-3 mt-2 border-t border-white/5">
                  <div className="flex items-center gap-1">
                    <button
                      onClick={() => handleCopy(sound.remoteUrl || '', sound.id + '_url')}
                      className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-white/5 transition-colors text-xs flex items-center gap-1"
                      title="نسخ رابط الصوت المباشر"
                    >
                      {copiedKey === sound.id + '_url' ? (
                        <Check className="w-3.5 h-3.5 text-emerald-400" />
                      ) : (
                        <Copy className="w-3.5 h-3.5" />
                      )}
                      <span className="text-[10px]">الرابط</span>
                    </button>
                    {sound.remoteUrl && (
                      <a
                        href={sound.remoteUrl}
                        target="_blank"
                        rel="noreferrer"
                        className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-white/5 transition-colors"
                        title="فتح في نافذة جديدة"
                      >
                        <ExternalLink className="w-3.5 h-3.5" />
                      </a>
                    )}
                  </div>

                  <div className="flex items-center gap-1">
                    <button
                      onClick={() => {
                        setEditingSound(sound);
                        setIsEditOpen(true);
                      }}
                      className="p-1.5 rounded-lg text-slate-400 hover:text-indigo-300 hover:bg-indigo-500/10 transition-colors"
                      title="تعديل البيانات"
                    >
                      <Edit3 className="w-3.5 h-3.5" />
                    </button>
                    <button
                      onClick={() => handleDelete(sound)}
                      className="p-1.5 rounded-lg text-slate-400 hover:text-rose-400 hover:bg-rose-500/10 transition-colors"
                      title="حذف الصوت"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Floating Bottom Audio Player Bar */}
      {activePlayingSound && (
        <div className="fixed bottom-4 left-4 right-4 md:left-24 md:right-24 bg-[#141419]/95 backdrop-blur-md border border-indigo-500/30 p-3.5 rounded-2xl shadow-2xl z-40 flex flex-col sm:flex-row sm:items-center justify-between gap-3 animate-slideUp">
          <div className="flex items-center gap-3 min-w-0">
            <button
              onClick={() => handleTogglePlay(activePlayingSound)}
              className="w-10 h-10 rounded-xl bg-gradient-to-r from-indigo-500 to-purple-600 text-white flex items-center justify-center shrink-0 shadow-lg shadow-indigo-500/30"
            >
              {isPlaying ? <Pause className="w-5 h-5 fill-white" /> : <Play className="w-5 h-5 fill-current ml-0.5" />}
            </button>
            <div className="min-w-0">
              <p className="text-white text-xs font-bold truncate">{activePlayingSound.name}</p>
              <p className="text-slate-400 text-[10px] font-mono truncate">{activePlayingSound.key}</p>
            </div>
          </div>

          <div className="flex-1 max-w-md mx-auto w-full flex items-center gap-2">
            <span className="text-[10px] text-slate-400 font-mono w-9 text-right">{formatTime(currentTime)}</span>
            <input
              type="range"
              min="0"
              max={duration || 100}
              step="0.01"
              value={currentTime}
              onChange={handleSeek}
              className="flex-1 h-1.5 bg-white/10 rounded-lg appearance-none cursor-pointer accent-indigo-500"
            />
            <span className="text-[10px] text-slate-400 font-mono w-9">{formatTime(duration)}</span>
          </div>

          <div className="flex items-center gap-3 justify-end">
            <button
              onClick={handleToggleLoop}
              className={`p-2 rounded-lg text-xs transition-colors ${
                isLooping ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30' : 'text-slate-400 hover:text-white'
              }`}
              title={isLooping ? 'التكرار مفعل' : 'تكرار التشغيل'}
            >
              🔁
            </button>
            <div className="flex items-center gap-1.5">
              <button onClick={handleToggleMute} className="text-slate-400 hover:text-white p-1">
                {isMuted || volume === 0 ? <VolumeX className="w-4 h-4" /> : <Volume2 className="w-4 h-4" />}
              </button>
              <input
                type="range"
                min="0"
                max="1"
                step="0.05"
                value={isMuted ? 0 : volume}
                onChange={(e) => handleVolumeChange(parseFloat(e.target.value))}
                className="w-16 h-1 bg-white/10 rounded-lg appearance-none cursor-pointer accent-indigo-500"
              />
            </div>
          </div>
        </div>
      )}

      {/* Upload Sound Modal */}
      {isUploadOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm animate-fadeIn">
          <div className="bg-[#141418] border border-white/10 rounded-2xl w-full max-w-lg overflow-hidden shadow-2xl">
            <div className="p-5 border-b border-white/5 flex items-center justify-between">
              <h3 className="text-white font-bold text-base flex items-center gap-2">
                <Upload className="w-5 h-5 text-indigo-400" />
                رفع ملف صوتي جديد (Upload Sound)
              </h3>
              <button
                onClick={() => !uploading && setIsUploadOpen(false)}
                className="text-slate-400 hover:text-white text-sm"
              >
                ✕
              </button>
            </div>

            <form onSubmit={handleSaveUpload} className="p-5 space-y-4">
              {/* File Dropzone */}
              <div>
                <label className="block text-slate-300 text-xs font-semibold mb-1.5">
                  ملف الصوت (.mp3, .wav, .ogg, .m4a, .aac) <span className="text-rose-400">*</span>
                </label>
                <div className="border-2 border-dashed border-white/10 hover:border-indigo-500/50 rounded-xl p-4 text-center cursor-pointer bg-[#1A1A1F] transition-colors relative">
                  <input
                    type="file"
                    accept="audio/*,.mp3,.wav,.ogg,.m4a,.aac"
                    onChange={handleFileChange}
                    className="absolute inset-0 opacity-0 cursor-pointer"
                    disabled={uploading}
                  />
                  {selectedFile ? (
                    <div className="space-y-1">
                      <div className="w-10 h-10 rounded-xl bg-indigo-500/20 text-indigo-400 flex items-center justify-center mx-auto mb-2">
                        <Music className="w-5 h-5" />
                      </div>
                      <p className="text-white text-xs font-bold truncate">{selectedFile.name}</p>
                      <p className="text-slate-400 text-[11px]">{formatFileSize(selectedFile.size)}</p>
                      <span className="inline-block text-[10px] text-indigo-400 mt-1">اضغط للتغيير</span>
                    </div>
                  ) : (
                    <div className="space-y-1 py-3">
                      <Upload className="w-8 h-8 text-slate-500 mx-auto mb-2" />
                      <p className="text-slate-300 text-xs font-medium">اسحب الملف وأفلته هنا أو اضغط للاختيار</p>
                      <p className="text-slate-500 text-[10px]">يدعم صيغ MP3, WAV, OGG, M4A, AAC</p>
                    </div>
                  )}
                </div>
              </div>

              {/* Sound Name */}
              <div>
                <label className="block text-slate-300 text-xs font-semibold mb-1">
                  اسم الصوت (Sound Name) <span className="text-rose-400">*</span>
                </label>
                <input
                  type="text"
                  value={soundName}
                  onChange={(e) => setSoundName(e.target.value)}
                  placeholder="مثال: صوت انفجار هدية التنين، نغمة دخول الفارس"
                  required
                  className="w-full bg-[#1A1A1F] text-white text-xs rounded-xl px-3.5 py-2.5 border border-white/10 focus:border-indigo-500 focus:outline-none"
                />
              </div>

              {/* Key Identifier */}
              <div>
                <label className="block text-slate-300 text-xs font-semibold mb-1">
                  مفتاح التعريف في التطبيق (Key Identifier) <span className="text-rose-400">*</span>
                </label>
                <input
                  type="text"
                  value={soundKey}
                  onChange={(e) => setSoundKey(e.target.value)}
                  placeholder="مثال: gift_dragon_sound, vip_entry_sound"
                  required
                  className="w-full bg-[#1A1A1F] text-white text-xs font-mono rounded-xl px-3.5 py-2.5 border border-white/10 focus:border-indigo-500 focus:outline-none"
                />
                <p className="text-slate-500 text-[10px] mt-1">يُستخدم هذا المفتاح للوصول إلى الصوت برمجياً داخل كود التطبيق.</p>
              </div>

              {/* Category & Subcategory */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-slate-300 text-xs font-semibold mb-1">
                    التصنيف الرئيسي (Category)
                  </label>
                  <select
                    value={soundCategory}
                    onChange={(e) => setSoundCategory(e.target.value)}
                    className="w-full bg-[#1A1A1F] text-white text-xs rounded-xl px-3 py-2.5 border border-white/10 focus:border-indigo-500 focus:outline-none"
                  >
                    {AUDIO_CATEGORIES.filter(c => c.id !== 'all').map(c => (
                      <option key={c.id} value={c.id}>
                        {c.label}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-slate-300 text-xs font-semibold mb-1">
                    تصنيف فرعي (Subcategory / Tag)
                  </label>
                  <input
                    type="text"
                    value={soundSubcategory}
                    onChange={(e) => setSoundSubcategory(e.target.value)}
                    placeholder="اختياري (مثال: lucky_gift, mic_effect)"
                    className="w-full bg-[#1A1A1F] text-white text-xs rounded-xl px-3.5 py-2.5 border border-white/10 focus:border-indigo-500 focus:outline-none"
                  />
                </div>
              </div>

              {/* Upload Progress */}
              {uploading && (
                <div className="space-y-1.5 bg-[#1A1A1F] p-3 rounded-xl border border-white/5">
                  <div className="flex justify-between text-xs text-slate-400">
                    <span>جاري رفع وحفظ الملف...</span>
                    <span>{uploadProgress}%</span>
                  </div>
                  <div className="w-full h-2 bg-white/5 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-gradient-to-r from-indigo-500 to-purple-600 transition-all duration-300"
                      style={{ width: `${uploadProgress}%` }}
                    />
                  </div>
                </div>
              )}

              {/* Action Buttons */}
              <div className="flex items-center justify-end gap-3 pt-3 border-t border-white/5">
                <button
                  type="button"
                  onClick={() => setIsUploadOpen(false)}
                  disabled={uploading}
                  className="px-4 py-2 rounded-xl text-slate-400 hover:text-white text-xs transition-colors"
                >
                  إلغاء
                </button>
                <button
                  type="submit"
                  disabled={uploading || !selectedFile}
                  className="px-5 py-2.5 bg-gradient-to-r from-indigo-600 to-purple-600 hover:from-indigo-500 hover:to-purple-500 disabled:opacity-50 text-white text-xs font-bold rounded-xl shadow-lg shadow-indigo-500/25 transition-all flex items-center gap-2"
                >
                  {uploading ? (
                    <>
                      <RefreshCw className="w-4 h-4 animate-spin" />
                      جاري الرفع...
                    </>
                  ) : (
                    <>
                      <Upload className="w-4 h-4" />
                      تأكيد ورفع الصوت
                    </>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Edit Sound Modal */}
      {isEditOpen && editingSound && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm animate-fadeIn">
          <div className="bg-[#141418] border border-white/10 rounded-2xl w-full max-w-lg overflow-hidden shadow-2xl">
            <div className="p-5 border-b border-white/5 flex items-center justify-between">
              <h3 className="text-white font-bold text-base flex items-center gap-2">
                <Edit3 className="w-5 h-5 text-indigo-400" />
                تعديل بيانات الصوت ({editingSound.key})
              </h3>
              <button
                onClick={() => setIsEditOpen(false)}
                className="text-slate-400 hover:text-white text-sm"
              >
                ✕
              </button>
            </div>

            <form onSubmit={handleSaveEdit} className="p-5 space-y-4">
              <div>
                <label className="block text-slate-300 text-xs font-semibold mb-1">
                  اسم الصوت
                </label>
                <input
                  type="text"
                  value={editingSound.name}
                  onChange={(e) => setEditingSound({ ...editingSound, name: e.target.value })}
                  required
                  className="w-full bg-[#1A1A1F] text-white text-xs rounded-xl px-3.5 py-2.5 border border-white/10 focus:border-indigo-500 focus:outline-none"
                />
              </div>

              <div>
                <label className="block text-slate-300 text-xs font-semibold mb-1">
                  التصنيف الرئيسي
                </label>
                <select
                  value={editingSound.category}
                  onChange={(e) => setEditingSound({ ...editingSound, category: e.target.value })}
                  className="w-full bg-[#1A1A1F] text-white text-xs rounded-xl px-3 py-2.5 border border-white/10 focus:border-indigo-500 focus:outline-none"
                >
                  {AUDIO_CATEGORIES.filter(c => c.id !== 'all').map(c => (
                    <option key={c.id} value={c.id}>
                      {c.label}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-slate-300 text-xs font-semibold mb-1">
                  تصنيف فرعي
                </label>
                <input
                  type="text"
                  value={editingSound.subcategory || ''}
                  onChange={(e) => setEditingSound({ ...editingSound, subcategory: e.target.value })}
                  className="w-full bg-[#1A1A1F] text-white text-xs rounded-xl px-3.5 py-2.5 border border-white/10 focus:border-indigo-500 focus:outline-none"
                />
              </div>

              <div>
                <label className="block text-slate-300 text-xs font-semibold mb-1">
                  رابط الصوت المباشر (URL)
                </label>
                <input
                  type="text"
                  value={editingSound.remoteUrl || ''}
                  onChange={(e) => setEditingSound({ ...editingSound, remoteUrl: e.target.value })}
                  className="w-full bg-[#1A1A1F] text-white text-xs font-mono rounded-xl px-3.5 py-2.5 border border-white/10 focus:border-indigo-500 focus:outline-none"
                />
              </div>

              <div className="flex items-center gap-3 pt-2">
                <input
                  type="checkbox"
                  id="editIsActive"
                  checked={editingSound.isActive}
                  onChange={(e) => setEditingSound({ ...editingSound, isActive: e.target.checked })}
                  className="w-4 h-4 rounded bg-[#1A1A1F] border-white/10 text-indigo-600 focus:ring-0 cursor-pointer"
                />
                <label htmlFor="editIsActive" className="text-slate-300 text-xs cursor-pointer select-none">
                  الملف الصوتي نشط ومتاح في التطبيق (Active)
                </label>
              </div>

              <div className="flex items-center justify-end gap-3 pt-3 border-t border-white/5">
                <button
                  type="button"
                  onClick={() => setIsEditOpen(false)}
                  className="px-4 py-2 rounded-xl text-slate-400 hover:text-white text-xs transition-colors"
                >
                  إلغاء
                </button>
                <button
                  type="submit"
                  className="px-5 py-2.5 bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold rounded-xl shadow-lg transition-all"
                >
                  حفظ التغييرات
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
