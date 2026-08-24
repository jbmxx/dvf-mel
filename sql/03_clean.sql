-- Quality filters. Each step is cumulative; see docs/filter_log.md for counts.
-- Bounds are set on domain reasoning rather than percentiles:
--   9 m²      legal minimum surface for a habitable dwelling in France
--   400 m²    above this, single-dwelling assumption breaks down
--   500 €/m²  below any plausible market transaction in the MEL
--   15,000 €/m²  well above prime Vieux-Lille (6,000–7,000 €/m²)

CREATE OR REPLACE TABLE ventes_propres AS
SELECT
    id_mutation, code_insee, date_mutation, annee,
    CASE type_bien WHEN '1' THEN 'Maison' WHEN '2' THEN 'Appartement' END AS type_bien,
    valeur, surface_bati, nb_pieces, n_dependances,
    valeur / surface_bati AS prix_m2
FROM mutations_mel
WHERE nature = 'Vente'
  AND valeur IS NOT NULL
  AND n_bati = 1          -- exactly one built property: price is attributable
  AND n_commercial = 0
  AND surface_bati > 0
  AND valeur >= 10000;    -- removes €1 transfers, disguised gifts

CREATE OR REPLACE TABLE ventes_finales AS
SELECT * FROM ventes_propres
WHERE surface_bati BETWEEN 9 AND 400
  AND prix_m2 BETWEEN 500 AND 15000;