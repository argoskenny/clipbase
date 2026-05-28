import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": {
        target: "http://127.0.0.1:4174",
        headers: {
          "X-Forwarded-Host": "127.0.0.1:5173"
        }
      }
    }
  },
  preview: {
    port: 5173,
    proxy: {
      "/api": {
        target: "http://127.0.0.1:4174",
        headers: {
          "X-Forwarded-Host": "127.0.0.1:5173"
        }
      }
    }
  }
});
