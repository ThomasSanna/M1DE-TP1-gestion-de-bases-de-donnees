-- SCHEMA AVANCÉ - Gestion des données de recherche (Université)
-- Base: PostgreSQL
-- Date: 2025-11-04
-- Authors: Sanna Thomas, Furfaro Thomas, Chêne Arlette

-- PARTIE 3 - GESTION DES UTILISATEURS ET CRÉATION DE VUES

-- 3.1. CRÉATION DES RÔLES

-- Rôle : Chercheur
CREATE ROLE role_chercheur;

-- Rôle : Data Manager
CREATE ROLE role_data_manager;

-- Rôle : Administrateur
CREATE ROLE role_administrateur;

-- 3.2. CRÉATION DES VUES

-- Vue 1 : Projets d'un chercheur (pour role_chercheur)
-- Permet à un chercheur de voir uniquement les projets auxquels il participe
CREATE OR REPLACE VIEW v_mes_projets AS
SELECT 
    p.id AS projet_id,
    p.titre,
    p.discipline,
    p.date_debut,
    p.date_fin,
    p.budget_annuel_eur,
    l.nom AS laboratoire,
    CONCAT(resp.prenom, ' ', resp.nom) AS responsable,
    pc.role AS mon_role,
    pc.charge_pct
FROM projet p
JOIN laboratoire l ON p.id_laboratoire_pilote = l.id
JOIN projet_chercheur pc ON p.id = pc.id_projet
LEFT JOIN chercheur resp ON p.id_chercheur_responsable = resp.id
WHERE pc.id_chercheur = (SELECT id FROM chercheur WHERE email = current_user);

-- Vue 2 : Données d'un chercheur (pour role_chercheur)
-- Permet à un chercheur de voir ses jeux de données
CREATE OR REPLACE VIEW v_mes_donnees AS
SELECT 
    jd.id AS dataset_id,
    jd.description,
    jd.licence,
    jd.date_depot,
    jd.conditions_acces,
    jd.url_externe,
    ct.intitule AS contrat,
    ct.statut_dmp,
    p.titre AS projet
FROM jeu_donnees jd
JOIN contrat ct ON jd.id_contrat = ct.id
JOIN projet p ON ct.id_projet = p.id
WHERE jd.id_auteur = (SELECT id FROM chercheur WHERE email = current_user);

-- Vue 3 : Métadonnées complètes des contrats (pour role_data_manager)
-- Vue élargie pour les gestionnaires de données
CREATE OR REPLACE VIEW v_metadonnees_contrats AS
SELECT 
    ct.id AS contrat_id,
    ct.intitule,
    ct.type_contrat,
    ct.financeur,
    ct.montant_eur,
    ct.date_debut,
    ct.date_fin,
    ct.statut_dmp,
    ct.date_validation_dmp,
    ct.url_document_dmp,
    p.titre AS projet,
    p.discipline,
    l.nom AS laboratoire,
    i.nom AS institution,
    COUNT(jd.id) AS nb_jeux_donnees,
    COUNT(CASE WHEN jd.date_depot IS NOT NULL THEN 1 END) AS nb_jeux_deposes
FROM contrat ct
JOIN projet p ON ct.id_projet = p.id
JOIN laboratoire l ON p.id_laboratoire_pilote = l.id
JOIN institution i ON l.id_institution = i.id
LEFT JOIN jeu_donnees jd ON ct.id = jd.id_contrat
GROUP BY ct.id, ct.intitule, ct.type_contrat, ct.financeur, ct.montant_eur, 
         ct.date_debut, ct.date_fin, ct.statut_dmp, ct.date_validation_dmp, 
         ct.url_document_dmp, p.titre, p.discipline, l.nom, i.nom;

-- Vue 4 : Synthèse des jeux de données par projet (pour role_data_manager)
CREATE OR REPLACE VIEW v_synthese_donnees_projet AS
SELECT 
    p.id AS projet_id,
    p.titre AS projet,
    p.discipline,
    l.nom AS laboratoire,
    COUNT(DISTINCT jd.id) AS nb_total_datasets,
    COUNT(DISTINCT CASE WHEN jd.date_depot IS NOT NULL THEN jd.id END) AS nb_datasets_deposes,
    COUNT(DISTINCT CASE WHEN jd.licence IS NULL OR jd.date_depot IS NULL THEN jd.id END) AS nb_datasets_non_conformes,
    COUNT(DISTINCT ct.id) AS nb_contrats,
    COUNT(DISTINCT CASE WHEN ct.statut_dmp = 'valide' THEN ct.id END) AS nb_dmp_valides
FROM projet p
JOIN laboratoire l ON p.id_laboratoire_pilote = l.id
LEFT JOIN contrat ct ON p.id = ct.id_projet
LEFT JOIN jeu_donnees jd ON ct.id = jd.id_contrat
GROUP BY p.id, p.titre, p.discipline, l.nom;

-- Vue 5 : Publications par chercheur (pour tous les rôles)
CREATE OR REPLACE VIEW v_publications_chercheur AS
SELECT 
    c.id AS chercheur_id,
    CONCAT(c.prenom, ' ', c.nom) AS chercheur,
    c.email,
    l.nom AS laboratoire,
    COUNT(pa.id_publication) AS nb_publications,
    STRING_AGG(pub.titre, ' | ' ORDER BY pub.date_publication DESC) AS titres_publications
FROM chercheur c
JOIN laboratoire l ON c.id_laboratoire = l.id
LEFT JOIN publication_auteur pa ON c.id = pa.id_chercheur
LEFT JOIN publication pub ON pa.id_publication = pub.id
GROUP BY c.id, c.prenom, c.nom, c.email, l.nom;

-- Vue 6 : Tableau de bord projets (pour role_administrateur et role_data_manager)
CREATE OR REPLACE VIEW v_tableau_bord_projets AS
SELECT 
    p.id AS projet_id,
    p.titre,
    p.discipline,
    p.budget_annuel_eur,
    p.date_debut,
    p.date_fin,
    CASE 
        WHEN p.date_fin IS NULL OR p.date_fin >= CURRENT_DATE THEN 'En cours'
        ELSE 'Terminé'
    END AS statut,
    l.nom AS laboratoire,
    i.nom AS institution,
    CONCAT(resp.prenom, ' ', resp.nom) AS responsable,
    COUNT(DISTINCT pc.id_chercheur) AS nb_chercheurs,
    COUNT(DISTINCT ct.id) AS nb_contrats,
    COALESCE(SUM(ct.montant_eur), 0) AS financement_total_eur,
    COUNT(DISTINCT jd.id) AS nb_jeux_donnees,
    COUNT(DISTINCT pa.id_publication) AS nb_publications
FROM projet p
JOIN laboratoire l ON p.id_laboratoire_pilote = l.id
JOIN institution i ON l.id_institution = i.id
LEFT JOIN chercheur resp ON p.id_chercheur_responsable = resp.id
LEFT JOIN projet_chercheur pc ON p.id = pc.id_projet
LEFT JOIN contrat ct ON p.id = ct.id_projet
LEFT JOIN jeu_donnees jd ON ct.id = jd.id_contrat
LEFT JOIN publication_auteur pa ON pc.id_chercheur = pa.id_chercheur
GROUP BY p.id, p.titre, p.discipline, p.budget_annuel_eur, p.date_debut, p.date_fin,
         l.nom, i.nom, resp.prenom, resp.nom;

-- 3.3. ATTRIBUTION DES PRIVILÈGES

-- Privilèges pour ADMINISTRATEUR (accès complet)
GRANT USAGE ON SCHEMA univ_recherche TO role_administrateur;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA univ_recherche TO role_administrateur;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA univ_recherche TO role_administrateur;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA univ_recherche TO role_administrateur;

-- Privilèges pour DATA_MANAGER (accès élargi aux métadonnées)
GRANT USAGE ON SCHEMA univ_recherche TO role_data_manager;
GRANT SELECT ON ALL TABLES IN SCHEMA univ_recherche TO role_data_manager;
GRANT INSERT, UPDATE, DELETE ON contrat, jeu_donnees TO role_data_manager;
GRANT SELECT ON v_metadonnees_contrats, v_synthese_donnees_projet, v_tableau_bord_projets TO role_data_manager;
GRANT SELECT ON v_publications_chercheur TO role_data_manager;

-- Privilèges pour CHERCHEUR (accès restreint à ses projets et données)
GRANT USAGE ON SCHEMA univ_recherche TO role_chercheur;
GRANT SELECT ON projet, chercheur, laboratoire, institution, publication TO role_chercheur;
GRANT SELECT ON v_mes_projets, v_mes_donnees, v_publications_chercheur TO role_chercheur;
GRANT INSERT ON publication, publication_auteur, jeu_donnees TO role_chercheur;
GRANT UPDATE ON jeu_donnees TO role_chercheur;

-- 3.4. CRÉATION D'UN USER DATA_MANAGER et D'UN USER CHERCHEUR (EXEMPLES)
-- Exemple de création d'un utilisateur Data Manager
CREATE USER data_manager_user WITH PASSWORD 'motdepasse';
GRANT role_data_manager TO data_manager_user;

-- Exemple de création d'un utilisateur Chercheur
CREATE USER "alexandrie.parent@dos.org" WITH PASSWORD 'motdepasse';
GRANT role_chercheur TO "alexandrie.parent@dos.org";

-- PARTIE 4 - REQUÊTES ET OPTIMISATION

-- 4.1. INDEX D'OPTIMISATION POUR LES REQUÊTES

-- Index pour R1 : Nombre de jeux de données par projet et année
-- Optimise les requêtes sur date_depot et date_creation (si elle existe)
CREATE INDEX IF NOT EXISTS idx_jeu_donnees_date_depot ON jeu_donnees(date_depot);
CREATE INDEX IF NOT EXISTS idx_jeu_donnees_date_creation ON jeu_donnees(date_creation);
CREATE INDEX IF NOT EXISTS idx_jeu_donnees_contrat ON jeu_donnees(id_contrat);
CREATE INDEX IF NOT EXISTS idx_contrat_projet ON contrat(id_projet);

-- Index pour améliorer les jointures projet-chercheur
CREATE INDEX IF NOT EXISTS idx_projet_chercheur_projet ON projet_chercheur(id_projet);
CREATE INDEX IF NOT EXISTS idx_projet_chercheur_chercheur ON projet_chercheur(id_chercheur);

-- Index pour R2 : Publications par chercheur et laboratoire
CREATE INDEX IF NOT EXISTS idx_publication_date_publication ON publication(date_publication);
CREATE INDEX IF NOT EXISTS idx_publication_auteur_chercheur ON publication_auteur(id_chercheur);
CREATE INDEX IF NOT EXISTS idx_publication_auteur_publication ON publication_auteur(id_publication);
CREATE INDEX IF NOT EXISTS idx_chercheur_laboratoire ON chercheur(id_laboratoire);

-- Index pour R3 : Conformité des jeux de données
-- Index composite pour vérifier licence et date_depot
CREATE INDEX IF NOT EXISTS idx_jeu_donnees_conformite ON jeu_donnees(licence, date_depot);

-- Index sur les dates de projet (pour filtres temporels)
CREATE INDEX IF NOT EXISTS idx_projet_dates ON projet(date_debut, date_fin);

-- Index sur laboratoire-institution (pour jointures fréquentes)
CREATE INDEX IF NOT EXISTS idx_laboratoire_institution ON laboratoire(id_institution);

-- Index sur discipline (pour filtres et groupements)
CREATE INDEX IF NOT EXISTS idx_projet_discipline ON projet(discipline);

-- Index sur statut DMP (pour filtres de conformité)
CREATE INDEX IF NOT EXISTS idx_contrat_statut_dmp ON contrat(statut_dmp);

-- PARTIE 5 - TRIGGERS ET PROCÉDURES STOCKÉES

-- 5.1. TABLE AUXILIAIRE POUR BILAN

-- Table pour stocker les bilans annuels des projets (utilisée par procédure)
CREATE TABLE IF NOT EXISTS bilan_projet (
    id_projet               BIGINT NOT NULL REFERENCES projet(id) ON DELETE CASCADE,
    annee                   INTEGER NOT NULL,
    nb_publications         INTEGER DEFAULT 0,
    nb_datasets_deposes     INTEGER DEFAULT 0,
    date_maj                TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_projet, annee)
);

-- Table pour archiver les contrats échus
CREATE TABLE IF NOT EXISTS contrat_archive (
    id                      BIGINT PRIMARY KEY,
    type_contrat            type_contrat NOT NULL,
    financeur               TEXT NOT NULL,
    intitule                TEXT NOT NULL,
    montant_eur             NUMERIC(14,2) NOT NULL,
    duree_mois              INTEGER,
    date_debut              DATE NOT NULL,
    date_fin                DATE NOT NULL,
    id_projet               BIGINT NOT NULL,
    statut_dmp              statut_dmp NOT NULL,
    date_validation_dmp     DATE,
    url_document_dmp        TEXT,
    date_archivage          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table pour archiver les jeux de données associés aux contrats archivés
CREATE TABLE IF NOT EXISTS jeu_donnees_archive (
    id                      BIGINT PRIMARY KEY,
    description             TEXT NOT NULL,
    licence                 TEXT,
    date_creation           DATE,
    date_depot              DATE,
    conditions_acces        TEXT,
    url_externe             TEXT,
    id_contrat              BIGINT NOT NULL REFERENCES contrat_archive(id) ON DELETE CASCADE,
    id_auteur               BIGINT NOT NULL,
    date_archivage          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Ajouter une colonne capacite_max_participants à la table projet si elle n'existe pas
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'univ_recherche' 
        AND table_name = 'projet' 
        AND column_name = 'capacite_max_participants'
    ) THEN
        ALTER TABLE projet ADD COLUMN capacite_max_participants INTEGER CHECK (capacite_max_participants > 0);
    END IF;
END $$;

-- 5.2. TRIGGERS

-- TRIGGER 1 : Limite de participants à un projet
-- Vérifie que la capacité maximale de participants n'est pas dépassée
CREATE OR REPLACE FUNCTION verifier_capacite_participants()
RETURNS TRIGGER AS $$
DECLARE
    v_capacite_max INTEGER;
    v_nb_participants_actuel INTEGER;
BEGIN
    -- Récupérer la capacité maximale du projet
    SELECT capacite_max_participants INTO v_capacite_max
    FROM projet WHERE id = NEW.id_projet;
    
    -- Si aucune limite n'est définie, accepter l'insertion
    IF v_capacite_max IS NULL THEN
        RETURN NEW;
    END IF;
    
    -- Compter le nombre actuel de participants (en excluant celui qu'on ajoute si UPDATE)
    IF TG_OP = 'INSERT' THEN
        SELECT COUNT(*) INTO v_nb_participants_actuel
        FROM projet_chercheur
        WHERE id_projet = NEW.id_projet;
    ELSE
        SELECT COUNT(*) INTO v_nb_participants_actuel
        FROM projet_chercheur
        WHERE id_projet = NEW.id_projet AND id <> NEW.id;
    END IF;
    
    -- Vérifier si la capacité est dépassée
    IF v_nb_participants_actuel >= v_capacite_max THEN
        RAISE EXCEPTION 'Capacité maximale de participants (%) dépassée pour le projet ID %', 
            v_capacite_max, NEW.id_projet;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_verifier_capacite_participants
    BEFORE INSERT OR UPDATE ON projet_chercheur
    FOR EACH ROW EXECUTE FUNCTION verifier_capacite_participants();

-- TRIGGER 2 : Vérification DMP d'un jeu de données
-- Empêche le passage en statut "déposé" si le DMP n'est pas validé
CREATE OR REPLACE FUNCTION verifier_dmp_avant_depot()
RETURNS TRIGGER AS $$
DECLARE
    v_statut_dmp statut_dmp;
BEGIN
    -- Si date_depot est NULL, pas de vérification nécessaire
    IF NEW.date_depot IS NULL THEN
        RETURN NEW;
    END IF;
    
    -- Récupérer le statut DMP du contrat associé
    SELECT statut_dmp INTO v_statut_dmp
    FROM contrat WHERE id = NEW.id_contrat;
    
    -- Vérifier que le DMP est validé
    IF v_statut_dmp <> 'valide' THEN
        RAISE EXCEPTION 'Impossible de déposer le jeu de données : le DMP du contrat (ID %) n''est pas validé (statut actuel : %)', 
            NEW.id_contrat, v_statut_dmp;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_verifier_dmp_avant_depot
    BEFORE INSERT OR UPDATE OF date_depot ON jeu_donnees
    FOR EACH ROW EXECUTE FUNCTION verifier_dmp_avant_depot();

-- 5.3. FONCTIONS ET PROCÉDURES STOCKÉES

-- FONCTION 1 : Nombre de publications d'un projet
-- Calcule et renvoie le nombre de publications pour un projet et une année donnés
CREATE OR REPLACE FUNCTION nb_publications_projet(
    p_id_projet BIGINT,      -- ID du projet concerné
    p_annee INTEGER          -- Année de publication à considérer
) RETURNS INTEGER AS $$
DECLARE
    v_nb_publications INTEGER;
BEGIN
    -- Compter les publications des chercheurs du projet pour l'année donnée
    SELECT COUNT(DISTINCT pub.id) INTO v_nb_publications
    FROM projet_chercheur pc
    JOIN publication_auteur pa ON pc.id_chercheur = pa.id_chercheur
    JOIN publication pub ON pa.id_publication = pub.id
    WHERE pc.id_projet = p_id_projet
      AND EXTRACT(YEAR FROM pub.date_publication) = p_annee;
    
    RETURN COALESCE(v_nb_publications, 0);
END;
$$ LANGUAGE plpgsql;

-- PROCÉDURE 2 : Préparation du bilan d'un projet
-- Met à jour la table bilan_projet avec le nombre de publications et datasets pour une année
CREATE OR REPLACE PROCEDURE preparer_bilan_projets(
    p_annee INTEGER          -- Année pour laquelle préparer le bilan
) AS $$
DECLARE
    v_projet RECORD;
    v_nb_publications INTEGER;
    v_nb_datasets INTEGER;
BEGIN
    -- Parcourir tous les projets
    FOR v_projet IN SELECT id FROM projet LOOP
        
        -- Calculer le nombre de publications pour l'année
        SELECT COUNT(DISTINCT pub.id) INTO v_nb_publications
        FROM projet_chercheur pc
        JOIN publication_auteur pa ON pc.id_chercheur = pa.id_chercheur
        JOIN publication pub ON pa.id_publication = pub.id
        WHERE pc.id_projet = v_projet.id
          AND EXTRACT(YEAR FROM pub.date_publication) = p_annee;
        
        -- Calculer le nombre de datasets déposés pour l'année
        SELECT COUNT(DISTINCT jd.id) INTO v_nb_datasets
        FROM contrat ct
        JOIN jeu_donnees jd ON ct.id = jd.id_contrat
        WHERE ct.id_projet = v_projet.id
          AND EXTRACT(YEAR FROM jd.date_depot) = p_annee
          AND jd.date_depot IS NOT NULL;
        
        -- Insérer ou mettre à jour le bilan
        INSERT INTO bilan_projet (id_projet, annee, nb_publications, nb_datasets_deposes, date_maj)
        VALUES (v_projet.id, p_annee, COALESCE(v_nb_publications, 0), COALESCE(v_nb_datasets, 0), CURRENT_TIMESTAMP)
        ON CONFLICT (id_projet, annee) 
        DO UPDATE SET 
            nb_publications = COALESCE(v_nb_publications, 0),
            nb_datasets_deposes = COALESCE(v_nb_datasets, 0),
            date_maj = CURRENT_TIMESTAMP;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- FONCTION 3 : Fiche projet
-- Renvoie un récapitulatif avec les publications et datasets d'un projet
CREATE OR REPLACE FUNCTION fiche_projet(
    p_id_projet BIGINT       -- ID du projet concerné
) RETURNS TABLE (
    type_element TEXT,
    annee INTEGER,
    titre_ou_description TEXT,
    doi_ou_statut TEXT,
    url TEXT
) AS $$
BEGIN
    -- Retourner les publications associées au projet
    RETURN QUERY
    SELECT 
        'Publication'::TEXT AS type_element,
        EXTRACT(YEAR FROM pub.date_publication)::INTEGER AS annee,
        pub.titre AS titre_ou_description,
        COALESCE(pub.doi, 'N/A') AS doi_ou_statut,
        pub.url_externe AS url
    FROM projet_chercheur pc
    JOIN publication_auteur pa ON pc.id_chercheur = pa.id_chercheur
    JOIN publication pub ON pa.id_publication = pub.id
    WHERE pc.id_projet = p_id_projet
    
    UNION ALL
    
    -- Retourner les jeux de données associées au projet
    SELECT 
        'Dataset'::TEXT AS type_element,
        EXTRACT(YEAR FROM jd.date_depot)::INTEGER AS annee,
        jd.description AS titre_ou_description,
        CASE 
            WHEN jd.date_depot IS NOT NULL THEN 'Déposé'
            ELSE 'Non déposé'
        END AS doi_ou_statut,
        jd.url_externe AS url
    FROM contrat ct
    JOIN jeu_donnees jd ON ct.id = jd.id_contrat
    WHERE ct.id_projet = p_id_projet
    
    ORDER BY type_element, annee DESC NULLS LAST;
END;
$$ LANGUAGE plpgsql;

-- PROCÉDURE 4 : Archivage des contrats échus
-- Déplace les contrats dont la date de fin est antérieure à une date seuil vers la table d'archives
-- Archive également les jeux de données associés pour maintenir l'intégrité des données
CREATE OR REPLACE PROCEDURE archiver_contrats_echus(
    p_date_seuil DATE        -- Date seuil : les contrats terminés avant cette date seront archivés
) AS $$
DECLARE
    v_nb_archives_contrats INTEGER;
    v_nb_archives_jeux_donnees INTEGER;
BEGIN
    -- 1. Archiver les contrats échus EN PREMIER (car jeu_donnees_archive référence contrat_archive)
    INSERT INTO contrat_archive (
        id, type_contrat, financeur, intitule, montant_eur, duree_mois,
        date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, 
        url_document_dmp, date_archivage
    )
    SELECT 
        id, type_contrat, financeur, intitule, montant_eur, duree_mois,
        date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, 
        url_document_dmp, CURRENT_TIMESTAMP
    FROM contrat
    WHERE date_fin < p_date_seuil
      AND id NOT IN (SELECT id FROM contrat_archive);
    
    GET DIAGNOSTICS v_nb_archives_contrats = ROW_COUNT;
    
    -- 2. Archiver les jeux de données associés aux contrats archivés
    INSERT INTO jeu_donnees_archive (
        id, description, licence, date_creation, date_depot, conditions_acces, 
        url_externe, id_contrat, id_auteur, date_archivage
    )
    SELECT 
        jd.id, jd.description, jd.licence, jd.date_creation, jd.date_depot, jd.conditions_acces,
        jd.url_externe, jd.id_contrat, jd.id_auteur, CURRENT_TIMESTAMP
    FROM jeu_donnees jd
    WHERE jd.id_contrat IN (SELECT id FROM contrat_archive)
      AND jd.id NOT IN (SELECT id FROM jeu_donnees_archive);
    
    GET DIAGNOSTICS v_nb_archives_jeux_donnees = ROW_COUNT;
    
    -- 3. Supprimer les jeux de données archivés de la table principale
    DELETE FROM jeu_donnees
    WHERE id IN (SELECT id FROM jeu_donnees_archive);
    
    -- 4. Supprimer les contrats archivés de la table principale
    DELETE FROM contrat
    WHERE date_fin < p_date_seuil
      AND id IN (SELECT id FROM contrat_archive);
    
    RAISE NOTICE '% contrat(s) et % jeu(x) de données archivé(s) avec succès', 
        v_nb_archives_contrats, v_nb_archives_jeux_donnees;
END;
$$ LANGUAGE plpgsql;