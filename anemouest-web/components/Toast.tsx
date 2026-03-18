'use client'

import { useEffect } from 'react'
import { useAppStore } from '@/store/appStore'
import type { Toast as ToastType } from '@/store/appStore'

const ICONS: Record<ToastType['type'], string> = {
  error: 'M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126z',
  warning: 'M12 9v3.75m0 3.75h.008M21 12a9 9 0 11-18 0 9 9 0 0118 0z',
  info: 'M11.25 11.25l.041-.02a.75.75 0 011.063.852l-.708 2.836a.75.75 0 001.063.853l.041-.021M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-9-3.75h.008v.008H12V8.25z',
  success: 'M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z',
}

const COLORS: Record<ToastType['type'], string> = {
  error: '#ff3b30',
  warning: '#ff9500',
  info: '#007aff',
  success: '#34c759',
}

function ToastItem({ toast }: { toast: ToastType }) {
  const removeToast = useAppStore(s => s.removeToast)
  const color = COLORS[toast.type]

  useEffect(() => {
    const timer = setTimeout(() => removeToast(toast.id), 5000)
    return () => clearTimeout(timer)
  }, [toast.id, removeToast])

  return (
    <div
      className="flex items-center gap-2.5 px-4 py-3 rounded-2xl max-w-sm animate-in slide-in-from-top-2"
      style={{
        background: 'var(--popup-bg)',
        backdropFilter: 'blur(40px) saturate(1.8)',
        WebkitBackdropFilter: 'blur(40px) saturate(1.8)',
        boxShadow: `0 8px 32px rgba(0,0,0,0.15), 0 0 0 0.5px rgba(255,255,255,0.2) inset, inset 0 1px 0 rgba(255,255,255,0.15)`,
        border: `0.5px solid color-mix(in srgb, ${color} 30%, transparent)`,
      }}
    >
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="shrink-0">
        <path d={ICONS[toast.type]} />
      </svg>
      <span className="text-[13px] font-medium flex-1" style={{ color: 'var(--text-primary)' }}>
        {toast.message}
      </span>
      {toast.action && (
        <button
          onClick={toast.action.onClick}
          className="text-[12px] font-bold px-2 py-1 rounded-lg shrink-0"
          style={{ color, background: `color-mix(in srgb, ${color} 10%, transparent)` }}
        >
          {toast.action.label}
        </button>
      )}
      <button
        onClick={() => removeToast(toast.id)}
        className="w-5 h-5 rounded-full flex items-center justify-center shrink-0 opacity-40 hover:opacity-100 transition-opacity"
      >
        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round">
          <path d="M18 6L6 18M6 6l12 12" />
        </svg>
      </button>
    </div>
  )
}

export function ToastContainer() {
  const toasts = useAppStore(s => s.toasts)

  if (toasts.length === 0) return null

  return (
    <div className="fixed top-4 left-1/2 -translate-x-1/2 z-[1000] flex flex-col gap-2">
      {toasts.map(toast => (
        <ToastItem key={toast.id} toast={toast} />
      ))}
    </div>
  )
}
