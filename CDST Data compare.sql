with COMPARISON AS (
    SELECT
        COALESCE(o.business_date, n.business_date) AS business_date,
        COALESCE(o.aladdin_id, n.aladdin_id) AS aladdin_id,

        n.LEAD_MANAGER,
        o.LEAD_MANAGER,
        n.DEAL_SPONSOR,
        o.DEAL_SPONSOR,
       

        o.coupon_rate AS old_coupon_rate,
        n.coupon_rate AS new_coupon_rate,

    
        ABS(NVL(o.coupon_rate,0) - NVL(n.coupon_rate,0)) AS coupon_diff

    FROM SANDBOX_01.VAITHI_DEV.STAGE_DIM_ASSET_DATA_COMPARE_BEFORE o
    FULL OUTER JOIN SANDBOX_01.VAITHI_DEV.STAGE_DIM_ASSET_DATA_COMPARE_AFTER n
        ON o.business_date = n.business_date
        AND o.aladdin_id = n.aladdin_id
       -- AND (COALESCE(n.LEAD_MANAGER,'') ='' 
       -- AND COALESCE(n.DEAL_SPONSOR,'') ='')
       
)

SELECT --distinct aladdin_id
   business_date,
    aladdin_id,
    old_coupon_rate,
    new_coupon_rate,
    coupon_diff
FROM COMPARISON
WHERE coupon_diff > 0
   and BUSINESS_DATE::date = '2026-02-11'   
ORDER BY 1 desc;
