-- R1

-- VERSION 1 : Avec sous-requête pour compter les chercheurs
WITH projets_eligibles AS (
    SELECT p.id AS id_projet
    FROM projet p
    JOIN projet_chercheur pc ON p.id = pc.id_projet
    WHERE p.date_debut >= '2018-01-01'
    GROUP BY p.id
    HAVING COUNT(DISTINCT pc.id_chercheur) > 5
)
SELECT 
    p.id AS projet_id,
    p.titre AS projet_titre,
    EXTRACT(YEAR FROM jd.date_depot) AS annee_civile,
    COUNT(jd.id) AS nb_jeux_donnees_deposes,
    ROUND(AVG(jd.date_depot - jd.date_creation), 2) AS delai_moyen_jours
FROM projet p
JOIN contrat ct ON p.id = ct.id_projet
JOIN jeu_donnees jd ON ct.id = jd.id_contrat
WHERE p.id IN (SELECT id_projet FROM projets_eligibles)
  AND jd.date_depot IS NOT NULL
GROUP BY p.id, p.titre, EXTRACT(YEAR FROM jd.date_depot)

-- VERSION 2 : Avec jointure directe et HAVING
SELECT 
    p.id AS projet_id,
    p.titre AS projet_titre,
    EXTRACT(YEAR FROM jd.date_depot) AS annee_civile,
    COUNT(DISTINCT jd.id) AS nb_jeux_donnees_deposes,
    ROUND(AVG(jd.date_depot - jd.date_creation), 2) AS delai_moyen_jours
FROM projet p
JOIN projet_chercheur pc ON p.id = pc.id_projet
JOIN contrat ct ON p.id = ct.id_projet
JOIN jeu_donnees jd ON ct.id = jd.id_contrat
WHERE p.date_debut >= '2018-01-01'
  AND jd.date_depot IS NOT NULL
GROUP BY p.id, p.titre, EXTRACT(YEAR FROM jd.date_depot)
HAVING COUNT(DISTINCT pc.id_chercheur) > 5

-- R2 
-- VERSION 1 : NOT IN
SELECT 
    p.id AS projet_id,
    p.titre AS projet_titre,
    CONCAT(resp.prenom, ' ', resp.nom) AS responsable
FROM projet p
JOIN laboratoire l ON p.id_laboratoire_pilote = l.id
LEFT JOIN chercheur resp ON p.id_chercheur_responsable = resp.id
WHERE l.nom = 'Unleash clicks-and-mortar solutions Lab'
  AND (p.date_debut <= '2024-12-31' 
       AND (p.date_fin IS NULL OR p.date_fin >= '2024-01-01'))
  AND p.id NOT IN (
      SELECT DISTINCT pc.id_projet
      FROM projet_chercheur pc
      JOIN chercheur c ON pc.id_chercheur = c.id
      JOIN laboratoire l2 ON c.id_laboratoire = l2.id
      LEFT JOIN publication_auteur pa ON c.id = pa.id_chercheur
      LEFT JOIN publication pub ON pa.id_publication = pub.id 
          AND EXTRACT(YEAR FROM pub.date_publication) = 2024
      WHERE l2.nom = 'Unleash clicks-and-mortar solutions Lab'
      GROUP BY pc.id_projet, c.id
      HAVING COUNT(DISTINCT pub.id) < (
          -- Moyenne des publications du labo
          SELECT AVG(cnt)
          FROM (
              SELECT COUNT(DISTINCT pub2.id) AS cnt
              FROM chercheur c2
              JOIN laboratoire l3 ON c2.id_laboratoire = l3.id
              LEFT JOIN publication_auteur pa2 ON c2.id = pa2.id_chercheur
              LEFT JOIN publication pub2 ON pa2.id_publication = pub2.id 
                  AND EXTRACT(YEAR FROM pub2.date_publication) = 2024
              WHERE l3.nom = 'Unleash clicks-and-mortar solutions Lab'
              GROUP BY c2.id
          ) AS moyennes
      )
  )


-- VERSION 2 : EXCEPT
SELECT 
    p.id AS projet_id,
    p.titre AS projet_titre,
    CONCAT(resp.prenom, ' ', resp.nom) AS responsable
FROM projet p
JOIN laboratoire l ON p.id_laboratoire_pilote = l.id
LEFT JOIN chercheur resp ON p.id_chercheur_responsable = resp.id
WHERE l.nom = 'Unleash clicks-and-mortar solutions Lab'
  AND (p.date_debut <= '2024-12-31' 
       AND (p.date_fin IS NULL OR p.date_fin >= '2024-01-01'))

EXCEPT

SELECT DISTINCT
    p.id AS projet_id,
    p.titre AS projet_titre,
    CONCAT(resp.prenom, ' ', resp.nom) AS responsable
FROM projet p
JOIN laboratoire l ON p.id_laboratoire_pilote = l.id
LEFT JOIN chercheur resp ON p.id_chercheur_responsable = resp.id
JOIN projet_chercheur pc ON p.id = pc.id_projet
JOIN chercheur c ON pc.id_chercheur = c.id
LEFT JOIN publication_auteur pa ON c.id = pa.id_chercheur
LEFT JOIN publication pub ON pa.id_publication = pub.id 
    AND EXTRACT(YEAR FROM pub.date_publication) = 2024
WHERE l.nom = 'Unleash clicks-and-mortar solutions Lab'
  AND c.id_laboratoire = l.id
GROUP BY p.id, p.titre, resp.prenom, resp.nom, c.id
HAVING COUNT(DISTINCT pub.id) < (
    SELECT AVG(cnt)
    FROM (
        SELECT COUNT(DISTINCT pub2.id) AS cnt
        FROM chercheur c2
        JOIN laboratoire l2 ON c2.id_laboratoire = l2.id
        LEFT JOIN publication_auteur pa2 ON c2.id = pa2.id_chercheur
        LEFT JOIN publication pub2 ON pa2.id_publication = pub2.id 
            AND EXTRACT(YEAR FROM pub2.date_publication) = 2024
        WHERE l2.nom = 'Unleash clicks-and-mortar solutions Lab'
        GROUP BY c2.id
    ) AS stats_labo
)

-- R3 

--VERSION 1 : NOT EXISTS
SELECT 
    l.id AS laboratoire_id,
    l.nom AS laboratoire_nom,
    i.nom AS institution_nom
FROM laboratoire l
JOIN institution i ON l.id_institution = i.id
WHERE NOT EXISTS (
    SELECT 1
    FROM projet p
    JOIN contrat ct ON ct.id_projet = p.id
    JOIN jeu_donnees jd ON ct.id = jd.id_contrat
    WHERE p.id_laboratoire_pilote = l.id
      AND EXTRACT(YEAR FROM COALESCE(jd.date_depot, jd.date_creation)) = 2024
      AND (jd.licence IS NULL OR jd.date_depot IS NULL)
)

-- VERSION 2 : LEFT JOIN

SELECT 
    l.id AS laboratoire_id,
    l.nom AS laboratoire_nom,
    i.nom AS institution_nom
FROM laboratoire l
JOIN institution i ON l.id_institution = i.id
LEFT JOIN projet p ON l.id = p.id_laboratoire_pilote
LEFT JOIN contrat ct ON p.id = ct.id_projet
LEFT JOIN jeu_donnees jd ON ct.id = jd.id_contrat
    AND EXTRACT(YEAR FROM COALESCE(jd.date_depot, jd.date_creation)) = 2024
    AND (jd.licence IS NULL OR jd.date_depot IS NULL)
GROUP BY l.id, l.nom, i.nom
HAVING COUNT(jd.id) = 0
ORDER BY l.nom;