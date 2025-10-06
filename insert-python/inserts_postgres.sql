-- PostgreSQL dump generated (synthetic data)
BEGIN;
-- Schema header from infos/schema_univ_recherche.sql
-- Schéma relationnel (français) pour la gestion des données de recherche (Université)
-- Base: PostgreSQL
-- Date: 2025-10-04

CREATE SCHEMA IF NOT EXISTS univ_recherche;
SET search_path TO univ_recherche;

-- Types énumérés (FR)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'type_institution') THEN
        CREATE TYPE type_institution AS ENUM ('universite','organisme_recherche','partenaire_prive');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'type_contrat') THEN
        CREATE TYPE type_contrat AS ENUM ('ANR','H2020','Region','Europe','Autre');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'statut_dmp') THEN
        CREATE TYPE statut_dmp AS ENUM ('brouillon','soumis','valide');
    END IF;
END $$;

-- Tables de référence
CREATE TABLE IF NOT EXISTS institution (
    id                  BIGSERIAL PRIMARY KEY,
    nom                 TEXT NOT NULL,
    type_institution    type_institution NOT NULL,
    adresse             TEXT,
    CONSTRAINT uq_institution_nom_type UNIQUE (nom, type_institution)
);

CREATE TABLE IF NOT EXISTS laboratoire (
    id              BIGSERIAL PRIMARY KEY,
    nom             TEXT NOT NULL,
    id_institution  BIGINT NOT NULL REFERENCES institution(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_laboratoire_nom_institution UNIQUE (nom, id_institution)
);

-- Projets structurants
CREATE TABLE IF NOT EXISTS projet (
    id                          BIGSERIAL PRIMARY KEY,
    titre                       TEXT NOT NULL,
    description                 TEXT,
    discipline                  TEXT NOT NULL,
    budget_annuel_eur           NUMERIC(12,2) NOT NULL CHECK (budget_annuel_eur >= 0),
    date_debut                  DATE NOT NULL,
    date_fin                    DATE,
    id_laboratoire_pilote       BIGINT NOT NULL REFERENCES laboratoire(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    id_chercheur_responsable    BIGINT NULL, -- FK ajoutée après création de chercheur
    CONSTRAINT chk_projet_dates CHECK (date_fin IS NULL OR date_fin >= date_debut)
);

-- Chercheurs
CREATE TABLE IF NOT EXISTS chercheur (
    id              BIGSERIAL PRIMARY KEY,
    prenom          TEXT NOT NULL,
    nom             TEXT NOT NULL,
    email           TEXT NOT NULL UNIQUE,
    orcid           VARCHAR(19), -- format 0000-0000-0000-0000
    discipline      TEXT,
    id_laboratoire  BIGINT NOT NULL REFERENCES laboratoire(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    -- NOTE: simplification initiale retirée. Un chercheur peut désormais participer à plusieurs projets.
    -- (la relation N-N est modélisée via la table associative `projet_chercheur` ci-dessous)
    CONSTRAINT uq_chercheur_orcid UNIQUE (orcid)
);

-- Ajout de la contrainte FK sur le responsable de projet (après la table chercheur)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_schema = 'univ_recherche' AND table_name = 'projet' AND constraint_name = 'fk_projet_chercheur_responsable'
    ) THEN
        ALTER TABLE projet
        ADD CONSTRAINT fk_projet_chercheur_responsable
        FOREIGN KEY (id_chercheur_responsable)
        REFERENCES chercheur(id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL;
    END IF;
END $$;

-- Contrats de financement
CREATE TABLE IF NOT EXISTS contrat (
    id                      BIGSERIAL PRIMARY KEY,
    type_contrat            type_contrat NOT NULL,
    financeur               TEXT NOT NULL,
    intitule                TEXT NOT NULL,
    montant_eur             NUMERIC(14,2) NOT NULL CHECK (montant_eur >= 0),
    duree_mois              INTEGER CHECK (duree_mois IS NULL OR duree_mois > 0),
    date_debut              DATE NOT NULL,
    date_fin                DATE NOT NULL,
    id_projet               BIGINT NOT NULL REFERENCES projet(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    -- DMP (Plan de Gestion des Données)
    statut_dmp              statut_dmp NOT NULL DEFAULT 'brouillon',
    date_validation_dmp     DATE,
    url_document_dmp        TEXT,
    CONSTRAINT chk_contrat_dates CHECK (date_fin >= date_debut),
    CONSTRAINT chk_dmp_valide_champs CHECK (
        statut_dmp <> 'valide' OR (date_validation_dmp IS NOT NULL AND url_document_dmp IS NOT NULL)
    )
);

-- Publications (métadonnées uniquement)
CREATE TABLE IF NOT EXISTS publication (
    id                  BIGSERIAL PRIMARY KEY,
    titre               TEXT NOT NULL,
    doi                 TEXT UNIQUE,
    date_publication    DATE,
    nb_pages            INTEGER CHECK (nb_pages IS NULL OR nb_pages > 0),
    url_externe         TEXT
    -- Optionnel: rattacher à un projet si souhaité
    --, id_projet       BIGINT REFERENCES projet(id) ON UPDATE RESTRICT ON DELETE SET NULL
);

-- Auteurs de publication (N-N)
CREATE TABLE IF NOT EXISTS publication_auteur (
    id_publication  BIGINT NOT NULL REFERENCES publication(id) ON UPDATE RESTRICT ON DELETE CASCADE,
    id_chercheur    BIGINT NOT NULL REFERENCES chercheur(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    ordre_auteur    INTEGER NOT NULL DEFAULT 1 CHECK (ordre_auteur > 0),
    PRIMARY KEY (id_publication, id_chercheur),
    CONSTRAINT uq_publication_ordre UNIQUE (id_publication, ordre_auteur)
);

-- Jeux de données (métadonnées uniquement)
CREATE TABLE IF NOT EXISTS jeu_donnees (
    id                  BIGSERIAL PRIMARY KEY,
    id_contrat          BIGINT NOT NULL REFERENCES contrat(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    description         TEXT NOT NULL,
    id_auteur           BIGINT NOT NULL REFERENCES chercheur(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    conditions_acces    TEXT,
    licence             TEXT,
    date_depot          DATE, -- Règle: ne peut être non NULL que si le DMP du contrat est validé
    url_externe         TEXT
);

-- Index utiles

-- Table associative pour gérer la relation N-N entre projets et chercheurs
CREATE TABLE IF NOT EXISTS projet_chercheur (
    id              BIGSERIAL PRIMARY KEY,
    id_projet       BIGINT NOT NULL REFERENCES projet(id) ON UPDATE RESTRICT ON DELETE CASCADE,
    id_chercheur    BIGINT NOT NULL REFERENCES chercheur(id) ON UPDATE RESTRICT ON DELETE CASCADE,
    role            TEXT,
    date_debut      DATE,
    date_fin        DATE,
    charge_pct      NUMERIC(5,2), -- pourcentage d'effort (0-100)
    is_principal    BOOLEAN DEFAULT FALSE,
    CONSTRAINT uq_projet_chercheur UNIQUE (id_projet, id_chercheur),
    CONSTRAINT chk_charge_pct CHECK (charge_pct IS NULL OR (charge_pct >= 0 AND charge_pct <= 100)),
    CONSTRAINT chk_dates_pc CHECK (date_fin IS NULL OR date_fin >= date_debut)
);

-- Fin du script FR (version simplifiée: index, triggers, fonctions et vue supprimés)

INSERT INTO univ_recherche.institution (id, nom, type_institution, adresse) VALUES (1, 'Petit', 'universite', '8, rue Laporte, 66277 Briand');
INSERT INTO univ_recherche.institution (id, nom, type_institution, adresse) VALUES (2, 'Lambert', 'universite', '50, boulevard Mathilde Lacombe, 81856 Monnier');
INSERT INTO univ_recherche.institution (id, nom, type_institution, adresse) VALUES (3, 'Texier', 'universite', 'boulevard Gonzalez, 66267 Thibault');
SELECT setval(pg_get_serial_sequence('univ_recherche.institution','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.institution),0));
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (1, 'Integrate mission-critical vortals Lab', 2);
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (2, 'Envisioneer granular schemas Lab', 2);
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (3, 'Seize robust supply-chains Lab', 2);
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (4, 'Incentivize vertical content Lab', 3);
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (5, 'Mesh frictionless e-markets Lab', 1);
SELECT setval(pg_get_serial_sequence('univ_recherche.laboratoire','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.laboratoire),0));
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (1, 'Christelle', 'Colas', 'christelle.colas@garcia.fr', '0842-7069-3009-3256', 'Chimie', 2);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (2, 'Marie', 'Brunel', 'marie.brunel@louis.fr', '9715-2445-1416-6482', 'Chimie', 4);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (3, 'Clémence', 'Lemaître', 'clémence.lemaître@vallet.com', NULL, 'Physique', 3);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (4, 'Audrey', 'Gérard', 'audrey.gérard@humbert.fr', '2565-7729-6647-1471', 'Physique', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (5, 'Martine', 'Laporte', 'martine.laporte@gautier.org', NULL, 'Physique', 3);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (6, 'Pierre', 'Faivre', 'pierre.faivre@guillon.fr', NULL, 'Chimie', 4);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (7, 'Philippe', 'Chauvet', 'philippe.chauvet@boyer.com', '0443-8615-0189-4075', 'Biologie', 3);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (8, 'Augustin', 'Marion', 'augustin.marion@pascal.com', '4733-9515-3174-8659', 'Chimie', 1);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (9, 'Augustin', 'Pons', 'augustin.pons@barre.net', '3137-9919-7438-9204', 'Biologie', 2);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (10, 'Luce', 'Navarro', 'luce.navarro@regnier.fr', NULL, 'Mathématiques', 3);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (11, 'Thérèse', 'Jacob', 'thérèse.jacob@bouchet.com', '8220-8414-2867-0412', 'Informatique', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (12, 'Augustin', 'Bertin', 'augustin.bertin@lefevre.net', NULL, 'Biologie', 3);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (13, 'Juliette', 'Roussel', 'juliette.roussel@gauthier.fr', NULL, 'Mathématiques', 2);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (14, 'Christelle', 'Thomas', 'christelle.thomas@fontaine.com', '5435-0839-9737-2688', 'Biologie', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (15, 'Cécile', 'Ferreira', 'cécile.ferreira@joseph.fr', '0361-5021-8059-2755', 'Physique', 2);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (16, 'Agathe', 'Rossi', 'agathe.rossi@maillard.com', NULL, 'Biologie', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (17, 'Clémence', 'Colas', 'clémence.colas@olivier.com', '7600-6070-1853-4878', 'Physique', 4);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (18, 'Roger', 'Barbe', 'roger.barbe@morvan.fr', NULL, 'Physique', 4);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (19, 'Thierry', 'Martinez', 'thierry.martinez@adam.org', '4177-7960-2892-7082', 'Informatique', 3);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (20, 'Capucine', 'Chevalier', 'capucine.chevalier@maury.fr', '9787-4240-3939-0828', 'Physique', 3);
SELECT setval(pg_get_serial_sequence('univ_recherche.chercheur','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.chercheur),0));
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (1, 'Le droit de changer plus rapidement', 'Y trouver sans nouveau public montagne.', 'Physique', 412743.2, '2025-06-10', '2026-03-26', 5, 15);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (2, 'L''art d''avancer de manière efficace', 'Suite miser lien chaîne. Entre souvent riche siège but lutte.', 'Chimie', 292839.05, '2023-07-30', '2028-03-24', 3, 8);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (3, 'Le pouvoir d''avancer en toute tranquilité', 'Chair conseil baisser. Nourrir poche fil toujours placer.', 'Chimie', 450438.82, '2025-08-01', '2027-10-16', 5, 5);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (4, 'Le plaisir de rouler plus rapidement', 'Âme départ cour construire. Sous expression seconde montrer. Compagnie conseil prévenir fonction rire minute.', 'Chimie', 30650.57, '2022-05-30', '2023-08-29', 3, 3);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (5, 'L''avantage d''évoluer de manière sûre', 'Étaler soulever maison moyen approcher violence valoir rêve. Angoisse porte joie.', 'Biologie', 134958.7, '2022-11-26', '2024-07-01', 4, 8);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (6, 'L''art de changer à sa source', 'Petit enfoncer conversation sou unique rapporter désir. Naissance oser armée feuille haïr reprendre suivant.', 'Informatique', 287469.31, '2021-09-29', '2024-02-07', 2, 13);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (7, 'L''avantage d''évoluer à la pointe', 'Table douleur bout toujours. Prochain poser interroger.', 'Mathématiques', 255569.83, '2024-06-06', '2026-02-23', 2, 6);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (8, 'Le pouvoir de rouler à sa source', 'Mille bien repousser seul plaire habitant. Famille apparence puisque poser présence vieux apparence.', 'Physique', 191369.79, '2024-12-28', NULL, 1, 9);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (9, 'La liberté de changer de manière sûre', 'Forcer que haute oreille retenir curiosité dangereux. Je accompagner haut signe papa.', 'Biologie', 181833.48, '2023-04-24', '2027-10-19', 3, 2);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (10, 'L''art de changer plus facilement', 'Fixer retirer soit éteindre confondre maintenir. Exposer fort l''une or résistance puissance user signe. Passer déchirer conscience court en important course garder.', 'Chimie', 292001.2, '2023-08-26', '2025-03-07', 4, 15);
SELECT setval(pg_get_serial_sequence('univ_recherche.projet','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.projet),0));
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (1, 'Europe', 'Pasquier SARL', 'Présent pauvre parvenir subir souvenir intention journée.', 764077.79, 24, '2022-07-31', '2024-04-21', 1, 'soumis', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (2, 'Europe', 'Labbé', 'Discussion forcer signe suivant quitter ne moment cabinet.', 1841929.8, 36, '2022-02-24', '2029-06-23', 3, 'valide', '2023-12-11', 'http://benard.fr/');
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (3, 'Europe', 'Lévy Aubry et Fils', 'Assister imposer police grand.', 1032419.83, 12, '2025-03-18', '2028-01-06', 8, 'soumis', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (4, 'H2020', 'Gomes SA', 'Présent encore animer découvrir lendemain.', 986311.18, 24, '2022-08-12', '2030-05-11', 9, 'soumis', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (5, 'Europe', 'Fleury', 'Mort dent former espoir.', 1016940.68, 12, '2024-01-06', '2025-03-28', 4, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (6, 'Europe', 'Étienne Étienne SA', 'Victime appeler as.', 964608.32, 12, '2022-10-26', '2030-07-25', 9, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (7, 'Autre', 'Rousset', 'Palais chute entre bien fortune.', 1053820.58, NULL, '2022-08-04', '2029-12-11', 10, 'soumis', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (8, 'Autre', 'Hebert Barre S.A.S.', 'Content mille voilà semaine hasard puis village double.', 1112385.23, NULL, '2025-06-13', '2026-10-17', 9, 'valide', '2025-07-16', 'https://www.cohen.net/');
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (9, 'Europe', 'Grégoire S.A.R.L.', 'Bruit haut armer sommeil cercle.', 1289968.46, 36, '2024-08-18', '2029-09-13', 8, 'soumis', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (10, 'Autre', 'Bertrand', 'Chute ensuite habiller cinquante.', 1377052.71, NULL, '2023-06-12', '2024-10-10', 3, 'soumis', NULL, NULL);
SELECT setval(pg_get_serial_sequence('univ_recherche.contrat','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.contrat),0));
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_depot, url_externe) VALUES (1, 3, 'Société possible léger tendre passé fort préparer vue corps crainte occuper.', 13, 'sur_demande', NULL, '2025-03-13', NULL);
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_depot, url_externe) VALUES (2, 9, 'Retenir nation île or fou rue éviter.', 15, 'restreint', 'CC-BY', NULL, NULL);
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_depot, url_externe) VALUES (3, 10, 'Enfin million soudain rang compte revoir société attaquer.', 15, 'ouvert', 'CC0', NULL, NULL);
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_depot, url_externe) VALUES (4, 4, 'Finir violent pour assister craindre patron prêter étrange étage nourrir souffrance.', 16, 'ouvert', NULL, '2024-04-11', NULL);
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_depot, url_externe) VALUES (5, 2, 'Valoir immobile matière moyen déchirer demande auteur signifier large silence éprouver grandir imaginer.', 2, 'sur_demande', 'CC-BY', NULL, 'http://www.charpentier.com/');
SELECT setval(pg_get_serial_sequence('univ_recherche.jeu_donnees','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.jeu_donnees),0));
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (1, 'Saint reculer nouveau haine.', NULL, '2023-06-08', NULL, NULL);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (1, 13, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (1, 17, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (1, 12, 3);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (1, 1, 4);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (1, 15, 5);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (2, 'Aucun qui classe mur roi conversation art.', NULL, '2022-04-28', 12, 'http://www.michel.com/');
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (2, 15, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (2, 17, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (2, 8, 3);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (2, 18, 4);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (3, 'Race rideau certes pouvoir somme.', '10.8537/VIwpar', '2021-01-02', 3, 'https://texier.org/');
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (3, 13, 1);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (4, 'Éclater exécuter scène carte ennemi.', NULL, '2025-09-25', 20, NULL);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (4, 13, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (4, 15, 2);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (5, 'Assister autre affirmer sueur ainsi tâche connaître.', NULL, '2023-02-25', 19, 'http://rolland.com/');
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (5, 1, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (5, 9, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (5, 2, 3);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (6, 'Terre aucun un servir égal image.', NULL, '2023-08-01', 17, 'https://colas.net/');
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (6, 2, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (6, 11, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (6, 1, 3);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (6, 8, 4);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (7, 'Souffler échapper terre temps.', NULL, '2023-11-29', 1, 'http://www.marty.fr/');
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (7, 8, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (7, 6, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (7, 4, 3);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (7, 19, 4);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (8, 'Image lever y personne oser dresser précéder.', '10.4048/lDmCZc', '2025-02-17', 4, NULL);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (8, 20, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (8, 1, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (8, 14, 3);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (8, 12, 4);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (9, 'Moitié ce tombe jeune tour écrire ennemi.', '10.7932/cXzgam', '2025-09-22', 11, NULL);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (9, 7, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (9, 17, 2);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (10, 'Petit nul avenir tout presser.', '10.3830/OLZZAJ', '2024-03-23', NULL, 'http://www.diaz.fr/');
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (10, 20, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (10, 9, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (10, 5, 3);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (10, 15, 4);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (10, 10, 5);
SELECT setval(pg_get_serial_sequence('univ_recherche.publication','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.publication),0));
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (1, 1, 17, 'PostDoc', '2025-02-18', NULL, 59.75, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (2, 1, 7, 'Technicien', '2025-05-03', NULL, 90.22, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (3, 1, 20, 'PostDoc', '2024-02-13', '2024-02-26', 43.03, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (4, 1, 14, 'Investigateur', '2024-07-18', '2026-01-08', 94.59, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (5, 2, 9, 'Doctorant', '2022-02-04', '2027-11-19', 23.09, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (6, 2, 6, 'PostDoc', '2024-01-09', NULL, 91.03, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (7, 2, 15, 'Doctorant', '2022-11-20', NULL, 74.16, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (8, 3, 19, 'Investigateur', '2024-04-09', NULL, 40.71, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (9, 3, 8, 'Doctorant', '2025-04-13', NULL, 94.3, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (10, 3, 3, 'PostDoc', '2021-06-19', NULL, 97.14, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (11, 3, 20, 'Investigateur', '2022-09-18', '2026-06-03', 85.86, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (12, 3, 1, 'Doctorant', '2025-01-04', NULL, 45.38, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (13, 3, 6, 'PostDoc', '2025-04-20', '2025-12-17', 68.78, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (14, 4, 16, 'Technicien', '2022-08-11', NULL, 11.99, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (15, 4, 11, 'PostDoc', '2023-01-03', NULL, 28.87, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (16, 5, 4, 'PostDoc', '2022-09-09', '2023-11-25', 33.58, true);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (17, 5, 19, 'Investigateur', '2024-10-12', NULL, 72.63, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (18, 5, 8, 'Technicien', '2023-04-27', '2027-09-07', 80.51, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (19, 6, 14, 'Technicien', '2024-05-19', NULL, 35.11, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (20, 6, 7, 'Doctorant', '2025-02-04', NULL, 48.76, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (21, 7, 16, 'Doctorant', '2024-07-02', NULL, 67.58, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (22, 7, 15, 'Doctorant', '2022-03-18', '2026-09-09', 48.82, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (23, 7, 3, 'Doctorant', '2025-08-08', '2026-12-23', 75.09, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (24, 8, 5, 'PostDoc', '2024-11-05', '2026-10-17', 64.36, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (25, 8, 9, 'PostDoc', '2024-06-12', '2026-08-31', 47.83, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (26, 8, 14, 'PostDoc', '2024-02-25', NULL, 31.79, true);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (27, 8, 2, 'Doctorant', '2021-08-08', '2027-04-09', 69.03, true);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (28, 8, 7, 'Doctorant', '2025-09-11', NULL, 49.17, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (29, 8, 10, 'PostDoc', '2021-04-12', '2021-11-25', 93.39, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (30, 9, 10, 'Technicien', '2023-09-15', '2028-07-29', 96.17, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (31, 9, 11, 'PostDoc', '2024-10-14', NULL, 57.55, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (32, 9, 3, 'Doctorant', '2021-08-23', NULL, 89.38, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (33, 9, 9, 'Investigateur', '2024-11-02', '2025-04-21', 14.22, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (34, 9, 6, 'Investigateur', '2025-09-28', NULL, 45.1, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (35, 10, 10, 'Technicien', '2022-12-03', '2023-08-01', 35.26, false);
SELECT setval(pg_get_serial_sequence('univ_recherche.projet_chercheur','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.projet_chercheur),0));
COMMIT;
