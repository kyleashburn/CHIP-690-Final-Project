-- First step
-- Pulls all the concept ids we need to care about
WITH icd10_conc AS (
SELECT * 
FROM omop.concept
WHERE concept_code LIKE 'C17.%' OR concept_code LIKE 'C18.%' OR
concept_code LIKE 'C21.%' OR  concept_code = 'Z86.010'
),

-- Second step 
-- Pulling the concepts
-- We want to pull the concept_id_2 for each of these
conc_maps AS (
SELECT concept_id_2
FROM omop.concept_relationship 
WHERE concept_id_1 in (SELECT concept_id FROM icd10_conc) 
AND relationship_id = 'Maps to'
)
,

-- third step -> ensuring all standard concepts
-- ensuring these are all standard concepts
stand_conc as (
SELECT concept_id_2 as cond_conc_id
FROM conc_maps cm
INNER JOIN omop.concept co ON cm.concept_id_2 = co.concept_id
WHERE co.standard_concept = 'S'
),


-- checking to see if they are in the condition occurrence table
canc_pats as (
SELECT DISTINCT co.person_id, co.condition_concept_id, co.condition_source_value
FROM omop.condition_occurrence co
WHERE co.condition_concept_id IN (SELECT * FROM stand_conc)
),

-- checking to see how many deaths we have records for
canc_deaths as (
SELECT * 
FROM omop.death od
WHERE od.person_id IN (SELECT person_id from canc_pats)
),

-- pulling max & min dates for patients -> range of records
-- earliest visit start to latest visit end provides us with visit dif
vis_max_min AS (
SELECT vo.person_id, MIN(vo.visit_start_datetime) AS first_vis, 
MAX(vo.visit_end_datetime) AS last_vis
FROM omop.visit_occurrence vo
WHERE vo.person_id IN (SELECT person_id FROM canc_pats)
GROUP BY vo.person_id
),

-- earliest procedure start to latest procedure end
proc_max_min AS (
SELECT po.person_id, MIN(po.procedure_datetime) AS first_proc , 
MAX(po.procedure_datetime) AS last_proc
FROM omop.procedure_occurrence po
WHERE po.person_id IN (SELECT person_id FROM canc_pats)
GROUP BY po.person_id
),
	
-- earliest drug exposure start to latest drug exposure end
drug_max_min AS (
SELECT de.person_id, MIN(drug_exposure_start_datetime) AS first_drug,
MAX(drug_exposure_end_datetime) AS last_drug
FROM omop.drug_exposure de
WHERE de.person_id IN (SELECT person_id FROM canc_pats)
GROUP BY de.person_id
),
	
-- earliest measurement to latest measurement
-- slows the running down though :(
meas_max_min AS (
SELECT om.person_id, MIN(om.measurement_datetime) AS first_meas, 
MAX(om.measurement_datetime) AS last_meas
FROM omop.measurement om
WHERE om.person_id IN (SELECT person_id FROM canc_pats)
GROUP BY om.person_id
),

-- no device exposures so we can just ignore that...

-- pulling the first and last datapoint date for each of the patients
num_years as (
SELECT cp.person_id, ((
	greatest(last_vis, last_proc, last_drug, last_meas)::date -
	least(first_vis, first_proc, first_drug, first_meas)::date)/365.25)
	 AS num_years	
FROM canc_pats cp
INNER JOIN vis_max_min vmm ON cp.person_id = vmm.person_id
INNER JOIN proc_max_min pmm ON cp.person_id = pmm.person_id
INNER JOIN drug_max_min dmm ON cp.person_id = dmm.person_id
INNER JOIN meas_max_min mmm ON cp.person_id = mmm.person_id
),

-- figuring out the start of the dx
dx_date AS (
SELECT person_id, MIN(condition_start_datetime) AS pat_dx_date
FROM omop.condition_occurrence co
WHERE co.person_id IN (SELECT person_id FROM canc_pats) AND
co.condition_concept_id IN (SELECT cond_conc_id FROM stand_conc)
GROUP BY co.person_id
),
	
-- finding the counts of meds for our patients (grouped as a whole) after their diagnosis
-- need to make it grouped on patients though
drug_counts as (
SELECT oc.concept_name, COUNT(de.drug_concept_id)
FROM omop.drug_exposure de
INNER JOIN canc_pats cp ON cp.person_id = de.person_id
INNER JOIN dx_date dd ON dd.person_id = de.person_id
INNER JOIN omop.concept oc ON oc.concept_id = de.drug_concept_id
WHERE de.drug_exposure_start_datetime > dd.pat_dx_date
GROUP BY oc.concept_name
ORDER BY COUNT(de.drug_concept_id) DESC
)

-- trying to find co-morbidities
SELECT oc.concept_name, COUNT(co.condition_concept_id)
FROM omop.condition_occurrence co
INNER JOIN canc_pats cp on co.person_id = cp.person_id 
INNER JOIN omop.concept oc on oc.concept_id = co.condition_concept_id
WHERE co.condition_concept_id not in (SELECT * FROM stand_conc)
GROUP BY oc.concept_name 
ORDER BY COUNT(co.condition_concept_id) DESC
