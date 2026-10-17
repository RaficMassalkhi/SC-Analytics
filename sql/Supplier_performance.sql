-- KPI 2: PO Fill Rate %
--Total quantity received / total quantity ordered

SELECT  
    po.supplier_id,
    SUM(pol.quantity_ordered) AS total_quantity_ordered,
    SUM(pol.quantity_received) AS total_quantity_received, 
    ROUND(100.0* SUM (pol.quantity_received) / SUM(pol.quantity_ordered),2) AS supplier_po_fill_rate


FROM purchase_orders po

JOIN purchase_order_lines pol 
    ON po.purchase_order_id = pol.purchase_order_id
    
GROUP BY
    po.supplier_id;


-- KPI 3: Supplier OTD %
--POs received on/before expected_at / total received POs

SELECT
    supplier_id,
    COUNT(CASE
            WHEN received_at <= expected_at
            THEN 1
        END) AS on_time_POs,
    COUNT(*) AS total_received_POs,
    ROUND(100.0 * COUNT(CASE
                WHEN received_at <= expected_at
                THEN 1
            END) / COUNT(*),2) AS supplier_OTD

FROM purchase_orders

WHERE NULLIF(TRIM(received_at), '') IS NOT NULL

GROUP BY supplier_id;

-- KPI 4: Actual Lead Time 
--received_at - ordered_at

SELECT
    purchase_order_id,
    supplier_id,
    ROUND(julianday(received_at) - julianday(ordered_at),2)  AS actual_lead_time_days

FROM purchase_orders

WHERE NULLIF(TRIM(received_at), '') IS NOT NULL;

-- KPI 5: Average Actual Lead Time
-- Average actual lead time

SELECT
    supplier_id,
    ROUND(AVG(julianday(received_at) - julianday(ordered_at)),2)  AS avg_actual_lead_time_days

FROM purchase_orders

WHERE NULLIF(TRIM(received_at), '') IS NOT NULL

GROUP BY supplier_id;

-- KPI 6: Lead-Time Variability
-- Standard deviation of actual lead time
-- Population Variability

SELECT
    supplier_id,

    ROUND(SQRT(AVG((julianday(received_at) - julianday(ordered_at))* 
                   (julianday(received_at) - julianday(ordered_at))) -
               AVG(julianday(received_at) - julianday(ordered_at))* 
               AVG(julianday(received_at) - julianday(ordered_at))), 2) 
    AS lead_time_variability_days

FROM purchase_orders

WHERE NULLIF(TRIM(received_at), '') IS NOT NULL

GROUP BY supplier_id;

-- KPI 7: Lead-Time Variance
-- Actual lead time - planned lead time = received at - expected at
-- Positive = Late // Negative = Early

SELECT 
    supplier_id,
    ROUND(AVG(julianday(received_at) - julianday(expected_at)),2) AS avg_lead_time_variance_days

FROM purchase_orders

WHERE NULLIF(TRIM(received_at), '') IS NOT NULL

GROUP BY supplier_id;

-- KPI 8: Supplier Fill Rate 
--Received units / units ordered 

SELECT
    po.supplier_id,
    SUM(pol.quantity_received) AS total_units_received,
    SUM(pol.quantity_ordered) AS total_units_ordered,
    ROUND(100.0 * SUM(pol.quantity_received)/ SUM(pol.quantity_ordered), 2) AS supplier_fill_rate

FROM purchase_orders po

JOIN purchase_order_lines pol
    ON po.purchase_order_id = pol.purchase_order_id

GROUP BY
    po.supplier_id;

-- KPI 9: Supplier OTIF Proxy
-- OTIF orders / total received orders

SELECT
    supplier_id,
    COUNT(CASE
            WHEN received_at <= expected_at
                 AND total_received = total_ordered
            THEN 1
        END) AS otif_pos,
    COUNT(*) AS total_received_pos,
    ROUND(100.0 *COUNT(CASE
                WHEN received_at <= expected_at
                     AND total_received = total_ordered
                THEN 1
            END) / COUNT(*),2) AS otif_proxy

FROM (
    SELECT
        po.purchase_order_id,
        po.supplier_id,
        po.received_at,
        po.expected_at,
        SUM(pol.quantity_ordered) AS total_ordered,
        SUM(pol.quantity_received) AS total_received

    FROM purchase_orders po

    JOIN purchase_order_lines pol
        ON po.purchase_order_id = pol.purchase_order_id

    WHERE NULLIF(TRIM(po.received_at), '') IS NOT NULL

    GROUP BY
        po.purchase_order_id,
        po.supplier_id,
        po.received_at,
        po.expected_at
)

GROUP BY supplier_id;