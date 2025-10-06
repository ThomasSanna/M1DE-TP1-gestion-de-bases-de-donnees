# Schéma relationnel formel (FR)

Ce document formalise le schéma relationnel dérivé du DBML `schema_univ_recherche_fr.dbml`.
Il liste les tables, attributs, types, clés primaires, clés étrangères et contraintes principales.

---

## 1. Tables et attributs

1) institution
- id : BIGSERIAL, PK
- nom : TEXT NOT NULL
- type_institution : type_institution (ENUM) NOT NULL
- adresse : TEXT
- Contraintes : UNIQUE(nom, type_institution)

2) laboratoire
- id : BIGSERIAL, PK
- nom : TEXT NOT NULL
- id_institution : BIGINT NOT NULL, FK -> institution(id)
- Contraintes : UNIQUE(nom, id_institution)

3) projet
- id : BIGSERIAL, PK
- titre : TEXT NOT NULL
- description : TEXT
- discipline : TEXT NOT NULL
- budget_annuel_eur : NUMERIC(12,2) NOT NULL CHECK >= 0
- date_debut : DATE NOT NULL
- date_fin : DATE NULL, CHECK date_fin IS NULL OR date_fin >= date_debut
- id_laboratoire_pilote : BIGINT NOT NULL, FK -> laboratoire(id)
- id_chercheur_responsable : BIGINT NULL, FK -> chercheur(id)
- Note métier : le responsable doit être un chercheur affecté au projet et appartenir au laboratoire pilote (enforcé par trigger)

4) chercheur
- id : BIGSERIAL, PK
- prenom : TEXT NOT NULL
- nom : TEXT NOT NULL
- email : TEXT NOT NULL UNIQUE
- orcid : VARCHAR(19) UNIQUE
- discipline : TEXT
- id_laboratoire : BIGINT NOT NULL, FK -> laboratoire(id)
- id_projet : BIGINT NULL, FK -> projet(id)
- Note : simplification : un chercheur est impliqué dans au plus un projet structurant

5) contrat
- id : BIGSERIAL, PK
- type_contrat : type_contrat (ENUM) NOT NULL
- financeur : TEXT NOT NULL
- intitule : TEXT NOT NULL
- montant_eur : NUMERIC(14,2) NOT NULL CHECK >= 0
- duree_mois : INTEGER NULL
- date_debut : DATE NOT NULL
- date_fin : DATE NOT NULL CHECK date_fin >= date_debut
- id_projet : BIGINT NOT NULL, FK -> projet(id)
- statut_dmp : statut_dmp (ENUM) NOT NULL DEFAULT 'brouillon'
- date_validation_dmp : DATE NULL
- url_document_dmp : TEXT NULL
- Contraintes : si statut_dmp = 'valide' alors date_validation_dmp et url_document_dmp non NULL (CHECK)

6) publication
- id : BIGSERIAL, PK
- titre : TEXT NOT NULL
- doi : TEXT UNIQUE
- date_publication : DATE
- nb_pages : INTEGER NULL
- url_externe : TEXT

7) publication_auteur
- id_publication : BIGINT NOT NULL, FK -> publication(id)
- id_chercheur : BIGINT NOT NULL, FK -> chercheur(id)
- ordre_auteur : INTEGER NOT NULL (>=1)
- PK : (id_publication, id_chercheur)
- Contraintes : UNIQUE(id_publication, ordre_auteur)

8) jeu_donnees
- id : BIGSERIAL, PK
- id_contrat : BIGINT NOT NULL, FK -> contrat(id)
- description : TEXT NOT NULL
- id_auteur : BIGINT NOT NULL, FK -> chercheur(id)
- conditions_acces : TEXT
- licence : TEXT
- date_depot : DATE NULL (uniquement si DMP du contrat est validé)
- url_externe : TEXT

---

## 2. Contraintes d'intégrité et règles métiers importantes

- Intégrité référentielle :
  - laboratoire.id_institution -> institution.id (ON UPDATE RESTRICT, ON DELETE RESTRICT)
  - projet.id_laboratoire_pilote -> laboratoire.id (RESTRICT/RESTRICT)
  - projet.id_chercheur_responsable -> chercheur.id (RESTRICT / SET NULL)
  - chercheur.id_laboratoire -> laboratoire.id (RESTRICT/RESTRICT)
  - chercheur.id_projet -> projet.id (RESTRICT / SET NULL)
  - contrat.id_projet -> projet.id (RESTRICT/RESTRICT)
  - publication_auteur.id_publication -> publication.id (RESTRICT / CASCADE)
  - publication_auteur.id_chercheur -> chercheur.id (RESTRICT / RESTRICT)
  - jeu_donnees.id_contrat -> contrat.id (RESTRICT / RESTRICT)
  - jeu_donnees.id_auteur -> chercheur.id (RESTRICT / RESTRICT)

- Règles métiers (enforced par triggers PL/pgSQL dans le script SQL):
  - Le `id_chercheur_responsable` d'un projet doit référencer un chercheur qui a `chercheur.id_projet = projet.id` et `chercheur.id_laboratoire = projet.id_laboratoire_pilote`.
  - Un `jeu_donnees.date_depot` ne peut être renseigné que si le contrat associé a `statut_dmp = 'valide'` et une `date_validation_dmp` non nulle.
  - Si un contrat a `statut_dmp = 'valide'`, alors `date_validation_dmp` et `url_document_dmp` doivent être renseignés.

---

## 3. Ordre d'insertion recommandé (pour respecter triggers et FK)

1. `institution`
2. `laboratoire` (référence `institution`)
3. `chercheur` (sans id_projet si le projet n'existe pas encore)
4. `projet` (créer sans `id_chercheur_responsable` si nécessaire)
5. Mettre à jour `chercheur.id_projet` pour les chercheurs impliqués
6. Mettre à jour `projet.id_chercheur_responsable` (doit pointer vers un chercheur du projet et du labo pilote)
7. `contrat` (lié au projet)
8. `publication` puis `publication_auteur`
9. `jeu_donnees` (insérer `date_depot` uniquement si DMP validé)

---

## 4. Remarques

- Les types ENUM et triggers sont définis dans le script SQL `schema_univ_recherche_fr.sql`.
- Si vous souhaitez une version normalisée (3NF plus stricte, tables additionnelles pour disciplines, licences, types), je peux proposer un affinement.
