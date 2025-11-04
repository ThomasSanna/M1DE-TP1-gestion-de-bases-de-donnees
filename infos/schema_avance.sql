-- ============================================================================
-- SCHEMA AVANCÉ SIMPLIFIÉ - Gestion des données de recherche (Université)
-- ============================================================================
-- Base: PostgreSQL
-- 
-- Ce script ajoute à la base existante :
-- 1. Table d'audit pour la traçabilité
-- 2. Index d'optimisation (réduits)
-- 3. Triggers essentiels
-- 4. Procédures stockées principales
-- 5. Vues simplifiées
-- 6. Rôles et privilèges
-- ============================================================================

SET search_path TO univ_recherche;

-- ============================================================================
-- 1. TABLE D'AUDIT / LOGS
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_log (
    id                  BIGSERIAL PRIMARY KEY,
    table_name          TEXT NOT NULL,
    record_id           BIGINT NOT NULL,
    action              TEXT NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    modified_by         TEXT NOT NULL,
    modified_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_table_name ON audit_log(table_name);
CREATE INDEX IF NOT EXISTS idx_audit_modified_at ON audit_log(modified_at DESC);

-- ============================================================================
-- 2. INDEX D'OPTIMISATION
-- ============================================================================

-- Index sur les clés étrangères principales
CREATE INDEX IF NOT EXISTS idx_laboratoire_institution ON laboratoire(id_institution);
CREATE INDEX IF NOT EXISTS idx_projet_laboratoire ON projet(id_laboratoire_pilote);
CREATE INDEX IF NOT EXISTS idx_chercheur_laboratoire ON chercheur(id_laboratoire);
CREATE INDEX IF NOT EXISTS idx_contrat_projet ON contrat(id_projet);
CREATE INDEX IF NOT EXISTS idx_jeu_donnees_contrat ON jeu_donnees(id_contrat);

-- Index sur colonnes fréquemment recherchées
CREATE INDEX IF NOT EXISTS idx_chercheur_email ON chercheur(email);
CREATE INDEX IF NOT EXISTS idx_projet_discipline ON projet(discipline);
CREATE INDEX IF NOT EXISTS idx_contrat_statut_dmp ON contrat(statut_dmp);

-- ============================================================================
-- 3. TRIGGERS
-- ============================================================================

-- Trigger : Validation du dépôt de données (DMP validé requis)
CREATE OR REPLACE FUNCTION verifier_depot_donnees()
RETURNS TRIGGER AS $$
DECLARE
    v_statut_dmp statut_dmp;
BEGIN
    IF NEW.date_depot IS NULL THEN
        RETURN NEW;
    END IF;
    
    SELECT statut_dmp INTO v_statut_dmp
    FROM contrat WHERE id = NEW.id_contrat;
    
    IF v_statut_dmp != 'valide' THEN
        RAISE EXCEPTION 'Le DMP du contrat doit être validé avant le dépôt';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_verifier_depot_donnees
    BEFORE INSERT OR UPDATE OF date_depot ON jeu_donnees
    FOR EACH ROW EXECUTE FUNCTION verifier_depot_donnees();

-- Trigger : Audit automatique
CREATE OR REPLACE FUNCTION audit_modifications()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, record_id, action, modified_by)
        VALUES (TG_TABLE_NAME, OLD.id, 'DELETE', current_user);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, record_id, action, modified_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'UPDATE', current_user);
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, record_id, action, modified_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'INSERT', current_user);
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_projet
    AFTER INSERT OR UPDATE OR DELETE ON projet
    FOR EACH ROW EXECUTE FUNCTION audit_modifications();

CREATE TRIGGER trg_audit_contrat
    AFTER INSERT OR UPDATE OR DELETE ON contrat
    FOR EACH ROW EXECUTE FUNCTION audit_modifications();

-- ============================================================================
-- 4. PROCÉDURES STOCKÉES
-- ============================================================================

-- Déclaration d'un nouveau projet
CREATE OR REPLACE FUNCTION declarer_projet(
    p_titre TEXT,
    p_discipline TEXT,
    p_id_laboratoire_pilote BIGINT,
    p_id_chercheur_responsable BIGINT
) RETURNS BIGINT AS $$
DECLARE
    v_nouveau_projet_id BIGINT;
BEGIN
    INSERT INTO projet (titre, discipline, id_laboratoire_pilote, id_chercheur_responsable, date_debut)
    VALUES (p_titre, p_discipline, p_id_laboratoire_pilote, p_id_chercheur_responsable, CURRENT_DATE)
    RETURNING id INTO v_nouveau_projet_id;
    
    INSERT INTO projet_chercheur (id_projet, id_chercheur, role, date_debut)
    VALUES (v_nouveau_projet_id, p_id_chercheur_responsable, 'Responsable', CURRENT_DATE);
    
    RETURN v_nouveau_projet_id;
END;
$$ LANGUAGE plpgsql;

-- Validation d'un DMP
CREATE OR REPLACE FUNCTION valider_dmp(p_id_contrat BIGINT) RETURNS VOID AS $$
BEGIN
    UPDATE contrat
    SET statut_dmp = 'valide',
        date_validation_dmp = CURRENT_DATE
    WHERE id = p_id_contrat;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 5. VUES
-- ============================================================================

-- Vue : Projets complets
CREATE OR REPLACE VIEW v_projets_complets AS
SELECT 
    p.id AS projet_id,
    p.titre,
    p.discipline,
    l.nom AS laboratoire,
    c.nom || ' ' || c.prenom AS responsable,
    COUNT(DISTINCT pc.id_chercheur) AS nb_chercheurs,
    COUNT(DISTINCT ct.id) AS nb_contrats
FROM projet p
JOIN laboratoire l ON p.id_laboratoire_pilote = l.id
LEFT JOIN chercheur c ON p.id_chercheur_responsable = c.id
LEFT JOIN projet_chercheur pc ON p.id = pc.id_projet
LEFT JOIN contrat ct ON p.id = ct.id_projet
GROUP BY p.id, p.titre, p.discipline, l.nom, c.nom, c.prenom;

-- Vue : Contrats avec statut DMP
CREATE OR REPLACE VIEW v_contrats_dmp AS
SELECT 
    ct.id AS contrat_id,
    ct.intitule,
    ct.statut_dmp,
    ct.date_validation_dmp,
    p.titre AS projet_titre,
    COUNT(jd.id) AS nb_jeux_donnees
FROM contrat ct
JOIN projet p ON ct.id_projet = p.id
LEFT JOIN jeu_donnees jd ON ct.id = jd.id_contrat
GROUP BY ct.id, ct.intitule, ct.statut_dmp, ct.date_validation_dmp, p.titre;

-- ============================================================================
-- 6. RÔLES ET PRIVILÈGES
-- ============================================================================

-- Création des rôles
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_administrateur') THEN
        DROP OWNED BY role_administrateur;
        DROP ROLE role_administrateur;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_data_manager') THEN
        DROP OWNED BY role_data_manager;
        DROP ROLE role_data_manager;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_chercheur') THEN
        DROP OWNED BY role_chercheur;
        DROP ROLE role_chercheur;
    END IF;
END $$;

CREATE ROLE role_administrateur;
CREATE ROLE role_data_manager;
CREATE ROLE role_chercheur;

-- Privilèges ADMINISTRATEUR
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA univ_recherche TO role_administrateur;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA univ_recherche TO role_administrateur;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA univ_recherche TO role_administrateur;

-- Privilèges DATA_MANAGER
GRANT SELECT ON ALL TABLES IN SCHEMA univ_recherche TO role_data_manager;
GRANT INSERT, UPDATE ON contrat, jeu_donnees TO role_data_manager;
GRANT EXECUTE ON FUNCTION valider_dmp(BIGINT) TO role_data_manager;

-- Privilèges CHERCHEUR
GRANT SELECT ON projet, chercheur, contrat, publication TO role_chercheur;
GRANT SELECT ON v_projets_complets, v_contrats_dmp TO role_chercheur;
GRANT EXECUTE ON FUNCTION declarer_projet(TEXT, TEXT, BIGINT, BIGINT) TO role_chercheur;
GRANT INSERT ON jeu_donnees, publication TO role_chercheur;
