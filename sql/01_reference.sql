-- Reference table: the 95 communes of Métropole Européenne de Lille
-- Pulled from the official geo.api.gouv.fr endpoint (EPCI 200093201)
-- so the perimeter is reproducible and not hardcoded.

INSTALL httpfs; LOAD httpfs;
INSTALL json;   LOAD json;

CREATE OR REPLACE TABLE communes_mel AS
SELECT code AS code_insee, nom AS nom_commune
FROM read_json_auto(
  'https://geo.api.gouv.fr/epcis/200093201/communes?fields=nom,code'
);

COPY communes_mel TO 'data/ref/communes_mel.csv' (HEADER, DELIMITER ',');