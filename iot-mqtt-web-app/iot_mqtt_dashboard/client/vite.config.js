/*
 * Smart City IoT Operations Console - vite.config.js
 * Copyright (c) 2026 Dr Shuo Ding <shuoding@outlook.com>
 * Licensed under the GNU Affero General Public License v3.0 or later
 * (AGPL-3.0-or-later). See the LICENSE file.
 */

import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5174
  }
});
