SELECT
    wsoe.business_date,
    edm.aladdin_id,
    NULLIF(TRIM(wsoe.lead_manager),'')  AS lead_manager,
    NULLIF(TRIM(wsoe.deal_sponsor),'')  AS deal_sponsor,

    /* Base Rate - Funded OR Contract NULL */
    AVG(
        CASE 
            WHEN TRIM(CONTRACT_NAME) NOT IN ('UNFND','Unfunded')
                 OR CONTRACT_NAME IS NULL
            THEN CONTRACT_BASE_RATE 
        END
    ) AS CONTRACT_BASE_RATE,

    /* Spread */
    AVG(
        CASE 
            WHEN TRIM(CONTRACT_NAME) NOT IN ('UNFND','Unfunded')
                 OR CONTRACT_NAME IS NULL
            THEN (wsoe.CONTRACT_SPREADADJUSTMENT + wsoe.CONTRACT_SPREAD)
        END
    ) AS CONTRACT_SPREAD,

    /* Commitment Fee - Only Unfunded */
    MAX(
        CASE 
            WHEN TRIM(CONTRACT_NAME) IN ('UNFND','Unfunded')
            THEN COMMITMENT_FEE 
        END
    ) AS COMMITMENT_FEE,

    /* Coupon */
    AVG(
        CASE 
            WHEN TRIM(CONTRACT_NAME) NOT IN ('UNFND','Unfunded')
                 OR CONTRACT_NAME IS NULL
            THEN (wsoe.WEIGHTED_AVERAGE_ALL_IN_RATE * 100)
        END
    ) AS COUPON_RATE

FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT wsoe

INNER JOIN PROD_STAGING.PUBLIC.EDM_DAILY_SECURITYMASTER edm
    ON WSOE.LOANX_ID = EDM.LOANX_ID
    AND WSOE.BUSINESS_DATE = EDM.BUSINESS_DATE
    AND COALESCE(WSOE.LOANX_ID,'') <> ''

GROUP BY
    wsoe.business_date,
    edm.aladdin_id,
    NULLIF(TRIM(wsoe.lead_manager),''),
    NULLIF(TRIM(wsoe.deal_sponsor),'');

/*-----------------------------------------------------------------------------------------------------------------*/


WITH BASE AS (
    SELECT
        wsoe.business_date,
        edm.aladdin_id,
        NULLIF(TRIM(wsoe.lead_manager),'') AS lead_manager,
        NULLIF(TRIM(wsoe.deal_sponsor),'') AS deal_sponsor,
        TRIM(wsoe.contract_name) AS contract_name,
        wsoe.*
    FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT wsoe
    JOIN PROD_STAGING.PUBLIC.EDM_DAILY_SECURITYMASTER edm
        ON wsoe.business_date = edm.business_date
),

/* ---------------- LOANX MATCH ---------------- */

WSO_LOANX_ID AS (
SELECT
    business_date,
    aladdin_id,
    lead_manager,
    deal_sponsor,

    AVG(CASE
            WHEN contract_name NOT IN ('UNFND','Unfunded')
                 OR contract_name IS NULL
            THEN CONTRACT_BASE_RATE
        END) CONTRACT_BASE_RATE,

    AVG(CASE
            WHEN contract_name NOT IN ('UNFND','Unfunded')
                 OR contract_name IS NULL
            THEN CONTRACT_SPREADADJUSTMENT + CONTRACT_SPREAD
        END) CONTRACT_SPREAD,

    MAX(CASE
            WHEN contract_name IN ('UNFND','Unfunded')
            THEN COMMITMENT_FEE
        END) COMMITMENT_FEE,

    AVG(CASE
            WHEN contract_name NOT IN ('UNFND','Unfunded')
                 OR contract_name IS NULL
            THEN WEIGHTED_AVERAGE_ALL_IN_RATE * 100
        END) COUPON_RATE

FROM BASE
WHERE COALESCE(LOANX_ID,'') <> ''
GROUP BY 1,2,3,4
),

/* ---------------- SECURITY MATCH ---------------- */

WSO_SECURITY_ID AS (
SELECT
    b.business_date,
    b.aladdin_id,
    b.lead_manager,
    b.deal_sponsor,

    AVG(CASE
            WHEN contract_name NOT IN ('UNFND','Unfunded')
                 OR contract_name IS NULL
            THEN CONTRACT_BASE_RATE
        END) CONTRACT_BASE_RATE,

    AVG(CASE
            WHEN contract_name NOT IN ('UNFND','Unfunded')
                 OR contract_name IS NULL
            THEN CONTRACT_SPREADADJUSTMENT + CONTRACT_SPREAD
        END) CONTRACT_SPREAD,

    MAX(CASE
            WHEN contract_name IN ('UNFND','Unfunded')
            THEN COMMITMENT_FEE
        END) COMMITMENT_FEE,

    AVG(CASE
            WHEN contract_name NOT IN ('UNFND','Unfunded')
                 OR contract_name IS NULL
            THEN WEIGHTED_AVERAGE_ALL_IN_RATE * 100
        END) COUPON_RATE

FROM BASE b
WHERE COALESCE(SECURITY_ID,'') <> ''
AND NOT EXISTS (
    SELECT 1 FROM WSO_LOANX_ID l
    WHERE b.aladdin_id = l.aladdin_id
)
GROUP BY 1,2,3,4
),

/* ---------------- CUSIP MATCH ---------------- */

WSO_CUSIP_ID AS (
SELECT
    b.business_date,
    b.aladdin_id,
    b.lead_manager,
    b.deal_sponsor,

    AVG(CASE
            WHEN contract_name NOT IN ('UNFND','Unfunded')
                 OR contract_name IS NULL
            THEN CONTRACT_BASE_RATE
        END) CONTRACT_BASE_RATE,

    AVG(CASE
            WHEN contract_name NOT IN ('UNFND','Unfunded')
                 OR contract_name IS NULL
            THEN CONTRACT_SPREADADJUSTMENT + CONTRACT_SPREAD
        END) CONTRACT_SPREAD,

    MAX(CASE
            WHEN contract_name IN ('UNFND','Unfunded')
            THEN COMMITMENT_FEE
        END) COMMITMENT_FEE,

    AVG(CASE
            WHEN contract_name NOT IN ('UNFND','Unfunded')
                 OR contract_name IS NULL
            THEN WEIGHTED_AVERAGE_ALL_IN_RATE * 100
        END) COUPON_RATE

FROM BASE b
WHERE COALESCE(CUSIP_ID,'') <> ''
AND NOT EXISTS (
    SELECT 1 FROM WSO_LOANX_ID l
    WHERE b.aladdin_id = l.aladdin_id
)
AND NOT EXISTS (
    SELECT 1 FROM WSO_SECURITY_ID s
    WHERE b.aladdin_id = s.aladdin_id
)
GROUP BY 1,2,3,4
)
