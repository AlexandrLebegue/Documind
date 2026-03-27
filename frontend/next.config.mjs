/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  trailingSlash: true,
  images: {
    unoptimized: true,
  },
  // In development, proxy API calls to the backend.
  // Rewrites are NOT supported with output: 'export', so we only
  // include them when running `next dev` (NODE_ENV === 'development').
  ...(process.env.NODE_ENV === 'development'
    ? {
        async rewrites() {
          return [
            {
              source: '/api/:path*',
              destination: 'http://localhost:8000/api/:path*',
            },
          ];
        },
      }
    : {}),
};

export default nextConfig;
