/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './app/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './hooks/**/*.{js,ts,jsx,tsx,mdx}',
    './store/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        // Wind speed scale (9 tiers, matching iOS)
        wind: {
          1: '#B3EDFF',  // <7 kts - light cyan
          2: '#54D9EB',  // 7-10 - turquoise
          3: '#59E385',  // 11-16 - green
          4: '#F8E654',  // 17-21 - yellow
          5: '#FAAB3A',  // 22-27 - orange
          6: '#F23842',  // 28-33 - red
          7: '#D433AB',  // 34-40 - magenta
          8: '#8C3EC8',  // 41-47 - purple
          9: '#6440A0',  // 48+ - deep purple
        },
        // Wave height scale (8 tiers, matching iOS)
        wave: {
          1: '#B3EDFF',  // <0.5m
          2: '#54D9EB',  // 0.5-1.0m
          3: '#59E385',  // 1.0-1.5m
          4: '#F8E654',  // 1.5-2.0m
          5: '#FAAB3A',  // 2.0-2.5m
          6: '#F23842',  // 2.5-3.0m
          7: '#D433AB',  // 3.0-4.0m
          8: '#8C3EC8',  // 4.0m+
        },
        // App accent colors
        accent: {
          cyan: '#22d3ee',
          blue: '#3b82f6',
          orange: '#f97316',
          indigo: '#6366f1',
        },
        // Glass background
        glass: {
          bg: 'rgba(255,255,255,0.08)',
          border: 'rgba(255,255,255,0.12)',
          hover: 'rgba(255,255,255,0.12)',
        },
      },
      backdropBlur: {
        xs: '4px',
        glass: '20px',
        heavy: '40px',
      },
      animation: {
        'shimmer': 'shimmer 1.5s infinite linear',
        'pulse-slow': 'pulse 2s ease-in-out infinite',
        'fadeInSimple': 'fadeInSimple 0.2s ease-out',
        'sheetUp': 'sheetUp 0.35s cubic-bezier(0.16, 1, 0.3, 1)',
        'sheetRight': 'sheetRight 0.3s cubic-bezier(0.16, 1, 0.3, 1)',
        'scaleIn': 'scaleIn 0.2s ease-out',
        'glassReveal': 'glassReveal 0.7s cubic-bezier(0.16, 1, 0.3, 1) both',
        'drift1': 'drift1 20s ease-in-out infinite',
        'drift2': 'drift2 25s ease-in-out infinite',
        'drift3': 'drift3 22s ease-in-out infinite',
        'drift4': 'drift4 18s ease-in-out infinite',
      },
      keyframes: {
        shimmer: {
          '0%': { transform: 'translateX(-100%)' },
          '100%': { transform: 'translateX(100%)' },
        },
        fadeInSimple: {
          from: { opacity: '0' },
          to: { opacity: '1' },
        },
        sheetUp: {
          from: { transform: 'translateY(100%)', opacity: '0' },
          to: { transform: 'translateY(0)', opacity: '1' },
        },
        sheetRight: {
          from: { transform: 'translateX(-100%)', opacity: '0' },
          to: { transform: 'translateX(0)', opacity: '1' },
        },
        scaleIn: {
          from: { opacity: '0', transform: 'scale(0.95)' },
          to: { opacity: '1', transform: 'scale(1)' },
        },
        glassReveal: {
          from: { opacity: '0', transform: 'translateY(20px) scale(0.97)', filter: 'blur(4px)' },
          to: { opacity: '1', transform: 'translateY(0) scale(1)', filter: 'blur(0)' },
        },
        drift1: {
          '0%, 100%': { transform: 'translate(0, 0)' },
          '50%': { transform: 'translate(60px, -40px)' },
        },
        drift2: {
          '0%, 100%': { transform: 'translate(0, 0)' },
          '50%': { transform: 'translate(-50px, 50px)' },
        },
        drift3: {
          '0%, 100%': { transform: 'translate(0, 0)' },
          '50%': { transform: 'translate(40px, 60px)' },
        },
        drift4: {
          '0%, 100%': { transform: 'translate(0, 0)' },
          '50%': { transform: 'translate(-60px, -30px)' },
        },
      },
    },
  },
  plugins: [],
}
