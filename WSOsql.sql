WITH BASE_FILTER AS (
    SELECT *
    FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT
    WHERE NOT (
        COALESCE(TRIM(CONTRACT_NAME),'') = ''
        AND COALESCE(TRIM(LEAD_MANAGER),'') = ''
        AND COALESCE(TRIM(DEAL_SPONSOR),'') = ''
        AND WEIGHTED_AVERAGE_ALL_IN_RATE IS NULL
    )
),

/* ---------------- LOANX ---------------- */
WSO_LOANX_ID AS (
SELECT
    wsoe.business_date,
    edm.aladdin_id,
    wsoe.lead_manager,
    wsoe.deal_sponsor,

    AVG(IFF(TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded'),
            wsoe.CONTRACT_BASE_RATE, NULL)) AS CONTRACT_BASE_RATE,

    AVG(IFF(TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded'),
            (wsoe.CONTRACT_SPREADADJUSTMENT + wsoe.CONTRACT_SPREAD), NULL)) AS CONTRACT_SPREAD,

    MAX(IFF(TRIM(wsoe.CONTRACT_NAME) IN ('UNFND','Unfunded'),
            wsoe.COMMITMENT_FEE, NULL)) AS COMMITMENT_FEE,

    AVG(IFF(TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded'),
            (wsoe.WEIGHTED_AVERAGE_ALL_IN_RATE * 100), NULL)) AS COUPON_RATE

FROM BASE_FILTER wsoe
JOIN PROD_STAGING.PUBLIC.EDM_DAILY_SECURITYMASTER edm
     ON wsoe.LOANX_ID = edm.LOANX_ID
     AND COALESCE(wsoe.LOANX_ID,'') <> ''
     AND wsoe.BUSINESS_DATE = edm.BUSINESS_DATE

GROUP BY 1,2,3,4
),

/* ---------------- SECURITY ---------------- */
WSO_SECURITY_ID AS (
SELECT
    wsoe.business_date,
    edm.aladdin_id,
    wsoe.lead_manager,
    wsoe.deal_sponsor,

    AVG(IFF(TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded'),
            wsoe.CONTRACT_BASE_RATE, NULL)) AS CONTRACT_BASE_RATE,

    AVG(IFF(TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded'),
            (wsoe.CONTRACT_SPREADADJUSTMENT + wsoe.CONTRACT_SPREAD), NULL)) AS CONTRACT_SPREAD,

    MAX(IFF(TRIM(wsoe.CONTRACT_NAME) IN ('UNFND','Unfunded'),
            wsoe.COMMITMENT_FEE, NULL)) AS COMMITMENT_FEE,

    AVG(IFF(TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded'),
            (wsoe.WEIGHTED_AVERAGE_ALL_IN_RATE * 100), NULL)) AS COUPON_RATE

FROM BASE_FILTER wsoe
JOIN PROD_STAGING.PUBLIC.EDM_DAILY_SECURITYMASTER edm
     ON wsoe.SECURITY_ID = edm.LIN
     AND COALESCE(wsoe.SECURITY_ID,'') <> ''
     AND wsoe.BUSINESS_DATE = edm.BUSINESS_DATE

WHERE NOT EXISTS (
      SELECT 1 FROM WSO_LOANX_ID LNX
      WHERE edm.ALADDIN_ID = LNX.ALADDIN_ID
)

GROUP BY 1,2,3,4
),

/* ---------------- CUSIP ---------------- */
WSO_CUSIP_ID AS (
SELECT
    wsoe.business_date,
    edm.aladdin_id,
    wsoe.lead_manager,
    wsoe.deal_sponsor,

    AVG(IFF(TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded'),
            wsoe.CONTRACT_BASE_RATE, NULL)) AS CONTRACT_BASE_RATE,

    AVG(IFF(TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded'),
            (wsoe.CONTRACT_SPREADADJUSTMENT + wsoe.CONTRACT_SPREAD), NULL)) AS CONTRACT_SPREAD,

    MAX(IFF(TRIM(wsoe.CONTRACT_NAME) IN ('UNFND','Unfunded'),
            wsoe.COMMITMENT_FEE, NULL)) AS COMMITMENT_FEE,

    AVG(IFF(TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded'),
            (wsoe.WEIGHTED_AVERAGE_ALL_IN_RATE * 100), NULL)) AS COUPON_RATE

FROM BASE_FILTER wsoe
JOIN PROD_STAGING.PUBLIC.EDM_DAILY_SECURITYMASTER edm
     ON wsoe.CUSIP_ID = edm.ALADDIN_ID
     AND COALESCE(wsoe.CUSIP_ID,'') <> ''
     AND wsoe.BUSINESS_DATE = edm.BUSINESS_DATE

WHERE NOT EXISTS (
      SELECT 1 FROM WSO_LOANX_ID LNX
      WHERE edm.ALADDIN_ID = LNX.ALADDIN_ID
)
AND NOT EXISTS (
      SELECT 1 FROM WSO_SECURITY_ID SEC
      WHERE edm.ALADDIN_ID = SEC.ALADDIN_ID
)

GROUP BY 1,2,3,4
),

/* ---------------- FINAL UNION ---------------- */
WSO_ENRICHMENT AS (
    SELECT * FROM WSO_LOANX_ID
    UNION ALL
    SELECT * FROM WSO_SECURITY_ID
    UNION ALL
    SELECT * FROM WSO_CUSIP_ID
)

SELECT * FROM WSO_ENRICHMENT;
