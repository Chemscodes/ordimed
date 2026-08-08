'use strict';

const jwt = require('jsonwebtoken');
const { Server } = require('socket.io');

/**
 * Le temps réel.
 *
 * C'est la pièce qu'on ne voit pas dans un schéma et sans laquelle l'app ne
 * marche plus « comme avant ». Firestore poussait chaque changement aux
 * clients abonnés : l'assistant place un patient en salle, l'écran du
 * médecin change tout seul. 27 flux `snapshots()` et 30 `StreamBuilder`
 * reposent là-dessus.
 *
 * REST ne pousse rien. Sans ce module, le médecin devrait rafraîchir à la
 * main — et la salle d'attente cesserait d'être partagée.
 *
 * Chaque cabinet a son salon. Un événement ne sort jamais du cabinet qui
 * l'a produit : c'est la même frontière que `parentUid` côté HTTP.
 */

let io = null;

const SECRET = process.env.JWT_SECRET || 'dev-secret-a-changer';

const salonDe = (parentUid) => `cabinet:${String(parentUid)}`;

function initRealtime(serveurHttp) {
  io = new Server(serveurHttp, {
    cors: { origin: '*' },
    // L'app est un client lourd sur un réseau de cabinet : la reconnexion
    // doit être rapide et silencieuse après une coupure Wi-Fi.
    pingInterval: 20000,
    pingTimeout: 20000,
  });

  io.use((socket, next) => {
    const jeton =
      socket.handshake.auth?.token ||
      (socket.handshake.headers.authorization || '').replace('Bearer ', '');

    if (!jeton) return next(new Error('Jeton absent'));

    try {
      const charge = jwt.verify(jeton, SECRET);
      socket.parentUid = String(charge.sub);
      // Le client ne choisit pas son salon : il est déduit du jeton. Le
      // laisser demander « abonne-moi au cabinet X » suffirait à écouter
      // les patients d'un autre.
      socket.join(salonDe(socket.parentUid));
      return next();
    } catch {
      return next(new Error('Jeton invalide'));
    }
  });

  return io;
}

/**
 * Annonce un changement au cabinet concerné.
 *
 * `entite` reprend le nom de la collection Firestore (`patients`,
 * `salle_attente`, `rendezvous`…) pour que le côté Flutter s'abonne avec le
 * même vocabulaire qu'il utilisait.
 */
function diffuser(parentUid, entite, action, donnees = {}) {
  if (!io) return;
  io.to(salonDe(parentUid)).emit('changement', {
    entite,
    action, // 'creation' | 'maj' | 'suppression'
    donnees,
    at: new Date().toISOString(),
  });
}

module.exports = { initRealtime, diffuser, salonDe };
