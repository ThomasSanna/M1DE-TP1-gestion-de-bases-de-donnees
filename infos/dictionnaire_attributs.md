### institution

| Attribut         | Type                                                    | Description          |
| ---------------- | ------------------------------------------------------- | -------------------- |
| id               | BIGSERIAL                                               | Identifiant unique   |
| nom              | TEXT                                                    | Nom de l’institution |
| type_institution | ENUM(universite, organisme_recherche, partenaire_prive) | Type d’institution   |
| adresse          | TEXT                                                    | Adresse postale      |

---

### laboratoire

| Attribut       | Type      | Description                                       |
| -------------- | --------- | ------------------------------------------------- |
| id             | BIGSERIAL | Identifiant unique                                |
| nom            | TEXT      | Nom du laboratoire                                |
| id_institution | BIGINT    | FK → institution.id (institution de rattachement) |

---

### projet

| Attribut                 | Type          | Description                                |
| ------------------------ | ------------- | ------------------------------------------ |
| id                       | BIGSERIAL     | Identifiant unique                         |
| titre                    | TEXT          | Titre du projet                            |
| description              | TEXT          | Description du projet                      |
| discipline               | TEXT          | Discipline scientifique                    |
| budget_annuel_eur        | NUMERIC(12,2) | Budget annuel (≥ 0)                        |
| date_debut               | DATE          | Date de début                              |
| date_fin                 | DATE          | Date de fin (≥ date_debut ou NULL)         |
| id_laboratoire_pilote    | BIGINT        | FK → laboratoire.id (labo pilote)          |
| id_chercheur_responsable | BIGINT        | FK → chercheur.id (responsable, optionnel) |

---

### chercheur

| Attribut       | Type        | Description                                    |
| -------------- | ----------- | ---------------------------------------------- |
| id             | BIGSERIAL   | Identifiant unique                             |
| prenom         | TEXT        | Prénom                                         |
| nom            | TEXT        | Nom                                            |
| email          | TEXT        | Adresse email, unique                          |
| orcid          | VARCHAR(19) | Identifiant ORCID (0000-0000-0000-0000)        |
| discipline     | TEXT        | Discipline scientifique                        |
| id_laboratoire | BIGINT      | FK → laboratoire.id (labo de rattachement)     |
 

---

### contrat

| Attribut            | Type                                    | Description                         |
| ------------------- | --------------------------------------- | ----------------------------------- |
| id                  | BIGSERIAL                               | Identifiant unique                  |
| type_contrat        | ENUM(ANR, H2020, Region, Europe, Autre) | Type de contrat                     |
| financeur           | TEXT                                    | Financeur                           |
| intitule            | TEXT                                    | Intitulé du contrat                 |
| montant_eur         | NUMERIC(14,2)                           | Montant du financement (≥ 0)        |
| duree_mois          | INTEGER                                 | Durée en mois (>0 ou NULL)          |
| date_debut          | DATE                                    | Début du contrat                    |
| date_fin            | DATE                                    | Fin du contrat (≥ date_debut)       |
| id_projet           | BIGINT                                  | FK → projet.id                      |
| statut_dmp          | ENUM(brouillon, soumis, valide)         | Statut du DMP                       |
| date_validation_dmp | DATE                                    | Date de validation du DMP si valide |
| url_document_dmp    | TEXT                                    | URL du document DMP si valide       |

---

### publication

| Attribut         | Type      | Description                    |
| ---------------- | --------- | ------------------------------ |
| id               | BIGSERIAL | Identifiant unique             |
| titre            | TEXT      | Titre de la publication        |
| doi              | TEXT      | Identifiant DOI, unique        |
| date_publication | DATE      | Date de publication            |
| nb_pages         | INTEGER   | Nombre de pages (>0 ou NULL)   |
| url_externe      | TEXT      | Lien externe (archive ouverte) |

---

### publication_auteur

| Attribut       | Type    | Description                                 |
| -------------- | ------- | ------------------------------------------- |
| id_publication | BIGINT  | FK → publication.id                         |
| id_chercheur   | BIGINT  | FK → chercheur.id                           |
| ordre_auteur   | INTEGER | Ordre d’auteur (>0, unique par publication) |

---

### jeu_donnees

| Attribut         | Type      | Description                                       |
| ---------------- | --------- | ------------------------------------------------- |
| id               | BIGSERIAL | Identifiant unique                                |
| id_contrat       | BIGINT    | FK → contrat.id                                   |
| description      | TEXT      | Description du jeu de données                     |
| id_auteur        | BIGINT    | FK → chercheur.id (auteur)                        |
| conditions_acces | TEXT      | Conditions d’accès                                |
| licence          | TEXT      | Licence d’utilisation                             |
| date_depot       | DATE      | Date de dépôt (non NULL uniquement si DMP validé) |
| url_externe      | TEXT      | Lien externe vers le dépôt                        |
