import type { APIRequestContext } from "@playwright/test";

/**
 * Helpers de limpieza para datos sintéticos __qa__. Ver ../../../QA.md §5.
 *
 * Cada repo implementa el endpoint de limpieza que le sirva. El contrato sugerido:
 *
 *   DELETE /api/_qa/cleanup   (protegido por header x-logwell-qa: <QA_TOKEN>)
 *   body: { runId: string }   → borra todo registro con marcador __qa__ de ese run.
 *
 * El job nocturno (red de seguridad) llama lo mismo sin runId → purga > 24h.
 *
 * Si el repo no expone ese endpoint todavía, el spec hace teardown vía UI
 * (borrar desde la propia interfaz) — menos ideal pero válido para arrancar.
 */
export async function cleanupQaData(
  request: APIRequestContext,
  opts: { baseURL: string; token?: string; runId: string },
): Promise<void> {
  if (!opts.token) return; // sin token = ephemeral/local; el entorno se destruye solo
  try {
    await request.delete(`${opts.baseURL}/api/_qa/cleanup`, {
      headers: { "x-logwell-qa": opts.token },
      data: { runId: opts.runId },
      timeout: 10_000,
    });
  } catch {
    // El barrido nocturno es la red de seguridad; no fallar el test por el cleanup.
  }
}
