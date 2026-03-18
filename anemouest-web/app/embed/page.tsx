'use client'

import { Suspense } from 'react'
import { EmbedContent } from './EmbedContent'

export default function EmbedPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen flex items-center justify-center bg-[#f2f2f7]">
        <div className="w-5 h-5 border-2 border-[#e5e5ea] border-t-[#007aff] rounded-full animate-spin" />
      </div>
    }>
      <EmbedContent />
    </Suspense>
  )
}
