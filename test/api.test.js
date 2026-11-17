// Tests d'intégration : lancés par Jenkins contre l'application démarrée avec docker compose
const test = require("node:test");
const assert = require("node:assert");

const BASE = process.env.BASE_URL || "http://localhost:3000";

// Attend que le serveur (et Redis) soit prêt, 30 s maximum
test.before(async () => {
  for (let i = 0; i < 30; i++) {
    try {
      if ((await fetch(`${BASE}/health`)).ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error(`Le serveur ne répond pas sur ${BASE}`);
});

test("GET /health répond ok", async () => {
  const r = await fetch(`${BASE}/health`);
  assert.strictEqual(r.status, 200);
  assert.match(await r.text(), /^ok /);
});

test("un sondage invalide est refusé (400)", async () => {
  const r = await fetch(`${BASE}/api/sessions`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ question: "", options: ["A"] }),
  });
  assert.strictEqual(r.status, 400);
});

test("un sondage valide renvoie un code à 4 chiffres", async () => {
  const r = await fetch(`${BASE}/api/sessions`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ question: "Test ?", options: ["Oui", "Non"] }),
  });
  assert.strictEqual(r.status, 200);
  assert.match((await r.json()).code, /^\d{4}$/);
});
