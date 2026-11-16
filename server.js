// Quiz Live : serveur Express + Socket.io (WebSocket) + Redis
const express = require("express");
const http = require("http");
const path = require("path");
const { Server } = require("socket.io");
const { createClient } = require("redis");
const { createAdapter } = require("@socket.io/redis-adapter");

const PORT = process.env.PORT || 3000;
const REDIS_URL = process.env.REDIS_URL || "redis://localhost:6379";
// Dans Kubernetes, HOSTNAME = nom du Pod. Pratique pour la démo (logs).
const POD = process.env.HOSTNAME || "local";

async function main() {
  // 3 connexions Redis : une pour les données, deux pour le partage entre réplicas
  const redis = createClient({ url: REDIS_URL });
  const pub = redis.duplicate();
  const sub = redis.duplicate();
  await Promise.all([redis.connect(), pub.connect(), sub.connect()]);
  console.log(`[${POD}] connecté à Redis`);

  const app = express();
  app.use(express.json());
  app.use(express.static(path.join(__dirname, "public")));

  const server = http.createServer(app);
  const io = new Server(server, { transports: ["websocket"] });
  // L'adaptateur Redis permet à tous les Pods de se transmettre les messages
  io.adapter(createAdapter(pub, sub));

  // Lit une session et ses votes dans Redis
  async function resultats(code) {
    const session = await redis.hGetAll(`session:${code}`);
    if (!session.question) return null;
    const options = JSON.parse(session.options);
    const votes = await redis.hGetAll(`votes:${code}`);
    const liste = options.map((texte, i) => ({
      texte,
      votes: parseInt(votes[String(i)] || "0", 10),
    }));
    const total = liste.reduce((somme, o) => somme + o.votes, 0);
    return { code, question: session.question, options: liste, total };
  }

  // Vérification de santé (utile pour Kubernetes et Nagios)
  app.get("/health", async (req, res) => {
    try {
      await redis.ping();
      res.status(200).send(`ok ${POD}`);
    } catch (e) {
      res.status(500).send("redis indisponible");
    }
  });

  // L'animateur crée un sondage
  app.post("/api/sessions", async (req, res) => {
    const question = String(req.body.question || "").trim();
    const options = (req.body.options || [])
      .map((o) => String(o).trim())
      .filter(Boolean);
    if (!question || options.length < 2 || options.length > 6) {
      return res
        .status(400)
        .json({ erreur: "Il faut une question et entre 2 et 6 options." });
    }
    let code;
    do {
      code = String(Math.floor(1000 + Math.random() * 9000)); // code à 4 chiffres
    } while (await redis.exists(`session:${code}`));
    await redis.hSet(`session:${code}`, {
      question,
      options: JSON.stringify(options),
    });
    await redis.expire(`session:${code}`, 60 * 60 * 24);
    console.log(`[${POD}] session ${code} créée`);
    res.json({ code });
  });

  // WebSocket
  io.on("connection", (socket) => {
    console.log(`[${POD}] client ${socket.id} connecté`);
    socket.emit("pod", POD);

    // Un participant rejoint : il reçoit seulement la question et les options
    socket.on("rejoindre", async (code) => {
      code = String(code);
      const r = await resultats(code);
      if (!r) return socket.emit("erreur", "Code introuvable");
      console.log(`[${POD}] client ${socket.id} a rejoint la session ${code}`);
      socket.emit("question", {
        question: r.question,
        options: r.options.map((o) => o.texte),
      });
    });

    // L'écran commun des résultats (accessible avec le code)
    socket.on("rejoindre-ecran", async (code) => {
      code = String(code);
      const r = await resultats(code);
      if (!r) return socket.emit("erreur", "Code introuvable");
      socket.join(`ecran:${code}`);
      console.log(`[${POD}] écran des résultats connecté à la session ${code}`);
      socket.emit("resultats", r);
    });

    socket.on("voter", async (data = {}) => {
      const code = String(data.code);
      const r = await resultats(code);
      if (!r) return socket.emit("erreur", "Code introuvable");
      const choix = data.choix;
      if (!Number.isInteger(choix) || choix < 0 || choix >= r.options.length) {
        return;
      }
      await redis.hIncrBy(`votes:${code}`, String(choix), 1);
      await redis.expire(`votes:${code}`, 60 * 60 * 24);
      console.log(`[${POD}] vote de ${socket.id} : session ${code}, option ${choix}`);
      // Celui qui vient de voter peut désormais voir les résultats en direct
      socket.join(`ecran:${code}`);
      // Envoie les nouveaux résultats aux écrans de résultats et aux votants,
      // même s'il est connecté à un autre Pod
      io.to(`ecran:${code}`).emit("resultats", await resultats(code));
    });

    socket.on("disconnect", () => {
      console.log(`[${POD}] client ${socket.id} déconnecté`);
    });
  });

  server.listen(PORT, () => console.log(`[${POD}] serveur sur le port ${PORT}`));

  // Arrêt propre (important pour les mises à jour Kubernetes)
  process.on("SIGTERM", () => {
    console.log(`[${POD}] arrêt demandé`);
    io.close(() => process.exit(0));
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
