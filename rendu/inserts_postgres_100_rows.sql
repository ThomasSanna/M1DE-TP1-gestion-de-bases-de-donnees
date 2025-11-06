-- PostgreSQL dump generated (synthetic data)
BEGIN;
-- Schema header from infos/schema_univ_recherche.sql
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

INSERT INTO univ_recherche.institution (id, nom, type_institution, adresse) VALUES (1, 'Prévost SA', 'partenaire_prive', '537, rue Marie Pires, 25301 Sainte ColetteVille');
INSERT INTO univ_recherche.institution (id, nom, type_institution, adresse) VALUES (2, 'Thibault', 'partenaire_prive', '73, avenue de Diaz, 90699 Muller');
INSERT INTO univ_recherche.institution (id, nom, type_institution, adresse) VALUES (3, 'Mendès S.A.S.', 'organisme_recherche', '5, boulevard de Blin, 47334 Mathieudan');
INSERT INTO univ_recherche.institution (id, nom, type_institution, adresse) VALUES (4, 'Lefort', 'partenaire_prive', '83, rue de Charpentier, 30824 Sainte Élodiedan');
INSERT INTO univ_recherche.institution (id, nom, type_institution, adresse) VALUES (5, 'Guillaume S.A.R.L.', 'organisme_recherche', '77, rue Claude Fournier, 17943 Bonnin');
INSERT INTO univ_recherche.institution (id, nom, type_institution, adresse) VALUES (6, 'Guillon', 'universite', '53, rue Andre, 60934 Hebertboeuf');
INSERT INTO univ_recherche.institution (id, nom, type_institution, adresse) VALUES (7, 'Blanchard', 'universite', '81, rue Gilbert Roux, 81500 Poirier');
INSERT INTO univ_recherche.institution (id, nom, type_institution, adresse) VALUES (8, 'Bruneau Perrier S.A.S.', 'organisme_recherche', 'boulevard Daniel, 44520 Hernandez');
INSERT INTO univ_recherche.institution (id, nom, type_institution, adresse) VALUES (9, 'Samson', 'universite', '426, boulevard de Lebrun, 91468 Andre-sur-Lejeune');
INSERT INTO univ_recherche.institution (id, nom, type_institution, adresse) VALUES (10, 'Legrand', 'organisme_recherche', '2, rue de Lévêque, 78382 Weissdan');
SELECT setval(pg_get_serial_sequence('univ_recherche.institution','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.institution),0));
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (1, 'Redefine scalable technologies Lab', 6);
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (2, 'Mesh cutting-edge synergies Lab', 10);
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (3, 'Streamline innovative content Lab', 7);
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (4, 'Brand front-end vortals Lab', 8);
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (5, 'Morph front-end content Lab', 2);
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (6, 'Revolutionize web-enabled web services Lab', 7);
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (7, 'Whiteboard enterprise markets Lab', 2);
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (8, 'Leverage plug-and-play methodologies Lab', 6);
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (9, 'E-enable 24/365 channels Lab', 2);
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (10, 'Harness web-enabled paradigms Lab', 3);
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (11, 'Repurpose web-enabled vortals Lab', 6);
INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES (12, 'Utilize impactful initiatives Lab', 10);
SELECT setval(pg_get_serial_sequence('univ_recherche.laboratoire','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.laboratoire),0));
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (1, 'Christelle', 'Rivière', 'christelle.rivière@maillot.com', NULL, 'Physique', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (2, 'Claudine', 'Lopez', 'claudine.lopez@foucher.fr', '4501-7491-1290-6860', 'Physique', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (3, 'Louis', 'Rodrigues', 'louis.rodrigues@renault.com', NULL, 'Physique', 3);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (4, 'Gilles', 'Lemaire', 'gilles.lemaire@gilles.org', '5784-8769-5436-7488', 'Informatique', 10);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (5, 'Margaud', 'Prévost', 'margaud.prévost@pascal.net', NULL, 'Chimie', 9);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (6, 'Frédéric', 'Cohen', 'frédéric.cohen@diallo.fr', NULL, 'Informatique', 4);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (7, 'Jacques', 'Pasquier', 'jacques.pasquier@etienne.fr', NULL, 'Biologie', 4);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (8, 'Arthur', 'Charles', 'arthur.charles@andre.fr', NULL, 'Biologie', 3);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (9, 'Juliette', 'Alves', 'juliette.alves@berthelot.net', NULL, 'Mathématiques', 7);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (10, 'Catherine', 'Bailly', 'catherine.bailly@dumas.fr', NULL, 'Biologie', 7);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (11, 'Charlotte', 'Paris', 'charlotte.paris@morin.fr', NULL, 'Biologie', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (12, 'Martin', 'Lévêque', 'martin.lévêque@perez.com', NULL, 'Biologie', 11);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (13, 'Eugène', 'Grenier', 'eugène.grenier@gomes.fr', NULL, 'Biologie', 4);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (14, 'Tristan', 'Pinto', 'tristan.pinto@baudry.fr', NULL, 'Informatique', 9);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (15, 'Guillaume', 'Pereira', 'guillaume.pereira@valentin.com', NULL, 'Informatique', 10);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (16, 'Martin', 'Giraud', 'martin.giraud@fleury.org', '3832-5533-3503-3833', 'Biologie', 9);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (17, 'Capucine', 'Poirier', 'capucine.poirier@schmitt.fr', '1607-7061-0452-6618', 'Physique', 8);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (18, 'Véronique', 'Duval', 'véronique.duval@imbert.org', NULL, 'Physique', 10);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (19, 'Emmanuelle', 'Schneider', 'emmanuelle.schneider@leblanc.com', NULL, 'Chimie', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (20, 'Marthe', 'Delannoy', 'marthe.delannoy@goncalves.fr', NULL, 'Physique', 10);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (21, 'Benjamin', 'Neveu', 'benjamin.neveu@jacquet.org', '9330-9143-2402-1822', 'Informatique', 2);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (22, 'Arthur', 'Imbert', 'arthur.imbert@brunel.com', '5137-8858-9550-6614', 'Biologie', 8);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (23, 'Zacharie', 'Collet', 'zacharie.collet@letellier.net', '8539-1979-9579-9603', 'Chimie', 12);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (24, 'David', 'Blanchet', 'david.blanchet@boulanger.fr', '6107-9332-3555-1948', 'Informatique', 1);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (25, 'Sabine', 'Fabre', 'sabine.fabre@paris.fr', '2396-2903-0085-5837', 'Physique', 9);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (26, 'Cécile', 'Jourdan', 'cécile.jourdan@bouchet.net', NULL, 'Biologie', 3);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (27, 'Marcelle', 'Lacroix', 'marcelle.lacroix@nicolas.fr', '8109-0030-1182-6324', 'Chimie', 10);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (28, 'Julien', 'Robert', 'julien.robert@pinto.org', '5512-1935-2901-8062', 'Biologie', 11);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (29, 'Guillaume', 'Lefort', 'guillaume.lefort@blin.net', NULL, 'Chimie', 1);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (30, 'Madeleine', 'Roussel', 'madeleine.roussel@leveque.fr', NULL, 'Biologie', 11);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (31, 'Christiane', 'Gautier', 'christiane.gautier@breton.com', NULL, 'Biologie', 4);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (32, 'Mathilde', 'Lejeune', 'mathilde.lejeune@devaux.fr', '7978-3495-4560-9636', 'Biologie', 8);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (33, 'Hortense', 'Lamy', 'hortense.lamy@marion.org', '7563-9074-9996-0195', 'Mathématiques', 12);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (34, 'Benjamin', 'Benard', 'benjamin.benard@gaillard.org', '9378-7488-4177-6041', 'Mathématiques', 8);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (35, 'Capucine', 'Peltier', 'capucine.peltier@joseph.fr', '5983-9417-4126-6596', 'Chimie', 4);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (36, 'Lucy', 'Marion', 'lucy.marion@prevost.org', '3153-7017-3233-9797', 'Mathématiques', 8);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (37, 'Claire', 'Martin', 'claire.martin@martel.com', '0281-8182-7812-0407', 'Biologie', 11);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (38, 'Manon', 'Thomas', 'manon.thomas@guillet.com', '5815-9761-3967-8458', 'Biologie', 4);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (39, 'Gérard', 'Jacquet', 'gérard.jacquet@lombard.com', NULL, 'Physique', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (40, 'Grégoire', 'De Sousa', 'grégoire.de sousa@auger.net', '6845-0737-3615-4231', 'Chimie', 2);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (41, 'Thibault', 'Colin', 'thibault.colin@mallet.net', NULL, 'Mathématiques', 10);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (42, 'Jacques', 'Simon', 'jacques.simon@georges.org', NULL, 'Informatique', 9);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (43, 'Anastasie', 'Cordier', 'anastasie.cordier@texier.com', '4644-6405-4012-9555', 'Biologie', 8);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (44, 'Laurence', 'Girard', 'laurence.girard@sanchez.com', '4933-3625-0693-9990', 'Chimie', 4);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (45, 'René', 'Allard', 'rené.allard@techer.com', NULL, 'Physique', 9);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (46, 'Zacharie', 'Morel', 'zacharie.morel@delahaye.org', NULL, 'Chimie', 7);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (47, 'Margot', 'Royer', 'margot.royer@lefort.net', NULL, 'Biologie', 11);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (48, 'William', 'Couturier', 'william.couturier@mendes.net', '3638-3626-0887-9978', 'Informatique', 8);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (49, 'Jacques', 'Bonnet', 'jacques.bonnet@pichon.fr', NULL, 'Informatique', 1);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (50, 'Christiane', 'Bègue', 'christiane.bègue@breton.com', '5754-0155-3621-2063', 'Chimie', 3);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (51, 'Gabrielle', 'Pires', 'gabrielle.pires@chevalier.fr', NULL, 'Mathématiques', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (52, 'Mathilde', 'Merle', 'mathilde.merle@valette.com', NULL, 'Biologie', 4);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (53, 'Jacqueline', 'Morvan', 'jacqueline.morvan@fabre.com', '8999-2142-0527-9089', 'Mathématiques', 6);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (54, 'Emmanuelle', 'Couturier', 'emmanuelle.couturier@gay.com', NULL, 'Informatique', 12);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (55, 'Marie', 'Huet', 'marie.huet@vaillant.fr', '1116-3594-7401-3760', 'Chimie', 9);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (56, 'Tristan', 'Leblanc', 'tristan.leblanc@lacombe.net', NULL, 'Biologie', 6);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (57, 'Laure', 'Perez', 'laure.perez@michel.fr', NULL, 'Biologie', 4);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (58, 'Zacharie', 'Fournier', 'zacharie.fournier@normand.fr', '2707-2020-8329-6949', 'Biologie', 8);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (59, 'Chantal', 'Laine', 'chantal.laine@denis.fr', NULL, 'Biologie', 10);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (60, 'Matthieu', 'Traore', 'matthieu.traore@maury.fr', NULL, 'Biologie', 2);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (61, 'Xavier', 'Pasquier', 'xavier.pasquier@ruiz.org', '0077-2455-1907-7825', 'Mathématiques', 2);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (62, 'René', 'Barthelemy', 'rené.barthelemy@guillaume.net', '4715-6278-4434-5280', 'Biologie', 11);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (63, 'Lucas', 'Gomes', 'lucas.gomes@gallet.fr', NULL, 'Biologie', 8);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (64, 'Anouk', 'Masson', 'anouk.masson@lecoq.fr', '8178-7194-6167-2851', 'Biologie', 2);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (65, 'Henri', 'Germain', 'henri.germain@goncalves.net', '2494-1364-9572-6085', 'Informatique', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (66, 'Emmanuelle', 'Mahe', 'emmanuelle.mahe@munoz.net', '9446-8985-6939-5108', 'Mathématiques', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (67, 'Clémence', 'Perrin', 'clémence.perrin@leveque.com', NULL, 'Biologie', 10);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (68, 'Louis', 'Lebrun', 'louis.lebrun@garcia.fr', '3892-7094-7087-8345', 'Biologie', 9);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (69, 'Frédérique', 'Diallo', 'frédérique.diallo@maillot.net', NULL, 'Physique', 8);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (70, 'Éric', 'Thomas', 'éric.thomas@legendre.fr', NULL, 'Biologie', 2);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (71, 'Paul', 'Benoit', 'paul.benoit@carpentier.com', '6392-9616-2327-8099', 'Biologie', 8);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (72, 'Maurice', 'Bonneau', 'maurice.bonneau@imbert.com', '2074-9515-8777-9749', 'Biologie', 7);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (73, 'Gilles', 'Bousquet', 'gilles.bousquet@arnaud.com', '1763-3726-4537-7914', 'Mathématiques', 1);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (74, 'Françoise', 'Marion', 'françoise.marion@dos.com', NULL, 'Mathématiques', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (75, 'André', 'Blanchard', 'andré.blanchard@millet.com', NULL, 'Chimie', 12);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (76, 'Margaud', 'Martel', 'margaud.martel@garnier.com', NULL, 'Physique', 10);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (77, 'Margot', 'Da Costa', 'margot.da costa@pineau.com', NULL, 'Informatique', 8);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (78, 'Martine', 'Léger', 'martine.léger@riviere.org', '9792-6278-8700-9299', 'Biologie', 2);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (79, 'Matthieu', 'Barbier', 'matthieu.barbier@raymond.com', '3703-8970-6642-4460', 'Chimie', 8);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (80, 'Frédérique', 'Gomes', 'frédérique.gomes@poirier.org', NULL, 'Physique', 7);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (81, 'François', 'Ferreira', 'françois.ferreira@jacob.com', '2815-6719-1789-6989', 'Mathématiques', 4);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (82, 'Charlotte', 'Guyon', 'charlotte.guyon@ferrand.com', '6437-5857-0044-6041', 'Biologie', 4);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (83, 'Pénélope', 'Gillet', 'pénélope.gillet@guilbert.com', NULL, 'Biologie', 11);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (84, 'Nicolas', 'Bourgeois', 'nicolas.bourgeois@marin.fr', '4967-6953-1389-5162', 'Physique', 1);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (85, 'Édith', 'Roussel', 'édith.roussel@barthelemy.com', NULL, 'Chimie', 2);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (86, 'Claudine', 'Marin', 'claudine.marin@da.fr', NULL, 'Informatique', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (87, 'Bernadette', 'Lemonnier', 'bernadette.lemonnier@philippe.fr', '0487-8695-0934-2734', 'Chimie', 1);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (88, 'Michel', 'Leclercq', 'michel.leclercq@collet.fr', NULL, 'Physique', 7);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (89, 'Gabrielle', 'Bernier', 'gabrielle.bernier@costa.fr', NULL, 'Physique', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (90, 'Isaac', 'Girard', 'isaac.girard@mendes.org', NULL, 'Chimie', 6);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (91, 'Adèle', 'Evrard', 'adèle.evrard@moreno.com', '0691-8102-7241-8711', 'Chimie', 1);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (92, 'Pierre', 'Morin', 'pierre.morin@guillet.fr', '6741-5507-2417-1895', 'Informatique', 8);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (93, 'Emmanuelle', 'Morin', 'emmanuelle.morin@caron.fr', '6271-8794-0905-4965', 'Physique', 8);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (94, 'Claude', 'Foucher', 'claude.foucher@weiss.fr', NULL, 'Physique', 12);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (95, 'Stéphanie', 'Foucher', 'stéphanie.foucher@maillet.fr', '8552-5656-1672-4143', 'Informatique', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (96, 'Martine', 'Leblanc', 'martine.leblanc@ledoux.fr', NULL, 'Biologie', 12);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (97, 'Margaux', 'Carre', 'margaux.carre@diallo.org', '9082-1593-6776-5894', 'Physique', 3);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (98, 'Zoé', 'Mallet', 'zoé.mallet@dupuis.fr', NULL, 'Physique', 5);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (99, 'Tristan', 'Arnaud', 'tristan.arnaud@bernard.fr', NULL, 'Mathématiques', 12);
INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES (100, 'Gilles', 'Weber', 'gilles.weber@pineau.com', '6551-9355-0563-0408', 'Physique', 2);
SELECT setval(pg_get_serial_sequence('univ_recherche.chercheur','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.chercheur),0));
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (1, 'L''assurance d''innover à la pointe', 'Surprendre rose tard jeunesse un. Parmi recherche général sauter certainement. Monde éteindre réel commencement patron.', 'Informatique', 463883.16, '2022-03-24', '2025-12-20', 7, 10);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (2, 'Le confort d''avancer de manière sûre', 'Coeur dangereux feu violent contraire or. Consentir parmi debout fier droit habitant parfaitement. Membre hauteur former abandonner.', 'Physique', 485266.12, '2020-11-05', '2022-12-31', 7, 36);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (3, 'La possibilité de changer avant-tout', 'Tout poids somme face suivant. Naturellement échapper réussir île fortune entrée. Déjà vague dent dernier français moins frapper mémoire.', 'Chimie', 36091.94, '2025-04-30', '2026-01-31', 10, 77);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (4, 'L''assurance de louer plus rapidement', 'Épaule crise étouffer vaste devant observer pourquoi. Commencer frapper plaindre pont saint quartier but.', 'Chimie', 30536.22, '2023-08-31', '2028-07-16', 5, 43);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (5, 'Le plaisir d''atteindre vos buts en toute tranquilité', 'Cri coucher pain etc admettre cent. Enfance rejoindre risquer rejoindre différent profond asseoir.', 'Biologie', 23271.64, '2022-11-29', '2026-04-26', 7, 19);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (6, 'La possibilité d''atteindre vos buts de manière efficace', 'Abandonner rouler moitié d''abord user intéresser occasion. Sien certes danser voici inconnu annoncer société. Religion cause lourd assurer fruit même colline.', 'Chimie', 358738.85, '2022-11-17', '2025-08-07', 7, 20);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (7, 'Le pouvoir de rouler à l''état pur', 'Passé puisque apparence dominer extraordinaire scène. Soulever gauche vie quelqu''un fixer politique.', 'Mathématiques', 339100.67, '2021-06-19', '2023-08-12', 4, 61);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (8, 'Le confort d''innover de manière efficace', 'Nuit sentier hier direction herbe. Qualité continuer vers herbe.', 'Physique', 383198.27, '2022-01-09', NULL, 7, 74);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (9, 'L''art de concrétiser vos projets sans soucis', 'Marcher forcer paquet.', 'Chimie', 365355.92, '2024-05-04', NULL, 5, 31);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (10, 'Le plaisir d''évoluer à sa source', 'Voiture mine usage chute qualité travers.', 'Mathématiques', 344992.98, '2021-11-15', NULL, 11, 9);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (11, 'La possibilité d''avancer à sa source', 'Temps cause mettre maître ouvert sérieux. Importer tu plonger jamais arracher épaule.', 'Chimie', 103793.57, '2020-12-30', '2022-03-25', 12, 64);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (12, 'La possibilité de concrétiser vos projets de manière sûre', 'Devant entre nouveau terrible. Ce sol matière unique environ. Autrefois objet convenir muet lettre.', 'Biologie', 52202.07, '2024-04-25', '2027-03-24', 11, 90);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (13, 'La liberté d''atteindre vos buts à la pointe', 'Appartement mur minute pain. Glisser pourquoi secret contraire groupe erreur.', 'Chimie', 34772.36, '2022-06-04', NULL, 1, 35);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (14, 'Le confort de louer de manière sûre', 'Rapport rejeter question aspect. Haïr l''un tromper conclure. Manquer note capable portier espoir jambe. Quoi franchir envoyer français soutenir douze voilà.', 'Chimie', 126005.6, '2022-08-17', '2023-07-25', 10, 24);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (15, 'Le confort de concrétiser vos projets avant-tout', 'Enfermer casser vite terrain muet. Indiquer signer déposer taille. Magnifique militaire devant retenir agent terrible défaut.', 'Mathématiques', 191343.9, '2025-07-29', '2027-11-22', 2, 30);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (16, 'L''avantage de concrétiser vos projets à la pointe', 'Poursuivre paysan centre partout entrée. Possible regarder vieux chaîne. Comment apparence certain camarade blanc colère crise. Noir ligne consentir avec résister naturellement.', 'Biologie', 197310.92, '2024-04-21', '2026-01-06', 7, 20);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (17, 'Le confort de rouler plus rapidement', 'Devant fort fort distinguer seigneur juger. Yeux victime livre. Malade plutôt dessiner bien avant.', 'Physique', 190617.79, '2025-02-12', '2027-12-01', 8, 11);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (18, 'Le pouvoir d''évoluer plus facilement', 'Oh ceci droite reculer eh. Donner paix qui public mode.', 'Biologie', 325704.15, '2021-11-05', '2025-11-17', 4, 58);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (19, 'L''assurance d''innover à la pointe', 'Caractère sombre découvrir sujet rare femme conclure.', 'Informatique', 80667.25, '2021-08-29', '2027-06-05', 9, 74);
INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES (20, 'Le plaisir d''évoluer à la pointe', 'Important horizon sur gens prononcer armer. Auquel paraître couler paix.', 'Chimie', 141749.47, '2024-04-13', '2027-02-22', 10, 81);
SELECT setval(pg_get_serial_sequence('univ_recherche.projet','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.projet),0));
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (1, 'Autre', 'Torres SARL', 'Pluie folie conseil dangereux.', 1557241.68, 12, '2023-07-03', '2027-04-14', 20, 'valide', '2024-10-23', 'https://www.foucher.net/');
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (2, 'ANR', 'Lemaître Devaux S.A.', 'Sorte franchir magnifique pendant fonction.', 548310.12, 12, '2025-02-23', '2029-03-12', 20, 'valide', '2025-05-29', 'https://www.leroux.net/');
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (3, 'Autre', 'Langlois', 'Portier avant enfoncer présent.', 595472.4, 24, '2025-09-03', '2027-07-28', 3, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (4, 'H2020', 'Joubert Tanguy S.A.', 'Cesser unique gros près.', 453824.08, 36, '2025-08-03', '2026-06-01', 11, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (5, 'H2020', 'Dupuis', 'Retour silence pouvoir vague million bien sauvage.', 1606348.58, NULL, '2024-07-03', '2030-08-14', 1, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (6, 'Europe', 'Vidal S.A.', 'Promettre principe mesure intérieur mieux chute dehors.', 1885499.66, NULL, '2024-03-12', '2030-11-04', 18, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (7, 'H2020', 'Philippe SARL', 'Sol projet saisir arrière épais.', 1090902.29, NULL, '2025-01-15', '2027-12-12', 10, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (8, 'Autre', 'Briand SARL', 'Feu mari école or.', 268413.38, NULL, '2023-12-02', '2027-08-07', 1, 'valide', '2025-09-03', 'http://barthelemy.com/');
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (9, 'Europe', 'Wagner Pottier SARL', 'Éprouver situation secret douleur tuer comment colère cerveau.', 1072011.95, NULL, '2022-05-16', '2023-03-04', 4, 'soumis', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (10, 'Europe', 'Cousin Marchal SA', 'Distinguer grave haut mieux main plaire ensuite entourer.', 296029.88, 12, '2024-03-08', '2029-05-11', 12, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (11, 'ANR', 'Lefort Bertin et Fils', 'Port bon à mériter épaule jamais devant.', 1726499.87, NULL, '2023-03-04', '2030-01-30', 9, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (12, 'ANR', 'Dumas et Fils', 'Étendre pièce feu falloir réclamer bouche chaise.', 804366.75, 12, '2022-06-29', '2027-05-15', 15, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (13, 'ANR', 'Chauvin', 'Cesse figurer dur.', 1248550.76, 24, '2023-09-05', '2023-12-15', 4, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (14, 'Region', 'Rodriguez Bourgeois S.A.', 'Noir désormais beauté colère lutter huit peu.', 1200606.63, 36, '2024-05-13', '2025-07-24', 5, 'soumis', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (15, 'H2020', 'Faivre', 'Saluer nature branche envelopper présent heureux.', 260998.59, NULL, '2024-09-23', '2025-02-17', 18, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (16, 'Europe', 'Lacombe', 'Porter prix mari accompagner mettre frapper clef françois.', 1562651.02, 24, '2022-11-30', '2026-01-11', 5, 'soumis', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (17, 'H2020', 'Renault', 'Exiger musique couche glisser mensonge devoir.', 1541669.52, NULL, '2025-01-23', '2027-09-26', 11, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (18, 'Region', 'Marin SARL', 'Mien morceau réunir rentrer affirmer vieillard bien.', 459082.67, NULL, '2025-03-15', '2028-10-18', 20, 'valide', '2025-08-18', 'http://morel.fr/');
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (19, 'Region', 'Pasquier SA', 'Retomber trop hors chercher dos.', 1490739.95, 36, '2023-10-31', '2025-10-04', 8, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (20, 'Europe', 'Raymond', 'Plaine événement docteur si tâche frère discussion arme.', 1855305.48, 24, '2024-07-30', '2025-02-13', 12, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (21, 'H2020', 'Guibert Hervé S.A.', 'Poursuivre tête se apprendre.', 1418877.32, 12, '2025-08-26', '2029-04-18', 8, 'soumis', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (22, 'H2020', 'Brun Lemonnier SARL', 'Un amuser aventure bas passer.', 416350.66, 24, '2023-08-17', '2027-12-05', 17, 'soumis', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (23, 'H2020', 'Jourdan Klein et Fils', 'Coûter comment colon soutenir.', 460494.77, 24, '2024-04-16', '2025-11-15', 18, 'valide', '2024-12-25', 'http://www.foucher.com/');
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (24, 'Europe', 'Jacques', 'Grandir conversation commun lutter croiser dresser lien.', 1197123.06, 24, '2024-10-28', '2030-10-13', 19, 'brouillon', NULL, NULL);
INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES (25, 'Region', 'Martineau S.A.R.L.', 'Portier avenir construire sujet dernier.', 1746954.12, 24, '2024-11-22', '2027-02-01', 6, 'soumis', NULL, NULL);
SELECT setval(pg_get_serial_sequence('univ_recherche.contrat','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.contrat),0));
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (1, 2, 'Sourire ramasser femme avec trou dimanche angoisse détail pousser tendre pas dont lèvre.', 66, 'sur_demande', 'CC-BY', '2023-09-05', '2025-05-14', 'https://marchal.fr/');
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (2, 8, 'Terreur regard tomber asseoir sauter lieu accrocher éclater nombre dès bleu capable vieil source place.', 74, 'restreint', NULL, '2023-11-15', '2025-01-31', NULL);
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (3, 22, 'Cependant sentir cours intérêt grâce poursuivre allumer.', 29, 'ouvert', 'ODbL', '2024-12-29', NULL, 'https://www.couturier.org/');
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (4, 1, 'Soi sang rentrer déclarer confondre comme faim bois nous saint sans marche.', 89, 'ouvert', NULL, '2024-12-15', '2025-01-23', NULL);
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (5, 14, 'Race seul avec mal beau huit liberté être accepter sérieux avancer dix lieu.', 33, 'sur_demande', 'ODbL', '2024-09-30', NULL, 'http://antoine.net/');
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (6, 9, 'Monde conseil faire rompre attirer discussion au.', 36, 'restreint', 'CC-BY', '2023-05-07', NULL, NULL);
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (7, 4, 'Rejoindre falloir fort avenir reculer chat robe silencieux gauche avec commander rouler parent foule justice.', 43, 'sur_demande', 'CC-BY', '2025-01-30', NULL, NULL);
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (8, 23, 'Or école passer train verre unique membre.', 73, 'restreint', 'CC-BY', '2024-07-24', '2025-05-31', 'https://www.barbe.com/');
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (9, 21, 'Couper croix voler pendant prochain comprendre livre carte soirée pas rouler soi toujours réfléchir.', 20, 'sur_demande', 'CC0', '2022-12-03', NULL, NULL);
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (10, 23, 'Tranquille bien nombre importer minute quarante entraîner arbre tu signer tendre remettre.', 12, 'sur_demande', 'ODbL', '2024-11-07', NULL, NULL);
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (11, 3, 'Tâche derrière instinct si résoudre vif poursuivre animal libre fermer seconde interroger parole éclater déposer couper.', 14, 'restreint', NULL, '2023-05-18', NULL, 'https://www.laurent.com/');
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (12, 22, 'Réserver seulement politique tromper escalier poitrine pain flamme.', 40, 'sur_demande', 'CC-BY', '2024-02-13', NULL, 'http://www.maurice.com/');
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (13, 16, 'Minute intérieur phrase trembler fond puissant nul surprendre sorte reprendre d''autres rapidement couler avant imaginer droite.', 97, 'sur_demande', 'CC-BY', '2024-02-06', NULL, NULL);
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (14, 8, 'Mien naître résister conscience accorder côté peau sourire vous.', 86, 'restreint', NULL, '2025-07-06', '2025-09-24', 'https://www.couturier.com/');
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (15, 8, 'Enlever coûter saint creuser où arrêter soirée secret sans.', 74, 'ouvert', NULL, '2025-05-06', '2025-07-12', 'https://www.delaunay.fr/');
INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES (16, 18, 'Homme passage causer engager rencontre obliger lune bout jeunesse social gouvernement.', 83, 'ouvert', 'CC-BY', '2023-08-25', '2023-12-28', NULL);
SELECT setval(pg_get_serial_sequence('univ_recherche.jeu_donnees','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.jeu_donnees),0));
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (1, 'Fils à approcher dernier occasion blanc.', '10.5276/VQrntU', '2022-02-26', NULL, NULL);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (1, 44, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (1, 47, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (1, 1, 3);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (1, 53, 4);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (2, 'Course réalité frapper quoi entretenir écarter et.', '10.1960/YOEyNv', '2021-06-03', 9, 'http://www.moreno.com/');
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (2, 98, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (2, 79, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (2, 72, 3);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (2, 35, 4);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (3, 'Public partager profond arbre fond accompagner.', NULL, '2021-12-02', 11, 'https://www.colas.fr/');
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (3, 77, 1);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (4, 'Affaire désormais toucher note.', '10.7886/fJkeKh', '2020-12-26', 7, NULL);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (4, 12, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (4, 20, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (4, 91, 3);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (4, 71, 4);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (4, 2, 5);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (5, 'Différent éviter quant à livre jardin calme françois pousser.', NULL, '2023-03-08', 15, NULL);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (5, 18, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (5, 62, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (5, 43, 3);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (5, 48, 4);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (5, 90, 5);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (6, 'Circonstance crise chaise refuser.', '10.3946/XuFQxl', '2023-12-12', 5, NULL);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (6, 52, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (6, 14, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (6, 93, 3);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (7, 'Au remplacer demander gauche.', NULL, '2022-11-20', 9, 'https://www.roussel.com/');
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (7, 58, 1);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (8, 'Point tout interroger haut.', NULL, '2023-04-10', 8, 'http://turpin.fr/');
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (8, 71, 1);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (9, 'Trois nu près l''une complet boire quatre.', '10.5983/ylklUE', '2021-06-27', 12, NULL);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (9, 77, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (9, 1, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (9, 37, 3);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (9, 61, 4);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (10, 'Arme fin prêter banc.', NULL, '2025-05-30', 5, NULL);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (10, 50, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (10, 10, 2);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (11, 'Désert visage eaux compagnie quitter pourquoi goutte.', NULL, '2023-01-05', 17, 'http://www.brunel.org/');
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (11, 17, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (11, 93, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (11, 34, 3);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (12, 'Reculer fauteuil portier autre.', '10.4332/VbbTaz', '2021-08-21', 20, 'http://www.grenier.fr/');
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (12, 33, 1);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (13, 'Peser rapidement roman hauteur impression âgé vieil passion.', NULL, '2023-05-12', 4, NULL);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (13, 86, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (13, 73, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (13, 6, 3);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (13, 26, 4);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (14, 'Bataille rapporter espace choisir.', NULL, '2023-05-13', 5, NULL);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (14, 36, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (14, 99, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (14, 5, 3);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (15, 'Ensuite point peuple ville.', '10.7019/iOAkuZ', '2023-07-28', 1, 'http://bousquet.com/');
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (15, 93, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (15, 57, 2);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (16, 'Froid conseil sueur tôt soutenir.', NULL, '2023-01-27', 4, NULL);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (16, 44, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (16, 12, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (16, 51, 3);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (16, 15, 4);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (17, 'Sembler présent geste.', NULL, '2022-08-12', 15, 'https://www.valette.fr/');
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (17, 46, 1);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (18, 'Chiffre recevoir prière foi fonction écrire quel.', NULL, '2022-07-06', 11, NULL);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (18, 9, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (18, 19, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (18, 40, 3);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (19, 'Partie dormir île un satisfaire.', NULL, '2024-06-09', 18, 'http://www.bouvier.net/');
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (19, 39, 1);
INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES (20, 'Sien tellement chaud changer faute.', NULL, '2022-07-29', 4, NULL);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (20, 82, 1);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (20, 96, 2);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (20, 55, 3);
INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES (20, 61, 4);
SELECT setval(pg_get_serial_sequence('univ_recherche.publication','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.publication),0));
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (1, 1, 88, 'Doctorant', '2022-07-30', '2027-04-03', 49.68, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (2, 1, 76, 'Technicien', '2022-09-28', NULL, 72.21, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (3, 1, 7, 'Technicien', '2025-09-14', NULL, 49.83, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (4, 1, 71, 'Technicien', '2025-02-07', NULL, 52.56, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (5, 1, 49, 'PostDoc', '2022-09-11', '2028-03-27', 66.27, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (6, 2, 71, 'PostDoc', '2022-03-22', NULL, 25.63, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (7, 2, 41, 'Doctorant', '2021-10-27', '2027-01-24', 85.86, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (8, 2, 52, 'PostDoc', '2023-01-24', NULL, 63.81, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (9, 2, 99, 'PostDoc', '2025-07-15', '2027-01-01', 93.61, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (10, 2, 50, 'PostDoc', '2021-09-19', NULL, 31.06, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (11, 2, 94, 'Technicien', '2024-07-27', '2028-03-05', 18.21, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (12, 3, 38, 'PostDoc', '2024-12-12', NULL, 43.95, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (13, 3, 97, 'PostDoc', '2025-01-29', NULL, 14.62, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (14, 3, 74, 'Technicien', '2021-09-22', '2028-02-27', 70.11, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (15, 3, 54, 'Technicien', '2022-11-29', '2028-04-07', 70.81, true);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (16, 4, 75, 'Doctorant', '2020-11-21', '2028-04-05', 53.45, true);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (17, 4, 82, 'PostDoc', '2024-10-12', NULL, 11.14, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (18, 4, 100, 'Technicien', '2025-06-13', NULL, 32.03, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (19, 4, 4, 'Technicien', '2022-08-10', '2023-10-13', 30.65, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (20, 4, 85, 'Technicien', '2025-05-28', NULL, 44.6, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (21, 4, 10, 'Technicien', '2025-03-21', NULL, 65.06, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (22, 5, 99, 'Doctorant', '2025-03-17', '2026-09-28', 13.58, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (23, 5, 7, 'Technicien', '2024-06-21', '2026-10-25', 25.41, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (24, 5, 86, 'Technicien', '2022-10-19', '2028-07-18', 21.2, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (25, 5, 78, 'PostDoc', '2021-05-15', '2023-03-12', 65.42, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (26, 5, 91, 'Technicien', '2022-03-31', '2025-08-06', 38.39, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (27, 5, 55, 'Technicien', '2024-10-24', '2026-10-11', 74.4, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (28, 6, 14, 'Investigateur', '2023-09-25', '2024-05-12', 45.37, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (29, 6, 29, 'Investigateur', '2024-09-30', NULL, 57.79, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (30, 6, 25, 'PostDoc', '2024-05-08', NULL, 17.04, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (31, 6, 67, 'PostDoc', '2022-06-30', NULL, 38.95, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (32, 6, 17, 'Doctorant', '2025-05-02', '2026-02-08', 96.84, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (33, 7, 61, 'PostDoc', '2021-07-03', NULL, 78.99, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (34, 7, 62, 'Doctorant', '2023-10-21', NULL, 46.17, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (35, 7, 75, 'Doctorant', '2023-12-13', '2026-03-20', 26.37, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (36, 7, 2, 'Doctorant', '2024-09-28', NULL, 47.65, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (37, 8, 13, 'PostDoc', '2023-06-25', '2027-02-13', 12.71, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (38, 8, 43, 'PostDoc', '2023-05-11', '2027-09-21', 75.02, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (39, 8, 77, 'PostDoc', '2021-09-16', NULL, 64.65, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (40, 8, 50, 'Doctorant', '2021-01-05', NULL, 94.38, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (41, 8, 23, 'Technicien', '2025-07-03', NULL, 57.51, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (42, 8, 91, 'Technicien', '2025-08-11', '2025-09-06', 37.13, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (43, 9, 43, 'Investigateur', '2022-05-10', NULL, 43.37, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (44, 10, 51, 'Technicien', '2025-09-04', '2027-10-18', 22.1, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (45, 10, 82, 'PostDoc', '2021-01-17', '2026-04-30', 47.8, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (46, 11, 58, 'PostDoc', '2023-10-10', '2027-07-31', 97.19, true);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (47, 11, 40, 'PostDoc', '2022-03-27', NULL, 15.96, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (48, 12, 59, 'Technicien', '2022-09-13', '2023-12-26', 45.14, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (49, 13, 14, 'Investigateur', '2024-04-07', '2026-09-30', 59.59, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (50, 13, 59, 'PostDoc', '2023-08-15', NULL, 20.46, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (51, 13, 29, 'Doctorant', '2023-03-29', '2026-05-20', 61.16, true);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (52, 14, 16, 'Investigateur', '2021-09-21', '2022-12-21', 80.24, true);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (53, 14, 75, 'Technicien', '2023-08-27', NULL, 69.95, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (54, 14, 97, 'Technicien', '2022-03-18', '2024-10-13', 30.27, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (55, 15, 89, 'Technicien', '2023-07-18', NULL, 16.7, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (56, 15, 92, 'Investigateur', '2023-12-11', NULL, 41.29, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (57, 15, 98, 'Doctorant', '2024-04-05', NULL, 65.1, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (58, 15, 93, 'PostDoc', '2025-07-28', NULL, 65.83, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (59, 15, 14, 'Investigateur', '2024-02-13', '2028-06-28', 30.83, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (60, 16, 100, 'Technicien', '2023-10-14', NULL, 35.88, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (61, 16, 88, 'Technicien', '2020-11-22', NULL, 16.69, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (62, 16, 87, 'Technicien', '2022-07-16', '2024-05-06', 61.45, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (63, 16, 46, 'Technicien', '2022-12-25', NULL, 41.79, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (64, 16, 17, 'PostDoc', '2022-06-12', NULL, 34.49, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (65, 17, 88, 'Technicien', '2023-05-26', NULL, 27.46, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (66, 17, 75, 'Technicien', '2024-11-14', '2027-05-18', 10.26, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (67, 17, 84, 'PostDoc', '2023-07-06', '2026-10-08', 10.25, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (68, 17, 90, 'PostDoc', '2022-01-06', '2027-01-05', 31.43, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (69, 17, 47, 'PostDoc', '2023-12-04', '2026-08-06', 84.79, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (70, 17, 77, 'Technicien', '2023-09-18', '2027-08-31', 54.74, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (71, 18, 83, 'Investigateur', '2023-09-16', '2028-01-28', 40.5, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (72, 18, 87, 'Investigateur', '2021-09-17', NULL, 93.89, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (73, 18, 46, 'Investigateur', '2021-10-02', '2022-10-31', 13.52, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (74, 19, 59, 'PostDoc', '2022-12-23', NULL, 11.96, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (75, 19, 46, 'Technicien', '2023-03-05', '2027-06-06', 82.9, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (76, 20, 21, 'Technicien', '2023-05-26', '2025-11-19', 10.91, false);
INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES (77, 20, 58, 'PostDoc', '2025-01-16', NULL, 81.97, false);
SELECT setval(pg_get_serial_sequence('univ_recherche.projet_chercheur','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.projet_chercheur),0));
COMMIT;
