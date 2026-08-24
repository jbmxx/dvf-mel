-- Deliverable: median €/m² by commune × property type × year.
-- Median, never mean: property prices are strongly right-skewed and DVF
-- retains structural outliers that no filter removes cleanly.
-- Cells under 10 sales are flagged, not deleted — a missing cell in a
-- dashboard reads as a bug, a flagged one reads as a documented limitation.

CREATE OR REPLACE TABLE prix_m2_median AS
SELECT
    v.code_insee,
    m.nom_commune,
    v.annee,
    v.type_bien,
    count(*) AS n_ventes,
    round(median(v.prix_m2))     AS prix_m2_median,
    round(median(v.valeur))      AS prix_median,
    round(median(v.surface_bati)) AS surface_mediane,
    count(*) >= 10 AS fiable
FROM ventes_finales v
JOIN communes_mel m ON v.code_insee = m.code_insee
GROUP BY 1, 2, 3, 4;