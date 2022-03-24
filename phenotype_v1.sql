-- this is the first step
-- it pulls all the concept ids we need to care about
WITH icd10_conc AS (
SELECT * 
FROM omop.concept
WHERE concept_code LIKE 'C17.%' OR concept_code LIKE 'C18.%' OR
concept_code LIKE 'C21.%' OR  concept_code = 'Z86.010'
),

-- second step 
-- pulling the standard concepts
-- we want to pull the concept_id_2 for each of these
stand_conc_ids AS (
SELECT concept_id_2
FROM omop.concept_relationship 
WHERE concept_id_1 in (SELECT concept_id FROM icd10_conc) 
AND relationship_id = 'Maps to'
),

-- third step 
-- checking each of these concepts to make sure they're standard
stand_chck AS (
SELECT *
FROM omop.concept
WHERE concept_id IN (SELECT * FROM stand_conc_ids)
)

-- next step, checking to see if they are in the condition occurrence table
SELECT COUNT(DISTINCT co.person_id)
FROM omop.condition_occurrence co
WHERE co.condition_concept_id IN (SELECT * FROM stand_conc_ids);
