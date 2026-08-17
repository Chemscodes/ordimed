'use strict';

const { Form, Patient } = require('../models');
const { scope, resoudreProfil } = require('../middleware/auth');
const { diffuser } = require('../realtime');
const c = require('../lib/coerce');

/**
 * Les documents médicaux : dossier initial, consultation, ordonnance,
 * demande de bilan, formulaire médecin.
 */
exports.lister = async (req, res) => {
  const filtre = scope(req);
  if (req.query.patientId) filtre.patientId = req.query.patientId;
  if (req.query.type) filtre.type = req.query.type;

  // « Qu'a-t-on rédigé aujourd'hui ? » — l'étape Conclusion de la
  // consultation lit ça pour cocher ce qui est fait.
  if (req.query.jour) {
    const debut = new Date(c.asDateOrNull(req.query.jour));
    debut.setHours(0, 0, 0, 0);
    filtre.createdAt = { $gte: debut, $lt: new Date(debut.getTime() + 86400000) };
  }

  const forms = await Form.find(filtre).sort({ createdAt: -1 }).limit(500);
  return res.json(forms.map((f) => f.toJSON()));
};

exports.creer = async (req, res) => {
  const patient = await Patient.findOne(scope(req, { _id: req.body.patientId }));
  if (!patient) return res.status(404).json({ error: 'Patient introuvable' });

  const auteur = req.body.auteurProfileId
    ? await resoudreProfil(req.parentUid, req.body.auteurProfileId)
    : null;

  const form = await Form.create(
    c.sansIndefinis({
      parentUid: req.parentUid,
      patientId: patient._id,
      auteurProfileId: auteur ? auteur._id : null,
      type: c.asText(req.body.type),
      contenu: c.asText(req.body.contenu),
      poids: c.asNumberOrNull(req.body.poids),
      taille: c.asNumberOrNull(req.body.taille),
      imc: c.asText(req.body.imc),
      notes: c.asText(req.body.notes),
      sections: req.body.sections,
      prescriptions: req.body.prescriptions,
      examens: req.body.examens,
      ordonnanceNumero: c.asText(req.body.ordonnanceNumero),
      seanceNumero: c.asText(req.body.seanceNumero),
      note_de_seance: c.asText(req.body.note_de_seance),
      visiteId: c.asText(req.body.visiteId),
      createdAt: new Date(),
    })
  );

  diffuser(req.parentUid, 'forms', 'creation', {
    id: String(form._id),
    patientId: String(patient._id),
  });
  return res.status(201).json(form.toJSON());
};

/**
 * Modifie un document existant.
 *
 * Firestore n'avait pas d'equivalent : chaque formulaire etant duplique sous
 * chaque profil sans identite partagee, l'app devait retrouver « le meme »
 * document dans les copies en comparant auteur, type, contenu et horodatage
 * a deux minutes pres. Un identifiant unique supprime tout cela.
 */
exports.modifier = async (req, res) => {
  const maj = c.sansIndefinis({
    contenu: req.body.contenu !== undefined ? c.asText(req.body.contenu) : undefined,
    notes: req.body.notes !== undefined ? c.asText(req.body.notes) : undefined,
    poids: req.body.poids !== undefined ? c.asNumberOrNull(req.body.poids) : undefined,
    taille: req.body.taille !== undefined ? c.asNumberOrNull(req.body.taille) : undefined,
    imc: req.body.imc !== undefined ? c.asText(req.body.imc) : undefined,
    sections: req.body.sections,
    prescriptions: req.body.prescriptions,
    examens: req.body.examens,
    seanceNumero:
      req.body.seanceNumero !== undefined
        ? c.asText(req.body.seanceNumero)
        : undefined,
    note_de_seance:
      req.body.note_de_seance !== undefined
        ? c.asText(req.body.note_de_seance)
        : undefined,
  });

  // Le type ne se modifie pas : il decide de la mise en page et de ce que
  // la consultation considere comme redige. Le changer transformerait une
  // ordonnance en bilan dans l'historique.
  const form = await Form.findOneAndUpdate(
    scope(req, { _id: req.params.id }),
    { $set: maj },
    { new: true, runValidators: true }
  );
  if (!form) return res.status(404).json({ error: 'Document introuvable' });

  diffuser(req.parentUid, 'forms', 'maj', {
    id: String(form._id),
    patientId: String(form.patientId),
  });
  return res.json(form.toJSON());
};

exports.supprimer = async (req, res) => {
  const form = await Form.findOneAndDelete(scope(req, { _id: req.params.id }));
  if (!form) return res.status(404).json({ error: 'Document introuvable' });

  diffuser(req.parentUid, 'forms', 'suppression', { id: String(form._id) });
  return res.json({ ok: true });
};
