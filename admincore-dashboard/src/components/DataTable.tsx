import { ChevronDown, ChevronLeft, ChevronRight, Search, X, Inbox } from 'lucide-react';
import { useState, useMemo, ReactNode } from 'react';

interface Column<T> {
  key: string;
  label: string;
  render?: (item: T) => ReactNode;
  sortable?: boolean;
  width?: string;
}

interface DataTableProps<T> {
  columns: Column<T>[];
  data: T[];
  onEdit?: (item: T) => void;
  onDelete?: (item: T) => void;
  searchKeys?: (keyof T)[];
  loading?: boolean;
}

export default function DataTable<T>({
  columns, data, onEdit, onDelete, searchKeys, loading,
}: DataTableProps<T>) {
  const [search, setSearch] = useState('');
  const [sortKey, setSortKey] = useState<string | null>(null);
  const [sortAsc, setSortAsc] = useState(true);
  const [page, setPage] = useState(1);
  const pageSize = 20;

  const filtered = useMemo(() => {
    if (!search.trim() || !searchKeys) return data;
    const q = search.toLowerCase();
    return data.filter((item: T) =>
      (searchKeys as (keyof T)[]).some(key =>
        String((item as Record<string, unknown>)[key as string] ?? '').toLowerCase().includes(q))
    );
  }, [data, search, searchKeys]);

  const sorted = useMemo(() => {
    if (!sortKey) return filtered;
    return [...filtered].sort((a, b) => {
      const aVal = (a as Record<string, unknown>)[sortKey];
      const bVal = (b as Record<string, unknown>)[sortKey];
      if (aVal == null || bVal == null) return 0;
      const cmp = String(aVal).localeCompare(String(bVal), undefined, { numeric: true });
      return sortAsc ? cmp : -cmp;
    });
  }, [filtered, sortKey, sortAsc]);

  const totalPages = Math.max(1, Math.ceil(sorted.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const paged = sorted.slice((currentPage - 1) * pageSize, currentPage * pageSize);
  const hasActions = Boolean(onEdit || onDelete);

  const toggleSort = (key: string) => {
    if (sortKey === key) setSortAsc(a => !a);
    else { setSortKey(key); setSortAsc(true); }
  };

  const actions = (item: T) => (
    <div className="flex items-center justify-end gap-2">
      {onEdit && (
        <button onClick={() => onEdit(item)}
          className="rounded-lg border border-indigo-500/25 bg-indigo-500/10 px-2.5 py-1 text-[10px] font-bold text-indigo-300 hover:bg-indigo-500/20">
          Edit
        </button>
      )}
      {onDelete && (
        <button onClick={() => onDelete(item)}
          className="rounded-lg border border-rose-500/25 bg-rose-500/10 px-2.5 py-1 text-[10px] font-bold text-rose-300 hover:bg-rose-500/20">
          Delete
        </button>
      )}
    </div>
  );

  return (
    <div className="overflow-hidden rounded-2xl border border-white/8 bg-white/[0.025] shadow-2xl shadow-black/20 backdrop-blur-sm">
      {/* Toolbar */}
      <div className="flex flex-wrap items-center gap-3 border-b border-white/6 bg-white/[0.02] p-3 sm:p-4">
        <div className="relative min-w-[180px] flex-1 sm:max-w-xs">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-slate-500" />
          <input
            type="text" value={search}
            onChange={e => { setSearch(e.target.value); setPage(1); }}
            placeholder="Search..."
            className="field w-full pl-9 pr-8"
          />
          {search && (
            <button onClick={() => setSearch('')} aria-label="Clear search"
              className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-white">
              <X className="h-3.5 w-3.5" />
            </button>
          )}
        </div>
        <span className="badge badge-ok mr-auto">{sorted.length} عنصر</span>
      </div>

      {/* Desktop table */}
      <div className="hidden overflow-x-auto md:block">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b border-white/8 bg-black/20">
              {columns.map(col => (
                <th key={col.key}
                  className={`p-3 text-right text-[10px] font-extrabold uppercase tracking-wider text-slate-500 ${col.sortable ? 'cursor-pointer select-none hover:text-white' : ''}`}
                  style={{ width: col.width }}
                  onClick={() => col.sortable && toggleSort(col.key)}>
                  <span className="inline-flex items-center gap-1.5">
                    {col.label}
                    {col.sortable && sortKey === col.key && (
                      <ChevronDown className={`h-3 w-3 transition-transform ${sortAsc ? '' : 'rotate-180'}`} />
                    )}
                  </span>
                </th>
              ))}
              {hasActions && <th className="w-24 p-3 text-left text-[10px] font-extrabold uppercase tracking-wider text-slate-500">إجراءات</th>}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              Array.from({ length: 6 }).map((_, i) => (
                <tr key={i} className="border-b border-white/5">
                  {columns.map(col => <td key={col.key} className="p-3"><div className="skeleton h-4 w-full" /></td>)}
                  {hasActions && <td className="p-3"><div className="skeleton h-4 w-16" /></td>}
                </tr>
              ))
            ) : paged.length === 0 ? (
              <tr><td colSpan={columns.length + (hasActions ? 1 : 0)} className="py-16 text-center">
                <Inbox className="mx-auto mb-3 h-8 w-8 text-slate-700" />
                <p className="text-xs text-slate-500">لا توجد بيانات لعرضها</p>
              </td></tr>
            ) : (
              paged.map((item, idx) => (
                <tr key={idx} className="border-b border-white/5 transition-colors hover:bg-white/[0.035]">
                  {columns.map(col => (
                    <td key={col.key} className="p-3 text-slate-200">
                      {col.render ? col.render(item) : String((item as Record<string, unknown>)[col.key] ?? '')}
                    </td>
                  ))}
                  {hasActions && (
                    <td className="sticky right-0 bg-[#111114] p-3 text-left shadow-[-8px_0_12px_-6px_rgba(0,0,0,0.6)]">
                      {actions(item)}
                    </td>
                  )}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* Mobile cards */}
      <div className="divide-y divide-white/5 md:hidden">
        {loading ? (
          Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="space-y-2 p-4"><div className="skeleton h-4 w-1/2" /><div className="skeleton h-4 w-full" /></div>
          ))
        ) : paged.length === 0 ? (
          <div className="py-14 text-center">
            <Inbox className="mx-auto mb-3 h-8 w-8 text-slate-700" />
            <p className="text-xs text-slate-500">لا توجد بيانات لعرضها</p>
          </div>
        ) : (
          paged.map((item, idx) => (
            <div key={idx} className="space-y-2.5 p-4">
              {columns.map(col => (
                <div key={col.key} className="flex items-start justify-between gap-4">
                  <span className="shrink-0 text-[10px] font-bold text-slate-500">{col.label}</span>
                  <span className="min-w-0 break-words text-left text-xs font-semibold text-slate-200">
                    {col.render ? col.render(item) : String((item as Record<string, unknown>)[col.key] ?? '')}
                  </span>
                </div>
              ))}
              {hasActions && <div className="pt-1">{actions(item)}</div>}
            </div>
          ))
        )}
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between gap-3 border-t border-white/6 bg-black/20 px-3 py-2.5 sm:px-4">
          <button disabled={currentPage <= 1} onClick={() => setPage(p => p - 1)}
            className="inline-flex items-center gap-1 rounded-lg border border-white/8 bg-white/5 px-2.5 py-1.5 text-[11px] font-bold text-slate-300 hover:bg-white/10 disabled:opacity-30">
            <ChevronRight className="h-3.5 w-3.5" /> السابق
          </button>
          <span className="font-mono text-[10px] text-slate-500">{currentPage} / {totalPages}</span>
          <button disabled={currentPage >= totalPages} onClick={() => setPage(p => p + 1)}
            className="inline-flex items-center gap-1 rounded-lg border border-white/8 bg-white/5 px-2.5 py-1.5 text-[11px] font-bold text-slate-300 hover:bg-white/10 disabled:opacity-30">
            التالي <ChevronLeft className="h-3.5 w-3.5" />
          </button>
        </div>
      )}
    </div>
  );
}
