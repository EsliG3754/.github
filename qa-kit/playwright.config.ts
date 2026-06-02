import { defineConfig, devices } from "@playwright/test";

/**
 * Config base Playwright para repos Logwell. Ver ../QA.md.
 *
 * - baseURL desde E2E_BASE_URL (CI lo inyecta; local default :3000).
 * - trace + video SIEMPRE on-first-retry para poder depurar en el cockpit NOC.
 * - reporter html (artifact) + list (consola) + json (lo consume el NOC en F3).
 */
const BASE_URL = process.env.E2E_BASE_URL || "http://127.0.0.1:3000";
const IS_CI = !!process.env.CI;

export default defineConfig({
  testDir: "./tests/e2e",
  // smoke debe ser rápido y determinista
  timeout: 30_000,
  expect: { timeout: 10_000 },
  fullyParallel: true,
  forbidOnly: IS_CI,
  retries: IS_CI ? 1 : 0,
  workers: IS_CI ? 2 : undefined,
  reporter: [
    ["list"],
    ["html", { open: "never", outputFolder: "playwright-report" }],
    ["json", { outputFile: "test-results/results.json" }],
  ],
  use: {
    baseURL: BASE_URL,
    trace: "on-first-retry",
    video: "on-first-retry",
    screenshot: "only-on-failure",
    actionTimeout: 10_000,
    // Header de modo QA: el backend suprime efectos externos cuando lo ve.
    extraHTTPHeaders: process.env.E2E_QA_TOKEN
      ? { "x-logwell-qa": process.env.E2E_QA_TOKEN }
      : {},
    // basic_auth para entornos privados (staging.* detrás de Caddy basic_auth).
    ...(process.env.E2E_BASIC_AUTH_USER
      ? {
          httpCredentials: {
            username: process.env.E2E_BASIC_AUTH_USER,
            password: process.env.E2E_BASIC_AUTH_PASS ?? "",
          },
        }
      : {}),
  },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    // Añadir firefox/webkit/mobile en regresión si se necesita.
  ],
});
