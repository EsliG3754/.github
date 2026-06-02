import { test, expect } from "../_fixtures/qa";
import { cleanupQaData } from "../_fixtures/teardown";

/**
 * Spec de ejemplo. Copiar y adaptar por app. Ver ../../../../QA.md.
 * Tag @smoke = entra al gate. Selectores por rol/label/testid.
 */

test.describe("@smoke ejemplo", () => {
  test("la home carga y muestra el CTA principal", async ({ page }) => {
    await page.goto("/");
    await expect(page).toHaveTitle(/.+/);
    // Reemplazar por el rol/nombre real del CTA del repo:
    // await expect(page.getByRole("link", { name: /cotizar/i })).toBeVisible();
  });

  // Limpieza de cualquier dato __qa__ creado por specs de este archivo.
  test.afterAll(async ({ playwright, qa, baseURL }) => {
    const request = await playwright.request.newContext();
    await cleanupQaData(request, {
      baseURL: baseURL || "",
      token: qa.token,
      runId: qa.runId,
    });
    await request.dispose();
  });
});
