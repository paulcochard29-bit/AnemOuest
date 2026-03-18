'use client'
import { useEffect } from 'react'
import { useAppStore } from '@/store/appStore'
import { API as API_BASE, apiFetch } from '@/lib/api'

export function useBuoys() {
  const setBuoys = useAppStore(s => s.setBuoys)

  useEffect(() => {
    let mounted = true
    const fetchBuoys = async () => {
      try {
        const res = await apiFetch(`${API_BASE}/candhis`)
        if (!res.ok) return
        const data = await res.json()
        if (mounted) setBuoys(data.buoys || [])
      } catch (err) { console.error('Error fetching buoys:', err) }
    }
    fetchBuoys()
    const interval = setInterval(fetchBuoys, 300000)
    return () => { mounted = false; clearInterval(interval) }
  }, [setBuoys])
}
