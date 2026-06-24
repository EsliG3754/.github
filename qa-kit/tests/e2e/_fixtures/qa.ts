import { test as base, expect } from "@playwright/test";

/**
 * Fixtures QA Logwell. Ver ../../../QA.md §5 (datos sintéticos) y §6 (modo QA).
 *
 * Provee:
 *  - qa.marker      → prefijo "__qa__" para texto libre.
 *  - qa.email(slug) → qa+<slug>-<runId>@logwell.mx (sub-addressing, aislado por run).
 *  - qa.runId       → identifica el run (CI o local) para no colisionar en paralelo.
 *  - qa.isReal      → true si corremos contra una URL real (prod/staging) CON token.
 *  - qa.token       → token de modo QA (o undefined).
 *
 * Regla: todo dato creado en un entorno real lleva el marcador y se limpia en
 * teardown (ver teardown.ts). En ephemeral/local no hace falta token.
 */

const RUN_ID =
  process.env.E2E_RUN_ID || process.env.GITHUB_RUN_ID || `local-${process.pid}`;
const TARGET = process.env.E2E_TARGET || "ephemeral";
const QA_TOKEN = process.env.E2E_QA_TOKEN || undefined;

export type QaContext = {
  runId: string;
  marker: string;
  token: string | undefined;
  /** true cuando golpeamos una URL real (prod/staging). Implica disciplina de teardown. */
  isReal: boolean;
  /** Email sintético enruttable y reconocible: qa+<slug>-<runId>@logwell.mx */
  email: (slug: string) => string;
  /** Texto libre marcado: "__qa__ <text>" */
  text: (text: string) => string;
};

export const test = base.extend<{ qa: QaContext }>({
  qa: async ({}, provide) => {
    const ctx: QaContext = {
      runId: RUN_ID,
      marker: "__qa__",
      token: QA_TOKEN,
      isReal: TARGET === "url",
      email: (slug: string) => `qa+${slug}-${RUN_ID}@logwell.mx`,
      text: (text: string) => `__qa__ ${text}`,
    };
    await provide(ctx);
  },
});

export { expect };
