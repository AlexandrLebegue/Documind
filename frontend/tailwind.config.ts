import type { Config } from 'tailwindcss';

const config: Config = {
  content: [
    './src/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        beige: {
          50: '#FAF8F5',
          100: '#F5F0EB',
          200: '#E8DDD3',
          300: '#d1c7bc',
          400: '#b8a99a',
        },
        accent: {
          DEFAULT: '#2E75B6',
          hover: '#245d92',
          light: '#dbeafe',
        },
      },
    },
  },
  plugins: [],
};

export default config;
