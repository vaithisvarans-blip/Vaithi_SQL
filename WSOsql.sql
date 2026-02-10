/* =========================================================
   WSO FUNDED LOAN METRICS
   Priority Matching:
   1. LOANX_ID
   2. SECURITY_ID
   3. CUSIP_ID
   ========================================================= */

WITH WSO_LOANX_ID AS (

SELECT
    wsoe.business_date,
    edm.aladdin_id,
    NULLIF(TRIM(wsoe.lead_manager),'') AS lead_manager,
    NULLIF(TRIM(wsoe.deal_sponsor),'') AS deal_sponsor,

    /* Funded OR Contract NULL */
    AVG(CASE
            WHEN TRIM(wsoe.contract_name) NOT IN ('UNFND','Unfunded')
                 OR wsoe.contract_name IS NULL
            THEN wsoe.CONTRACT_BASE_RATE
        END) AS CONTRACT_BASE_RATE,

    AVG(CASE
            WHEN TRIM(wsoe.contract_name) NOT IN ('UNFND','Unfunded')
                 OR wsoe.contract_name IS NULL
            THEN wsoe.CONTRACT_SPREADADJUSTMENT + wsoe.CONTRACT_SPREAD
        END) AS CONTRACT_SPREAD,

    MAX(CASE
            WHEN TRIM(wsoe.contract_name) IN ('UNFND','Unfunded')
            THEN wsoe.COMMITMENT_FEE
        END) AS COMMITMENT_FEE,

    AVG(CASE
            WHEN TRIM(wsoe.contract_name) NOT IN ('UNFND','Unfunded')
                 OR wsoe.contract_name IS NULL
            THEN wsoe.WEIGHTED_AVERAGE_ALL_IN_RATE * 100
        END) AS COUPON_RATE

FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT wsoe

JOIN PROD_STAGING.PUBLIC.EDM_DAILY_SECURITYMASTER edm
    ON wsoe.LOANX_ID = edm.LOANX_ID
    AND wsoe.business_date = edm.business_date

WHERE COALESCE(wsoe.LOANX_ID,'') <> ''

GROUP BY 1,2,3,4
),

/* ========================================================= */

WSO_SECURITY_ID AS (

SELECT
    wsoe.business_date,
    edm.aladdin_id,
    NULLIF(TRIM(wsoe.lead_manager),'') AS lead_manager,
    NULLIF(TRIM(wsoe.deal_sponsor),'') AS deal_sponsor,

    AVG(CASE
            WHEN TRIM(wsoe.contract_name) NOT IN ('UNFND','Unfunded')
                 OR wsoe.contract_name IS NULL
            THEN wsoe.CONTRACT_BASE_RATE
        END) AS CONTRACT_BASE_RATE,

    AVG(CASE
            WHEN TRIM(wsoe.contract_name) NOT IN ('UNFND','Unfunded')
                 OR wsoe.contract_name IS NULL
            THEN wsoe.CONTRACT_SPREADADJUSTMENT + wsoe.CONTRACT_SPREAD
        END) AS CONTRACT_SPREAD,

    MAX(CASE
            WHEN TRIM(wsoe.contract_name) IN ('UNFND','Unfunded')
            THEN wsoe.COMMITMENT_FEE
        END) AS COMMITMENT_FEE,

    AVG(CASE
            WHEN TRIM(wsoe.contract_name) NOT IN ('UNFND','Unfunded')
                 OR wsoe.contract_name IS NULL
            THEN wsoe.WEIGHTED_AVERAGE_ALL_IN_RATE * 100
        END) AS COUPON_RATE

FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT wsoe

JOIN PROD_STAGING.PUBLIC.EDM_DAILY_SECURITYMASTER edm
    ON wsoe.SECURITY_ID = edm.LIN
    AND wsoe.business_date = edm.business_date

WHERE COALESCE(wsoe.SECURITY_ID,'') <> ''

AND NOT EXISTS (
    SELECT 1
    FROM WSO_LOANX_ID l
    WHERE edm.aladdin_id = l.aladdin_id
)

GROUP BY 1,2,3,4
),

/* ========================================================= */

WSO_CUSIP_ID AS (

SELECT
    wsoe.business_date,
    edm.aladdin_id,
    NULLIF(TRIM(wsoe.lead_manager),'') AS lead_manager,
    NULLIF(TRIM(wsoe.deal_sponsor),'') AS deal_sponsor,

    AVG(CASE
            WHEN TRIM(wsoe.contract_name) NOT IN ('UNFND','Unfunded')
                 OR wsoe.contract_name IS NULL
            THEN wsoe.CONTRACT_BASE_RATE
        END) AS CONTRACT_BASE_RATE,

    AVG(CASE
            WHEN TRIM(wsoe.contract_name) NOT IN ('UNFND','Unfunded')
                 OR wsoe.contract_name IS NULL
            THEN wsoe.CONTRACT_SPREADADJUSTMENT + wsoe.CONTRACT_SPREAD
        END) AS CONTRACT_SPREAD,

    MAX(CASE
            WHEN TRIM(wsoe.contract_name) IN ('UNFND','Unfunded')
            THEN wsoe.COMMITMENT_FEE
        END) AS COMMITMENT_FEE,

    AVG(CASE
            WHEN TRIM(wsoe.contract_name) NOT IN ('UNFND','Unfunded')
                 OR wsoe.contract_name IS NULL
            THEN wsoe.WEIGHTED_AVERAGE_ALL_IN_RATE * 100
        END) AS COUPON_RATE

FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT wsoe

JOIN PROD_STAGING.PUBLIC.EDM_DAILY_SECURITYMASTER edm
    ON wsoe.CUSIP_ID = edm.ALADDIN_ID
    AND wsoe.business_date = edm.business_date

WHERE COALESCE(wsoe.CUSIP_ID,'') <> ''

AND NOT EXISTS (
    SELECT 1
    FROM WSO_LOANX_ID l
    WHERE edm.aladdin_id = l.aladdin_id
)

AND NOT EXISTS (
    SELECT 1
    FROM WSO_SECURITY_ID s
    WHERE edm.aladdin_id = s.aladdin_id
)

GROUP BY 1,2,3,4
)

/* =========================================================
   FINAL UNION (Priority Preserved)
   ========================================================= */

SELECT * FROM WSO_LOANX_ID
UNION ALL
SELECT * FROM WSO_SECURITY_ID
UNION ALL
SELECT * FROM WSO_CUSIP_ID;

WITH FINAL_DATA AS (

SELECT * FROM WSO_LOANX_ID
UNION ALL
SELECT * FROM WSO_SECURITY_ID
UNION ALL
SELECT * FROM WSO_CUSIP_ID

)

SELECT *
FROM FINAL_DATA
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY BUSINESS_DATE, ALADDIN_ID
    ORDER BY
        /* Prefer rows having data */
        CASE
            WHEN LEAD_MANAGER IS NULL
             AND DEAL_SPONSOR IS NULL
             AND CONTRACT_BASE_RATE IS NULL
             AND CONTRACT_SPREAD IS NULL
             AND COMMITMENT_FEE IS NULL
             AND COUPON_RATE IS NULL
            THEN 2   -- worst rows
            ELSE 1   -- keep these
        END
) = 1;


