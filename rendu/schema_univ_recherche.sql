-- Schéma relationnel (français) pour la gestion des données de recherche (Université)
-- Base: PostgreSQL
-- Date: 2025-10-04
-- Authors: Sanna Thomas, Furfaro Thomas, Chêne Arlette

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
    adresse             TEXT
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
    date_creation       DATE, -- Date de création du jeu de données (métadonnées)
    date_depot          DATE, -- Règle: ne peut être non NULL que si le DMP du contrat est validé
    url_externe         TEXT,
    CONSTRAINT chk_dates_jeu_donnees CHECK (date_depot IS NULL OR date_creation IS NULL OR date_depot >= date_creation)
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
