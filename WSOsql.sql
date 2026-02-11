WITH WSO_loanx_id 
 AS (
SELECT DISTINCT
    wsoe.business_date,
    edm.aladdin_id,
    wsoe.lead_manager,
    wsoe.deal_sponsor,

    AVG(CASE 
            WHEN TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded') 
            THEN wsoe.CONTRACT_BASE_RATE 
        END) AS CONTRACT_BASE_RATE,

    AVG(CASE 
            WHEN TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded') 
            THEN (wsoe.CONTRACT_SPREADADJUSTMENT + wsoe.CONTRACT_SPREAD) 
        END) AS CONTRACT_SPREAD,

    MAX(CASE 
            WHEN TRIM(wsoe.CONTRACT_NAME) IN ('UNFND','Unfunded') 
            THEN wsoe.COMMITMENT_FEE 
        END) AS COMMITMENT_FEE,

    AVG(CASE 
            WHEN TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded') 
            THEN (wsoe.WEIGHTED_AVERAGE_ALL_IN_RATE * 100) 
        END) AS COUPON_RATE
        --,TRIM(wsoe.CONTRACT_NAME)---added for checking purpose
        --,wsoe.LOANX_ID ID

FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT wsoe
INNER JOIN PROD_STAGING.PUBLIC.EDM_DAILY_SECURITYMASTER edm
    ON wsoe.LOANX_ID = edm.LOANX_ID
    AND COALESCE(wsoe.LOANX_ID, '') <> ''
    AND wsoe.BUSINESS_DATE = edm.BUSINESS_DATE

WHERE
    /* Remove rows only if ALL fields are NULL / blank */
    NOT (
        COALESCE(TRIM(wsoe.CONTRACT_NAME), '') = ''
        AND COALESCE(TRIM(wsoe.LEAD_MANAGER), '') = ''
        AND COALESCE(TRIM(wsoe.DEAL_SPONSOR), '') = ''
        AND wsoe.WEIGHTED_AVERAGE_ALL_IN_RATE IS NULL
    )
    GROUP BY 1,2,3,4--,9,10
  ),
WSO_security_id 
 AS(
  SELECT DISTINCT
    wsoe.business_date,
    edm.aladdin_id,
    wsoe.lead_manager,
    wsoe.deal_sponsor,

    AVG(CASE 
            WHEN TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded') 
            THEN wsoe.CONTRACT_BASE_RATE 
        END) AS CONTRACT_BASE_RATE,

    AVG(CASE 
            WHEN TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded') 
            THEN (wsoe.CONTRACT_SPREADADJUSTMENT + wsoe.CONTRACT_SPREAD) 
        END) AS CONTRACT_SPREAD,

    MAX(CASE 
            WHEN TRIM(wsoe.CONTRACT_NAME) IN ('UNFND','Unfunded') 
            THEN wsoe.COMMITMENT_FEE 
        END) AS COMMITMENT_FEE,

    AVG(CASE 
            WHEN TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded') 
            THEN (wsoe.WEIGHTED_AVERAGE_ALL_IN_RATE * 100) 
        END) AS COUPON_RATE
        --,TRIM(wsoe.CONTRACT_NAME)---added for checking purpose
        --,WSOE.SECURITY_ID ID

FROM PROD_STAGING."PUBLIC"."WSO_DAILY_SECURITYMASTER_ENRICHMENT" WSOE
      INNER JOIN PROD_STAGING."PUBLIC"."EDM_DAILY_SECURITYMASTER"  EDM
          ON (WSOE.SECURITY_ID = EDM.LIN AND COALESCE(SECURITY_ID,'') != '')
          AND WSOE.BUSINESS_DATE= EDM.BUSINESS_DATE

WHERE
    /* Remove rows only if ALL fields are NULL / blank */
    NOT (
        COALESCE(TRIM(wsoe.CONTRACT_NAME), '') = ''
        AND COALESCE(TRIM(wsoe.LEAD_MANAGER), '') = ''
        AND COALESCE(TRIM(wsoe.DEAL_SPONSOR), '') = ''
        AND wsoe.WEIGHTED_AVERAGE_ALL_IN_RATE IS NULL
    )
    AND 1=1 
    AND NOT EXISTS ( SELECT 1 FROM WSO_LOANX_ID LNX WHERE EDM.ALADDIN_ID = LNX.ALADDIN_ID )

    GROUP BY 1,2,3,4--,9,10
  ),
WSO_cusip_id 
 AS (
  SELECT DISTINCT
    wsoe.business_date,
    edm.aladdin_id,
    wsoe.lead_manager,
    wsoe.deal_sponsor,

    AVG(CASE 
            WHEN TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded') 
            THEN wsoe.CONTRACT_BASE_RATE 
        END) AS CONTRACT_BASE_RATE,

    AVG(CASE 
            WHEN TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded') 
            THEN (wsoe.CONTRACT_SPREADADJUSTMENT + wsoe.CONTRACT_SPREAD) 
        END) AS CONTRACT_SPREAD,

    MAX(CASE 
            WHEN TRIM(wsoe.CONTRACT_NAME) IN ('UNFND','Unfunded') 
            THEN wsoe.COMMITMENT_FEE 
        END) AS COMMITMENT_FEE,

    AVG(CASE 
            WHEN TRIM(wsoe.CONTRACT_NAME) NOT IN ('UNFND','Unfunded') 
            THEN (wsoe.WEIGHTED_AVERAGE_ALL_IN_RATE * 100) 
        END) AS COUPON_RATE
       -- ,TRIM(wsoe.CONTRACT_NAME)---added for checking purpose
        --,WSOE.CUSIP_ID ID
FROM PROD_STAGING."PUBLIC"."WSO_DAILY_SECURITYMASTER_ENRICHMENT" WSOE
     INNER JOIN PROD_STAGING."PUBLIC"."EDM_DAILY_SECURITYMASTER"  EDM
       ON (WSOE.CUSIP_ID = EDM.ALADDIN_ID AND COALESCE(WSOE.CUSIP_ID,'') != '')
       AND WSOE.BUSINESS_DATE= EDM.BUSINESS_DATE

WHERE
    /* Remove rows only if ALL fields are NULL / blank */
    NOT (
        COALESCE(TRIM(wsoe.CONTRACT_NAME), '') = ''
        AND COALESCE(TRIM(wsoe.LEAD_MANAGER), '') = ''
        AND COALESCE(TRIM(wsoe.DEAL_SPONSOR), '') = ''
        AND wsoe.WEIGHTED_AVERAGE_ALL_IN_RATE IS NULL
    ) 
     AND 1=1
          AND NOT EXISTS ( SELECT 1 FROM WSO_LOANX_ID LNX WHERE EDM.ALADDIN_ID = LNX.ALADDIN_ID )
          AND NOT EXISTS ( SELECT 1 FROM WSO_SECURITY_ID SEC WHERE EDM.ALADDIN_ID = SEC.ALADDIN_ID )
    GROUP BY 1,2,3,4--,9,10
  ),
WSOEnrichment 
 AS (
     SELECT * FROM WSO_LOANX_ID
        UNION ALL
     SELECT * FROM WSO_SECURITY_ID
        UNION ALL
     SELECT * FROM WSO_CUSIP_ID  
   ) 
