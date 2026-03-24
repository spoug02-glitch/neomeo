/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        primary: {
          50:  '#f0eeff',
          100: '#e2ddff',
          200: '#c6bbff',
          300: '#a899ff',
          400: '#8a73ff',
          500: '#6c52f5',
          600: '#4C3FCF',
          700: '#3b2fb0',
          800: '#2a1f90',
          900: '#1a1270',
          950: '#0e0945',
        },
        accent: '#F97316',
      },
      fontFamily: {
        sans: ['"Pretendard"', '"Noto Sans KR"', 'system-ui', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
