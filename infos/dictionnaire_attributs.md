# Dictionnaire des Attributs

## Types énumérés

### type_institution
- `universite` : Université
- `organisme_recherche` : Organisme de recherche
- `partenaire_prive` : Partenaire privé

### type_contrat
- `ANR` : Agence Nationale de la Recherche
- `H2020` : Horizon 2020 (programme européen)
- `Region` : Financement régional
- `Europe` : Financement européen
- `Autre` : Autre type de financement

### statut_dmp
- `brouillon` : DMP en cours de rédaction
- `soumis` : DMP soumis pour validation
- `valide` : DMP validé

---

## Table: institution

**Description** : Institution de rattachement (université, organisme de recherche ou partenaire privé).

| Attribut | Type | Contraintes | Description |
|----------|------|-------------|-------------|
| id | bigint | PK, auto-increment | Identifiant unique de l'institution |
| nom | text | NOT NULL | Nom de l'institution |
| type_institution | type_institution | NOT NULL | Type d'institution (enum) |
| adresse | text | | Adresse postale de l'institution |

**Contraintes supplémentaires** :
- UNIQUE(nom, type_institution)

---

## Table: laboratoire

**Description** : Laboratoire de recherche rattaché à une institution.

| Attribut | Type | Contraintes | Description |
|----------|------|-------------|-------------|
| id | bigint | PK, auto-increment | Identifiant unique du laboratoire |
| nom | text | NOT NULL | Nom du laboratoire (ex: LISA, LIRMM) |
| id_institution | bigint | NOT NULL, FK → institution(id) | Institution de rattachement |

**Contraintes supplémentaires** :
- UNIQUE(nom, id_institution)

---

## Table: projet

**Description** : Projet de recherche structurant dirigé par un chercheur unique.

| Attribut | Type | Contraintes | Description |
|----------|------|-------------|-------------|
| id | bigint | PK, auto-increment | Identifiant unique du projet |
| titre | text | NOT NULL | Titre du projet |
| description | text | | Description détaillée du projet |
| discipline | text | NOT NULL | Discipline scientifique du projet |
| budget_annuel_eur | decimal(12,2) | NOT NULL, >= 0 | Budget annuel en euros |
| date_debut | date | NOT NULL | Date de début du projet |
| date_fin | date | >= date_debut ou NULL | Date de fin du projet |
| id_laboratoire_pilote | bigint | NOT NULL, FK → laboratoire(id) | Laboratoire porteur du projet |
| id_chercheur_responsable | bigint | FK → chercheur(id) | Chercheur responsable du projet |

**Règle métier** : Le responsable du projet doit appartenir au laboratoire pilote (vérifié par trigger).

---

## Table: chercheur

**Description** : Chercheur affilié à un laboratoire.

| Attribut | Type | Contraintes | Description |
|----------|------|-------------|-------------|
| id | bigint | PK, auto-increment | Identifiant unique du chercheur |
| prenom | text | NOT NULL | Prénom du chercheur |
| nom | text | NOT NULL | Nom du chercheur |
| email | text | NOT NULL, UNIQUE | Adresse email professionnelle |
| orcid | varchar(19) | UNIQUE | Identifiant ORCID (format: 0000-0000-0000-0000) |
| discipline | text | | Discipline de recherche principale |
| id_laboratoire | bigint | NOT NULL, FK → laboratoire(id) | Laboratoire de rattachement |

---

## Table: projet_chercheur

**Description** : Table associative gérant la relation N-N entre projets et chercheurs.

| Attribut | Type | Contraintes | Description |
|----------|------|-------------|-------------|
| id | bigint | PK, auto-increment | Identifiant unique de l'association |
| id_projet | bigint | NOT NULL, FK → projet(id) | Identifiant du projet |
| id_chercheur | bigint | NOT NULL, FK → chercheur(id) | Identifiant du chercheur |
| role | text | | Rôle du chercheur dans le projet |
| date_debut | date | | Date de début de participation |
| date_fin | date | | Date de fin de participation |
| charge_pct | decimal(5,2) | 0-100 | Pourcentage d'effort alloué au projet |
| is_principal | boolean | DEFAULT false | Indique si c'est un chercheur principal |

**Contraintes supplémentaires** :
- UNIQUE(id_projet, id_chercheur)

---

## Table: contrat

**Description** : Contrat de financement d'un projet de recherche.

| Attribut | Type | Contraintes | Description |
|----------|------|-------------|-------------|
| id | bigint | PK, auto-increment | Identifiant unique du contrat |
| type_contrat | type_contrat | NOT NULL | Type de contrat (enum) |
| financeur | text | NOT NULL | Organisme financeur |
| intitule | text | NOT NULL | Intitulé du contrat |
| montant_eur | decimal(14,2) | NOT NULL, >= 0 | Montant total en euros |
| duree_mois | int | > 0 ou NULL | Durée en mois |
| date_debut | date | NOT NULL | Date de début du contrat |
| date_fin | date | NOT NULL, >= date_debut | Date de fin du contrat |
| id_projet | bigint | NOT NULL, FK → projet(id) | Projet financé |
| statut_dmp | statut_dmp | NOT NULL, DEFAULT 'brouillon' | Statut du Data Management Plan |
| date_validation_dmp | date | | Date de validation du DMP |
| url_document_dmp | text | | URL du document DMP |

**Règle métier** : Si statut_dmp = 'valide', alors date_validation_dmp et url_document_dmp doivent être renseignés.

---

## Table: publication

**Description** : Publication scientifique (métadonnées uniquement, fichiers stockés hors base).

| Attribut | Type | Contraintes | Description |
|----------|------|-------------|-------------|
| id | bigint | PK, auto-increment | Identifiant unique de la publication |
| titre | text | NOT NULL | Titre de la publication |
| doi | text | UNIQUE | Digital Object Identifier |
| date_publication | date | | Date de publication |
| nb_pages | int | > 0 ou NULL | Nombre de pages |
| url_externe | text | | URL vers le document (ex: HAL) |

---

## Table: publication_auteur

**Description** : Table associative entre publications et chercheurs (relation N-N).

| Attribut | Type | Contraintes | Description |
|----------|------|-------------|-------------|
| id_publication | bigint | NOT NULL, FK → publication(id) | Identifiant de la publication |
| id_chercheur | bigint | NOT NULL, FK → chercheur(id) | Identifiant du chercheur |
| ordre_auteur | int | NOT NULL, DEFAULT 1, > 0 | Ordre d'apparition dans la liste des auteurs |

**Contraintes supplémentaires** :
- PK(id_publication, id_chercheur)
- UNIQUE(id_publication, ordre_auteur) : un seul auteur par position

---

## Table: jeu_donnees

**Description** : Jeu de données produit dans le cadre d'un contrat (métadonnées uniquement).

| Attribut | Type | Contraintes | Description |
|----------|------|-------------|-------------|
| id | bigint | PK, auto-increment | Identifiant unique du jeu de données |
| id_contrat | bigint | NOT NULL, FK → contrat(id) | Contrat associé |
| description | text | NOT NULL | Description du jeu de données |
| id_auteur | bigint | NOT NULL, FK → chercheur(id) | Chercheur auteur du dataset |
| conditions_acces | text | | Conditions d'accès aux données |
| licence | text | | Licence d'utilisation |
| date_depot | date | | Date de dépôt officiel |
| url_externe | text | | URL vers l'entrepôt de données |

**Règle métier** : Le dépôt (date_depot non NULL) n'est autorisé que si le DMP du contrat est validé (vérifié par trigger).
