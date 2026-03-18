'use client'
import { useRef, useCallback, useEffect } from 'react'

export function useSwipe(onSwipe?: (direction: 'left' | 'right') => void) {
  const startX = useRef(0)
  const startY = useRef(0)

  const onTouchStart = useCallback((e: React.TouchEvent) => {
    startX.current = e.touches[0].clientX
    startY.current = e.touches[0].clientY
  }, [])

  const onTouchEnd = useCallback((e: React.TouchEvent) => {
    if (!onSwipe) return
    const dx = e.changedTouches[0].clientX - startX.current
    const dy = e.changedTouches[0].clientY - startY.current
    if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 1.5) {
      onSwipe(dx > 0 ? 'right' : 'left')
    }
  }, [onSwipe])

  // Keyboard: left/right arrows
  useEffect(() => {
    if (!onSwipe) return
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'ArrowLeft') onSwipe('left')
      else if (e.key === 'ArrowRight') onSwipe('right')
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [onSwipe])

  return { onTouchStart, onTouchEnd }
}
