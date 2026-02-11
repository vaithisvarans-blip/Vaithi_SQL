/* ============================================================
   WSO LOAN METRICS – PRODUCTION FIX
   ============================================================
   Business Rules:
   1. Funded contracts only used for rate calculations
   2. Include loans where Manager & Sponsor are NULL
      if all CONTRACT_NAME values are populated
   3. Remove duplicate null-only rows
   4. Maintain existing aggregation logic
   ============================================================ */

WITH BASE_DATA AS (

SELECT
    wsoe.business_date,
    edm.aladdin_id,

    /* Clean empty strings */
    NULLIF(TRIM(wsoe.lead_manager),'') AS lead_manager,
    NULLIF(TRIM(wsoe.deal_sponsor),'') AS deal_sponsor,
    NULLIF(TRIM(wsoe.contract_name),'') AS contract_name,

    wsoe.CONTRACT_BASE_RATE,
    wsoe.CONTRACT_SPREADADJUSTMENT,
    wsoe.CONTRACT_SPREAD,
    wsoe.COMMITMENT_FEE,
    wsoe.WEIGHTED_AVERAGE_ALL_IN_RATE,

    /* Flag loans where contract names are fully populated */
    COUNT_IF(wsoe.contract_name IS NULL)
        OVER (PARTITION BY wsoe.business_date, edm.aladdin_id) 
        AS NULL_CONTRACT_COUNT

FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT wsoe

JOIN PROD_STAGING.PUBLIC.EDM_DAILY_SECURITYMASTER edm
    ON wsoe.LOANX_ID = edm.LOANX_ID
    AND wsoe.business_date = edm.business_date

WHERE COALESCE(wsoe.LOANX_ID,'') <> ''
),

/* ============================================================
   FILTER VALID LOANS
   ============================================================ */

FILTERED_DATA AS (

SELECT *
FROM BASE_DATA

WHERE
(
    /* Keep if manager or sponsor exists */
    COALESCE(lead_manager, deal_sponsor) IS NOT NULL

    /* OR include loans where all contract names exist */
    OR NULL_CONTRACT_COUNT = 0
)
),

/* ============================================================
   AGGREGATE FUNDED METRICS
   ============================================================ */

AGG_DATA AS (

SELECT
    business_date,
    aladdin_id,
    lead_manager,
    deal_sponsor,

    /* Funded Only */
    AVG(
        CASE
            WHEN contract_name NOT IN ('UNFND','Unfunded')
            THEN CONTRACT_BASE_RATE
        END
    ) AS CONTRACT_BASE_RATE,

    AVG(
        CASE
            WHEN contract_name NOT IN ('UNFND','Unfunded')
            THEN CONTRACT_SPREADADJUSTMENT + CONTRACT_SPREAD
        END
    ) AS CONTRACT_SPREAD,

    MAX(
        CASE
            WHEN contract_name IN ('UNFND','Unfunded')
            THEN COMMITMENT_FEE
        END
    ) AS COMMITMENT_FEE,

    AVG(
        CASE
            WHEN contract_name NOT IN ('UNFND','Unfunded')
            THEN WEIGHTED_AVERAGE_ALL_IN_RATE * 100
        END
    ) AS COUPON_RATE

FROM FILTERED_DATA
GROUP BY 1,2,3,4
)

/* ============================================================
   REMOVE DUPLICATE NULL RECORDS
   ============================================================ */

SELECT *
FROM AGG_DATA

QUALIFY ROW_NUMBER() OVER (
    PARTITION BY business_date, aladdin_id
    ORDER BY
        CASE
            WHEN lead_manager IS NULL
             AND deal_sponsor IS NULL
             AND CONTRACT_BASE_RATE IS NULL
             AND CONTRACT_SPREAD IS NULL
             AND COMMITMENT_FEE IS NULL
             AND COUPON_RATE IS NULL
            THEN 2
            ELSE 1
        END
) = 1;
