'use client'

import { useRef, useEffect, useState, useCallback, type ReactNode } from 'react'
import type mapboxgl from 'mapbox-gl'

interface MapPopupProps {
  map: mapboxgl.Map
  lngLat: [number, number]
  onClose: () => void
  expanded?: boolean
  anchorBottom?: boolean // true for markers with anchor:'bottom' (webcams) — pos.y is at bottom of marker
  markerHeight?: number // full marker height in px (for anchorBottom markers)
  children: ReactNode
}

export function MapPopup({ map, lngLat, onClose, expanded, anchorBottom, markerHeight = 76, children }: MapPopupProps) {
  const popupRef = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState<{ x: number; y: number } | null>(null)
  const [active, setActive] = useState(false)

  const updatePosition = useCallback(() => {
    const point = map.project(lngLat as [number, number])
    setPos({ x: point.x, y: point.y })
  }, [map, lngLat])

  // Position tracking
  useEffect(() => {
    updatePosition()
    map.on('move', updatePosition)
    requestAnimationFrame(() => setActive(true))
    return () => { map.off('move', updatePosition) }
  }, [map, updatePosition])

  // Close on click outside
  useEffect(() => {
    const handleClick = (e: MouseEvent) => {
      if (popupRef.current && !popupRef.current.contains(e.target as Node)) {
        onClose()
      }
    }
    const timer = setTimeout(() => {
      document.addEventListener('mousedown', handleClick)
    }, 50)
    return () => {
      clearTimeout(timer)
      document.removeEventListener('mousedown', handleClick)
    }
  }, [onClose])

  // Close on Escape
  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    document.addEventListener('keydown', handleKey)
    return () => document.removeEventListener('keydown', handleKey)
  }, [onClose])

  if (!pos) return null

  const popupWidth = expanded ? 380 : 320
  const container = map.getContainer()
  const cw = container.clientWidth
  const gap = 0 // arrow tip touches the marker
  const arrowH = 10

  // For anchor:'center' markers (stations, buoys, spots): pos.y = center → top of marker = pos.y - halfH
  // For anchor:'bottom' markers (webcams): pos.y = bottom of marker → top of marker = pos.y - fullHeight
  const markerTopY = anchorBottom ? pos.y - markerHeight : pos.y - 13
  const arrowTipY = markerTopY - gap
  const ch = container.clientHeight

  let left = pos.x - popupWidth / 2
  let arrowLeft = popupWidth / 2

  // Clamp horizontal — arrow always points at marker x
  if (left < 8) { arrowLeft += left - 8; left = 8 }
  else if (left + popupWidth > cw - 8) { arrowLeft += (left + popupWidth) - (cw - 8); left = cw - 8 - popupWidth }
  arrowLeft = Math.max(16, Math.min(popupWidth - 16, arrowLeft))

  // If not enough space above (arrow tip too close to top), flip below marker
  let flipped = false
  let style: React.CSSProperties

  if (arrowTipY - arrowH < 60) {
    // Flip: popup below marker
    flipped = true
    const markerBottomY = anchorBottom ? pos.y : pos.y + 13
    const topY = markerBottomY + gap
    style = {
      left,
      top: topY,
      width: popupWidth,
      maxWidth: 'calc(100vw - 16px)',
      transformOrigin: 'top center',
    }
  } else {
    // Normal: popup above marker, anchored from bottom
    style = {
      left,
      bottom: ch - arrowTipY + arrowH,
      width: popupWidth,
      maxWidth: 'calc(100vw - 16px)',
      transformOrigin: 'bottom center',
    }
  }

  return (
    <div
      ref={popupRef}
      className={`map-popup ${active ? 'map-popup-active' : 'map-popup-enter'}`}
      style={style}
    >
      {flipped && (
        <div className="map-popup-arrow-up" style={{ marginLeft: arrowLeft - 10 }} />
      )}
      <div className="map-popup-content" style={{ maxHeight: 'calc(100vh - 80px)', overflowY: 'auto' }}>
        {children}
      </div>
      {!flipped && (
        <div className="map-popup-arrow" style={{ marginLeft: arrowLeft - 10 }} />
      )}
    </div>
  )
}
