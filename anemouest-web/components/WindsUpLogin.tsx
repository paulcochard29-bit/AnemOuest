'use client'

import { useState, useCallback } from 'react'
import { API as API_BASE, apiFetch } from '@/lib/api'

interface WindsUpLoginProps {
  onClose: () => void
  onSuccess: (token: string) => void
}

export function WindsUpLogin({ onClose, onSuccess }: WindsUpLoginProps) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleSubmit = useCallback(async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email || !password) return

    setLoading(true)
    setError(null)

    try {
      const res = await apiFetch(`${API_BASE}/windsup`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'login', email, password }),
      })

      const data = await res.json()

      if (!res.ok || data.error) {
        setError(data.error || 'Identifiants incorrects')
        setLoading(false)
        return
      }

      if (data.token) {
        localStorage.setItem('windsupToken', data.token)
        onSuccess(data.token)
      } else {
        setError('Reponse inattendue du serveur')
      }
    } catch {
      setError('Erreur de connexion')
    }
    setLoading(false)
  }, [email, password, onSuccess])

  return (
    <div className="fixed inset-0 z-[900] flex items-center justify-center px-4" onClick={onClose}>
      <div className="absolute inset-0 bg-black/40 backdrop-blur-sm" />
      <div
        className="relative w-full max-w-sm rounded-2xl overflow-hidden"
        onClick={e => e.stopPropagation()}
        style={{
          background: 'var(--popup-bg)',
          backdropFilter: 'blur(40px) saturate(1.8)',
          WebkitBackdropFilter: 'blur(40px) saturate(1.8)',
          boxShadow: '0 8px 40px rgba(0,0,0,0.2), 0 0 0 0.5px var(--glass-shadow-inset) inset',
        }}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-5 pt-5 pb-2">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-xl flex items-center justify-center" style={{ background: '#06b6d415' }}>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#06b6d4" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <path d="M18.5 11H2v2h16.5c.83 0 1.5.67 1.5 1.5s-.67 1.5-1.5 1.5v2c1.93 0 3.5-1.57 3.5-3.5S20.43 11 18.5 11z" />
                <path d="M9.5 4C7.57 4 6 5.57 6 7.5h2c0-.83.67-1.5 1.5-1.5S11 6.67 11 7.5 10.33 8.5 9.5 8.5H2v2h7.5C11.43 10.5 13 8.93 13 7" />
              </svg>
            </div>
            <div>
              <h3 className="text-[16px] font-semibold" style={{ color: 'var(--text-primary)' }}>WindsUp</h3>
              <p className="text-[12px]" style={{ color: 'var(--text-secondary)' }}>Abonnement requis</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="w-8 h-8 rounded-full flex items-center justify-center"
            style={{ background: 'var(--glass-btn-bg)' }}
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
              <path d="M18 6L6 18M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className="px-5 pb-5 pt-3">
          <div className="space-y-2.5">
            <input
              type="text"
              placeholder="Email ou pseudo WindsUp"
              value={email}
              onChange={e => setEmail(e.target.value)}
              autoComplete="username"
              className="w-full px-4 py-3 rounded-xl text-[15px] outline-none transition"
              style={{
                background: 'var(--bg-primary)',
                color: 'var(--text-primary)',
                border: '0.5px solid var(--border)',
              }}
            />
            <input
              type="password"
              placeholder="Mot de passe"
              value={password}
              onChange={e => setPassword(e.target.value)}
              autoComplete="current-password"
              className="w-full px-4 py-3 rounded-xl text-[15px] outline-none transition"
              style={{
                background: 'var(--bg-primary)',
                color: 'var(--text-primary)',
                border: '0.5px solid var(--border)',
              }}
            />
          </div>

          {error && (
            <div className="mt-2.5 px-3 py-2 rounded-lg bg-[#ff3b30]/10 text-[#ff3b30] text-[13px] font-medium">
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={loading || !email || !password}
            className="w-full mt-4 py-3 rounded-xl text-[15px] font-semibold text-white transition-all active:scale-[0.97] disabled:opacity-50"
            style={{ background: '#06b6d4' }}
          >
            {loading ? (
              <span className="flex items-center justify-center gap-2">
                <span className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                Connexion...
              </span>
            ) : (
              'Se connecter'
            )}
          </button>

          <p className="text-center text-[11px] mt-3" style={{ color: 'var(--text-tertiary)' }}>
            Utilisez vos identifiants winds-up.com
          </p>
        </form>
      </div>
    </div>
  )
}
