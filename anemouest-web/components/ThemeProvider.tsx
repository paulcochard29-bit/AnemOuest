'use client'

import { useEffect } from 'react'
import { useAppStore } from '@/store/appStore'

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const isDarkMode = useAppStore(s => s.isDarkMode)

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', isDarkMode ? 'dark' : 'light')
    // Update meta theme-color for mobile browser chrome
    const meta = document.querySelector('meta[name="theme-color"]')
    if (meta) meta.setAttribute('content', isDarkMode ? '#000000' : '#f2f2f7')
  }, [isDarkMode])

  return <>{children}</>
}
