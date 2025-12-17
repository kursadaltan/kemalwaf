import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';
// https://vite.dev/config/
export default defineConfig(() => {
    // Read from environment variable (set during docker build or npm script)
    const basePath = process.env.VITE_BASE_PATH || '/';
    return {
        plugins: [react()],
        // Dynamic base path: can be overridden with VITE_BASE_PATH env var
        // Development: "/" (default)
        // Production with Nginx: "/admin/" (set during build)
        base: basePath,
        resolve: {
            alias: {
                '@': path.resolve(__dirname, './src'),
            },
        },
        build: {
            outDir: '../admin/public',
            emptyOutDir: true,
        },
        server: {
            port: 5173,
            proxy: {
                '/api': {
                    target: 'http://localhost:8888',
                    changeOrigin: true,
                    secure: false,
                    ws: true,
                    configure: (proxy, _options) => {
                        proxy.on('proxyReq', (proxyReq, req, _res) => {
                            // Forward cookies
                            if (req.headers.cookie) {
                                proxyReq.setHeader('cookie', req.headers.cookie);
                            }
                        });
                    },
                },
            },
        },
    };
});
