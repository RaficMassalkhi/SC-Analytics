-- KPI 1: Outstanding PO Value 
-- Sum(quantity_ordered - quantity_received) x unit_cost
-- The master unit cost is being used for ALL calculations (products table)

SELECT
    po.supplier_id,
    po.warehouse_id,
    pol.product_id,
    SUM(pol.quantity_ordered - pol.quantity_received) AS outstanding_units,
    SUM((pol.quantity_ordered - pol.quantity_received) * p.unit_cost) AS outstanding_po_value

FROM purchase_orders po

JOIN purchase_order_lines pol
    ON po.purchase_order_id = pol.purchase_order_id

JOIN products p
    ON pol.product_id = p.product_id

WHERE po.status IN ('open', 'partial')

GROUP BY
    po.supplier_id,
    po.warehouse_id,
    pol.product_id

HAVING
    SUM(pol.quantity_ordered - pol.quantity_received) > 0;

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
-- Can include actual vs expected lead time later in the future -- *note to self

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

-- KPI 10: Current Inventory Units 
-- Excel Sheet containing full reconstructed inventory is in the excel folder 

SELECT
    warehouse_id,
    SUM(ending_inventory) AS inventory_units

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) 

GROUP BY
    warehouse_id;

-- KPI 11: Current Inventory Value 
-- List of warehouse ids, inventory units, and the total value for each warehouse

SELECT
    ri.warehouse_id,
    SUM(ri.ending_inventory) AS inventory_units,
    ROUND(SUM(MAX(ri.ending_inventory, 0) * p.unit_cost), 2) AS current_inventory_value

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) ri

JOIN products p
    ON ri.product_id = p.product_id

GROUP BY
    ri.warehouse_id

ORDER BY
    ri.warehouse_id;

-- KPI 12: Stockout SKU Count 
-- SKU-Warehouse positions with current inventory <= 0

SELECT
    warehouse_id,
    COUNT(*) AS stockout_sku_count

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
)

WHERE ending_inventory <= 0

GROUP BY
    warehouse_id

ORDER BY
    warehouse_id;
-- KPI 13: Stockout Rate % 
-- Stockout positions / active inventory positions
-- All 30,000 reconstructed Product x Warehouse positions are considered active 


SELECT 
    warehouse_id, 
    COUNT(CASE
            WHEN ending_inventory <= 0
            THEN 1
        END) AS stockout_positions,
    COUNT(CASE
            WHEN ending_inventory IS NOT NULL 
            THEN 1
        END) AS active_inventory_positions,
    ROUND(100.0 * COUNT(CASE
            WHEN ending_inventory <= 0
            THEN 1
        END) / COUNT(CASE
            WHEN ending_inventory IS NOT NULL 
            THEN 1
        END),2) AS warehouse_stockout_rate

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
)
GROUP BY warehouse_id;

-- KPI 14: Below Reorder Point Count 
-- Count positions where inventory < reorder_point

SELECT 
    ri.warehouse_id,
    COUNT(*) AS below_reorder_point_count

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) ri
JOIN products p
    ON ri.product_id = p.product_id

WHERE ri.ending_inventory < p.reorder_point

GROUP BY ri.warehouse_id;

-- KPI 15: Below Reorder Point % 
-- Below ROP positions / relevant positions

SELECT
    COUNT(CASE
            WHEN ri.ending_inventory < p.reorder_point
            THEN 1
        END) AS below_rop_positions,
    COUNT(*) AS relevant_positions,
    ROUND(100.0 * COUNT(CASE
                WHEN ri.ending_inventory < p.reorder_point
                THEN 1
            END) / COUNT(*),2) AS below_reorder_point

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) ri

JOIN products p
    ON ri.product_id = p.product_id;

-- KPI 16: Slow moving inventory
-- Stock with outbound movement below a defined time window
-- Slow-moving is defined as 1-25 units sold in the last 90 days 
SELECT
    inventory.warehouse_id,
    COUNT(*) AS slow_moving_positions,
    SUM(inventory.ending_inventory) AS slow_moving_units,
    ROUND(SUM(inventory.ending_inventory * p.unit_cost), 2) AS slow_moving_inventory_value

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory,
        SUM(CASE
                WHEN im.movement_type = 'sale'
                     AND julianday((
                            SELECT MAX(movement_at)
                            FROM inventory_movements))
                              - julianday(im.movement_at) <= 90
                THEN -im.quantity_change
                ELSE 0
            END) AS outbound_90_days

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) inventory
JOIN products p
    ON inventory.product_id = p.product_id

WHERE inventory.ending_inventory > 0
  AND inventory.outbound_90_days BETWEEN 1 AND 25

GROUP BY
    inventory.warehouse_id

ORDER BY
    inventory.warehouse_id;


-- KPI 17: Non-moving Inventory
-- Stock with no outbound for 90 days
-- Non-moving is defined as 0 units sold in the last 90 days
SELECT
    inventory.warehouse_id,
    COUNT(*) AS non_moving_positions,
    SUM(inventory.ending_inventory) AS non_moving_units,
    ROUND(SUM(inventory.ending_inventory * p.unit_cost), 2) AS non_moving_inventory_value

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory,
        MAX(CASE
                WHEN im.movement_type = 'sale'
                THEN im.movement_at
            END) AS last_outbound

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) inventory

JOIN products p
    ON inventory.product_id = p.product_id

WHERE inventory.ending_inventory > 0

  AND (inventory.last_outbound IS NULL
      OR julianday((
            SELECT MAX(movement_at)
            FROM inventory_movements))
            - julianday(inventory.last_outbound) > 90)

GROUP BY
    inventory.warehouse_id

ORDER BY
    inventory.warehouse_id;

-- KPI 18: Slow/Non-moving Inventory Value 
-- Slow/non-moving stock * unit cost

SELECT
    inventory.warehouse_id,
    ROUND(SUM(inventory.ending_inventory * p.unit_cost), 2) AS slow_nonmoving_inventory_value

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory,
        SUM(CASE
                WHEN im.movement_type = 'sale'
                     AND julianday((
                            SELECT MAX(movement_at)
                            FROM inventory_movements))
                          - julianday(im.movement_at) <= 90
                THEN -im.quantity_change
                ELSE 0
            END) AS outbound_90_days

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) inventory

JOIN products p
    ON inventory.product_id = p.product_id

WHERE inventory.ending_inventory > 0

  AND inventory.outbound_90_days BETWEEN 0 AND 25

GROUP BY
    inventory.warehouse_id

ORDER BY
    inventory.warehouse_id;

-- KPI 19: Excess Inventory Proxy
-- Current Stock - required coverage stock (where positive)
-- Required coverage is calculated by finding the avg daily outbound for each product and 
-- multiplied by 30 to find the month's required stock

SELECT
    ri.warehouse_id,
    ROUND(SUM(CASE
                WHEN ri.ending_inventory - (COALESCE(outbound.total_outbound_units, 0) / 1096.0 * 30) > 0
                THEN ri.ending_inventory - (COALESCE(outbound.total_outbound_units, 0) / 1096.0 * 30)
                ELSE 0
            END),2) AS excess_inventory_units

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) ri

LEFT JOIN (
    SELECT
        product_id,
        warehouse_id,
        SUM(-quantity_change) AS total_outbound_units

    FROM inventory_movements

    WHERE movement_type = 'sale'

    GROUP BY
        product_id,
        warehouse_id
) outbound
    ON ri.product_id = outbound.product_id
    AND ri.warehouse_id = outbound.warehouse_id

GROUP BY
    ri.warehouse_id

ORDER BY
    ri.warehouse_id;


-- KPI 20: Excess Inventory Value 
-- Excess inventory * unit cost 

SELECT
    ri.warehouse_id,
    ROUND(SUM(CASE
                WHEN ri.ending_inventory - (COALESCE(outbound.total_outbound_units, 0) / 1096.0 * 30) > 0
                THEN ri.ending_inventory - (COALESCE(outbound.total_outbound_units, 0) / 1096.0 * 30)
                ELSE 0
            END),2) AS excess_inventory_units,
    ROUND(SUM(CASE
                 WHEN ri.ending_inventory - (COALESCE(outbound.total_outbound_units, 0) / 1096.0 * 30) > 0
                THEN (ri.ending_inventory- (COALESCE(outbound.total_outbound_units, 0) / 1096.0 * 30))* p.unit_cost
                ELSE 0
            END),2) AS excess_inventory_value

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) ri

LEFT JOIN (
    SELECT
        product_id,
        warehouse_id,
        SUM(-quantity_change) AS total_outbound_units

    FROM inventory_movements

    WHERE movement_type = 'sale'

    GROUP BY
        product_id,
        warehouse_id
) outbound
    ON ri.product_id = outbound.product_id
    AND ri.warehouse_id = outbound.warehouse_id

JOIN products p ON ri.product_id = p.product_id

GROUP BY
    ri.warehouse_id

ORDER BY
    ri.warehouse_id;


-- KPI 21: Inventory Turnover
-- Annual outbound value / avg. inventory value
SELECT
    annual.product_id,
    annual.annual_outbound_value,
    inventory.avg_inventory_value,
    ROUND(annual.annual_outbound_value / inventory.avg_inventory_value, 2) AS inventory_turnover

FROM (
    SELECT
        o.product_id,
        ROUND(o.annual_outbound_units * p.unit_cost,2) AS annual_outbound_value

    FROM (
        SELECT
            product_id,
            SUM(-quantity_change) * 365.0 / 1096.0 AS annual_outbound_units

        FROM inventory_movements

        WHERE movement_type = 'sale'

        GROUP BY product_id
    ) o
    JOIN products p
        ON o.product_id = p.product_id
) annual

JOIN (
    SELECT
        ri.product_id,
        ROUND((SUM(ri.opening_units * p.unit_cost)+ SUM(MAX(ri.ending_inventory, 0) * p.unit_cost)) / 2.0, 2) 
        AS avg_inventory_value

    FROM (
        SELECT
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units,
            iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

        FROM inventory_opening_balances iob

        LEFT JOIN inventory_movements im
            ON iob.product_id = im.product_id
            AND iob.warehouse_id = im.warehouse_id

        GROUP BY
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units
    ) ri

    JOIN products p
        ON ri.product_id = p.product_id

    GROUP BY
        ri.product_id
) inventory

    ON annual.product_id = inventory.product_id

ORDER BY
    annual.product_id;

-- KPI 22: Days Inventory on Hand
-- Current Inventory / avg. daily outbound consumption

SELECT
    ri.warehouse_id,
    ROUND(SUM(ri.ending_inventory) / (SUM(COALESCE(outbound.total_outbound_units, 0)) / 1096.0), 2)
     AS days_inventory_on_hand

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) ri

LEFT JOIN (
    SELECT
        product_id,
        warehouse_id,
        SUM(-quantity_change) AS total_outbound_units

    FROM inventory_movements

    WHERE movement_type = 'sale'

    GROUP BY
        product_id,
        warehouse_id
) outbound
    ON ri.product_id = outbound.product_id
    AND ri.warehouse_id = outbound.warehouse_id

GROUP BY
    ri.warehouse_id

ORDER BY
    ri.warehouse_id;


-- KPI 23: Inventory Coverage 
-- Current stock / average daily/weekly outbound consumption

SELECT
    ri.warehouse_id,
    ROUND(SUM(ri.ending_inventory) / (SUM(COALESCE(outbound.total_outbound_units, 0)) / 1096.0 * 7), 2) 
    AS inventory_coverage_weeks

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) ri

LEFT JOIN (
    SELECT
        product_id,
        warehouse_id,
        SUM(-quantity_change) AS total_outbound_units

    FROM inventory_movements

    WHERE movement_type = 'sale'

    GROUP BY
        product_id,
        warehouse_id
) outbound
    ON ri.product_id = outbound.product_id
    AND ri.warehouse_id = outbound.warehouse_id

GROUP BY
    ri.warehouse_id

ORDER BY
    ri.warehouse_id;

-- KPI 24: Inventory Balance Reconciliation
-- Opening balance + net movements = calculated closing

SELECT
    iob.warehouse_id,
    SUM(iob.opening_units) AS opening_inventory,
    SUM(COALESCE(movements.net_movement, 0)) AS net_movement,
    SUM(iob.opening_units + COALESCE(movements.net_movement, 0)) AS calculated_closing_inventory


FROM inventory_opening_balances iob

LEFT JOIN (
    SELECT
        product_id,
        warehouse_id,
        SUM(quantity_change) AS net_movement

    FROM inventory_movements

    GROUP BY
        product_id,
        warehouse_id
) movements
    ON iob.product_id = movements.product_id
    AND iob.warehouse_id = movements.warehouse_id

GROUP BY
    iob.warehouse_id

ORDER BY
    iob.warehouse_id;

-- KPI 25: Capacity Utilization %
-- Current inventory units ÷ capacity_units

SELECT
    ri.warehouse_id,
    SUM(ri.ending_inventory) AS current_inventory_units,
    w.capacity_units,
    ROUND(100.0 * SUM(ri.ending_inventory) / w.capacity_units, 2) AS capacity_utilization_pct

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) ri

JOIN warehouses w
    ON ri.warehouse_id = w.warehouse_id

GROUP BY
    ri.warehouse_id,
    w.capacity_units

ORDER BY
    ri.warehouse_id;


-- KPI 26: Capacity Risk
-- Current inventory + relevant inbound pipeline compared with capacity
-- Inbound pipeline is based on outstanding quantities on open/partial POs

SELECT
    ri.warehouse_id,
    SUM(ri.ending_inventory) AS current_inventory_units,
    COALESCE(inbound.inbound_units, 0) AS inbound_pipeline_units,
    SUM(ri.ending_inventory) + COALESCE(inbound.inbound_units, 0) AS projected_inventory_units,
    w.capacity_units

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) ri

JOIN warehouses w
    ON ri.warehouse_id = w.warehouse_id

LEFT JOIN (
    SELECT
        po.warehouse_id,
        SUM(pol.quantity_ordered - pol.quantity_received) AS inbound_units

    FROM purchase_orders po

    JOIN purchase_order_lines pol
        ON po.purchase_order_id = pol.purchase_order_id

    WHERE po.status IN ('open', 'partial')
      AND pol.quantity_ordered > pol.quantity_received

    GROUP BY
        po.warehouse_id
) inbound
    ON ri.warehouse_id = inbound.warehouse_id

GROUP BY
    ri.warehouse_id,
    w.capacity_units,
    inbound.inbound_units

ORDER BY
    ri.warehouse_id;

-- KPI 27: Inventory Imbalance
-- Find the same SKU overstocked in one warehouse while short in another.
-- Compare SKU stock/coverage/ROP across warehouses

SELECT
    inventory.product_id,
    COUNT(CASE
            WHEN inventory.ending_inventory > inventory.reorder_point
            THEN 1
        END) AS overstocked_warehouses,
    COUNT(CASE
            WHEN inventory.ending_inventory < inventory.reorder_point
            THEN 1
        END) AS short_warehouses,
    SUM(CASE
            WHEN inventory.ending_inventory > inventory.reorder_point
            THEN inventory.ending_inventory - inventory.reorder_point
            ELSE 0
        END) AS excess_units,
    SUM(CASE
            WHEN inventory.ending_inventory < inventory.reorder_point
            THEN inventory.reorder_point - inventory.ending_inventory
            ELSE 0
        END) AS shortage_units

FROM (
    SELECT
        ri.product_id,
        ri.warehouse_id,
        ri.ending_inventory,
        p.reorder_point

    FROM (
        SELECT
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

        FROM inventory_opening_balances iob

        LEFT JOIN inventory_movements im
            ON iob.product_id = im.product_id
            AND iob.warehouse_id = im.warehouse_id

        GROUP BY
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units
    ) ri

    JOIN products p
        ON ri.product_id = p.product_id
) inventory

GROUP BY
    inventory.product_id

HAVING
    COUNT(CASE
            WHEN inventory.ending_inventory > inventory.reorder_point
            THEN 1
        END) > 0
    AND
    COUNT(CASE
            WHEN inventory.ending_inventory < inventory.reorder_point
            THEN 1
        END) > 0

ORDER BY
    inventory.product_id;

-- KPI 28: Rebalancing Opportunity
-- Potential transferable excess matched to shortages by SKU

SELECT
    inventory.product_id,
    SUM(CASE
            WHEN inventory.ending_inventory > inventory.reorder_point
            THEN inventory.ending_inventory - inventory.reorder_point
            ELSE 0
        END) AS excess_units,
    SUM(CASE
            WHEN inventory.ending_inventory < inventory.reorder_point
            THEN inventory.reorder_point - inventory.ending_inventory
            ELSE 0
        END) AS shortage_units,
    CASE
        WHEN SUM(CASE
                    WHEN inventory.ending_inventory > inventory.reorder_point
                    THEN inventory.ending_inventory - inventory.reorder_point
                    ELSE 0
                END) <
             SUM(CASE
                    WHEN inventory.ending_inventory < inventory.reorder_point
                    THEN inventory.reorder_point - inventory.ending_inventory
                    ELSE 0
                END)
        THEN SUM(CASE
                    WHEN inventory.ending_inventory > inventory.reorder_point
                    THEN inventory.ending_inventory - inventory.reorder_point
                    ELSE 0
                END)
        ELSE SUM(CASE
                    WHEN inventory.ending_inventory < inventory.reorder_point
                    THEN inventory.reorder_point - inventory.ending_inventory
                    ELSE 0
                END)
    END AS rebalancing_opportunity_units

FROM (
    SELECT
        ri.product_id,
        ri.warehouse_id,
        ri.ending_inventory,
        p.reorder_point

    FROM (
        SELECT
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

        FROM inventory_opening_balances iob

        LEFT JOIN inventory_movements im
            ON iob.product_id = im.product_id
            AND iob.warehouse_id = im.warehouse_id

        GROUP BY
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units
    ) ri

    JOIN products p
        ON ri.product_id = p.product_id
) inventory

GROUP BY
    inventory.product_id

HAVING
    SUM(CASE
            WHEN inventory.ending_inventory > inventory.reorder_point
            THEN inventory.ending_inventory - inventory.reorder_point
            ELSE 0
        END) > 0
    AND
    SUM(CASE
            WHEN inventory.ending_inventory < inventory.reorder_point
            THEN inventory.reorder_point - inventory.ending_inventory
            ELSE 0
        END) > 0

ORDER BY
    inventory.product_id;


-- KPI 29: Inbound Pipeline Units
-- Outstanding ordered quantity assigned to destination warehouse

SELECT
    po.warehouse_id,
    SUM(pol.quantity_ordered - pol.quantity_received) AS inbound_pipeline_units

FROM purchase_orders po

JOIN purchase_order_lines pol
    ON po.purchase_order_id = pol.purchase_order_id

WHERE po.status IN ('open', 'partial')

    AND pol.quantity_ordered > pol.quantity_received

GROUP BY
    po.warehouse_id

ORDER BY
    po.warehouse_id;

-- KPI 30: Projected Inventory 
-- Current stock + outstanding inbound quantity

SELECT
    ri.warehouse_id,
    SUM(ri.ending_inventory) AS current_inventory_units,
    COALESCE(inbound.inbound_pipeline_units, 0) AS inbound_pipeline_units,
    SUM(ri.ending_inventory) + COALESCE(inbound.inbound_pipeline_units, 0) AS projected_inventory_units

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) ri

LEFT JOIN (
    SELECT
        po.warehouse_id,
        SUM(pol.quantity_ordered - pol.quantity_received) AS inbound_pipeline_units

    FROM purchase_orders po

    JOIN purchase_order_lines pol
        ON po.purchase_order_id = pol.purchase_order_id

    WHERE po.status IN ('open', 'partial')

        AND pol.quantity_ordered > pol.quantity_received

    GROUP BY
        po.warehouse_id
) inbound
    ON ri.warehouse_id = inbound.warehouse_id

GROUP BY
    ri.warehouse_id,
    inbound.inbound_pipeline_units

ORDER BY
    ri.warehouse_id;

-- KPI 31: Projected Capacity Utilization 
-- (Current stock + inbound pipeline) ÷ capacity

SELECT
    ri.warehouse_id,
    SUM(ri.ending_inventory) AS current_inventory_units,
    COALESCE(inbound.inbound_units, 0) AS inbound_pipeline_units,
    SUM(ri.ending_inventory) + COALESCE(inbound.inbound_units, 0) AS projected_inventory_units,
    w.capacity_units,
    ROUND(100.0 * (SUM(ri.ending_inventory) + COALESCE(inbound.inbound_units, 0)) / w.capacity_units, 2) 
    AS projected_capacity_utilization

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) ri

JOIN warehouses w
    ON ri.warehouse_id = w.warehouse_id

LEFT JOIN (
    SELECT
        po.warehouse_id,
        SUM(pol.quantity_ordered - pol.quantity_received) AS inbound_units

    FROM purchase_orders po

    JOIN purchase_order_lines pol
        ON po.purchase_order_id = pol.purchase_order_id

    WHERE po.status IN ('open', 'partial')
      AND pol.quantity_ordered > pol.quantity_received

    GROUP BY
        po.warehouse_id
) inbound
    ON ri.warehouse_id = inbound.warehouse_id

GROUP BY
    ri.warehouse_id,
    w.capacity_units,
    inbound.inbound_units

ORDER BY
    ri.warehouse_id;

-- KPI 32: Supply-at-Risk SKUs
-- Flag low/stockout inventory combined with poor supplier service or late inbound

SELECT
    inventory.product_id,
    inventory.supplier_id,
    inventory.low_inventory_warehouses,
    supplier.supplier_otd_pct,
    COALESCE(late_inbound.late_inbound_units, 0) AS late_inbound_units

FROM (
    SELECT
        ri.product_id,
        p.supplier_id,
        COUNT(CASE
                WHEN ri.ending_inventory <= p.reorder_point
                THEN 1
            END) AS low_inventory_warehouses

    FROM (
        SELECT
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

        FROM inventory_opening_balances iob

        LEFT JOIN inventory_movements im
            ON iob.product_id = im.product_id
            AND iob.warehouse_id = im.warehouse_id

        GROUP BY
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units
    ) ri

    JOIN products p
        ON ri.product_id = p.product_id

    GROUP BY
        ri.product_id,
        p.supplier_id
) inventory

JOIN (
    SELECT
        supplier_id,
        ROUND(100.0 * COUNT(CASE
                    WHEN received_at <= expected_at
                    THEN 1
                END) / COUNT(*), 2) AS supplier_otd_pct

    FROM purchase_orders

    WHERE NULLIF(TRIM(received_at), '') IS NOT NULL

    GROUP BY
        supplier_id
) supplier
    ON inventory.supplier_id = supplier.supplier_id

LEFT JOIN (
    SELECT
        pol.product_id,
        SUM(pol.quantity_ordered - pol.quantity_received) AS late_inbound_units

    FROM purchase_orders po

    JOIN purchase_order_lines pol
        ON po.purchase_order_id = pol.purchase_order_id

    WHERE po.status IN ('open', 'partial')
        AND pol.quantity_ordered > pol.quantity_received
        AND po.expected_at < '2026-01-01'

    GROUP BY
        pol.product_id
) late_inbound
    ON inventory.product_id = late_inbound.product_id

WHERE
    inventory.low_inventory_warehouses > 0

    AND (supplier.supplier_otd_pct < 90
        OR COALESCE(late_inbound.late_inbound_units, 0) > 0)

ORDER BY
    inventory.product_id;

-- KPI 33: Supplier Dependency Risk
-- Combine spend/volume concentration with supplier performance
-- Risk is measured by top-spend suppliers + OTD below 90%.

SELECT
    spend.supplier_id,
    ROUND(spend.supplier_spend, 2) AS supplier_spend,
    ROUND(100.0 * spend.supplier_spend / totals.total_spend, 2) AS spend_share_pct,
    supplier.supplier_otd_pct,
    CASE
        WHEN spend.supplier_spend >= concentration.concentration_threshold
             AND supplier.supplier_otd_pct < 90
        THEN 'High Risk'
        ELSE 'Normal'
    END AS dependency_risk

FROM (
    SELECT
        po.supplier_id,
        SUM(pol.quantity_ordered * p.unit_cost) AS supplier_spend

    FROM purchase_orders po

    JOIN purchase_order_lines pol
        ON po.purchase_order_id = pol.purchase_order_id

    JOIN products p
        ON pol.product_id = p.product_id

    GROUP BY
        po.supplier_id
) spend

CROSS JOIN (
    SELECT
        SUM(pol.quantity_ordered * p.unit_cost) AS total_spend

    FROM purchase_orders po

    JOIN purchase_order_lines pol
        ON po.purchase_order_id = pol.purchase_order_id

    JOIN products p
        ON pol.product_id = p.product_id
) totals

JOIN (
    SELECT
        supplier_id,
        ROUND(100.0 * COUNT(CASE
                    WHEN received_at <= expected_at
                    THEN 1
                END) / COUNT(*), 2) AS supplier_otd_pct

    FROM purchase_orders

    WHERE NULLIF(TRIM(received_at), '') IS NOT NULL

    GROUP BY
        supplier_id
) supplier
    ON spend.supplier_id = supplier.supplier_id

CROSS JOIN (
    SELECT
        MIN(supplier_spend) AS concentration_threshold

    FROM (
        SELECT
            po.supplier_id,
            SUM(pol.quantity_ordered * p.unit_cost) AS supplier_spend

        FROM purchase_orders po

        JOIN purchase_order_lines pol
            ON po.purchase_order_id = pol.purchase_order_id

        JOIN products p
            ON pol.product_id = p.product_id

        GROUP BY
            po.supplier_id

        ORDER BY
            supplier_spend DESC

        LIMIT 25
    )
) concentration

ORDER BY
    spend.supplier_spend DESC;

-- KPI 34: Inventory-at-Risk Value
-- Value of slow, non-moving, excess or otherwise flagged stock

SELECT
    risk.warehouse_id,
    ROUND(SUM(CASE
                WHEN risk.non_moving_flag = 1
                    OR risk.slow_moving_flag = 1
                    OR risk.excess_flag = 1
                    OR risk.low_inventory_flag = 1
                THEN MAX(risk.ending_inventory, 0) * risk.unit_cost
                ELSE 0
            END), 2) AS inventory_at_risk_value

FROM (
    SELECT
        ri.product_id,
        ri.warehouse_id,
        ri.ending_inventory,
        p.unit_cost,
        p.reorder_point,
        CASE
            WHEN ri.ending_inventory > 0
                AND (ri.last_outbound IS NULL
                    OR julianday((
                        SELECT MAX(movement_at)
                         FROM inventory_movements))
                     - julianday(ri.last_outbound) > 90)
            THEN 1
            ELSE 0
        END AS non_moving_flag,
        CASE
            WHEN ri.ending_inventory > 0
                AND ri.outbound_90_days BETWEEN 1 AND 25
            THEN 1
            ELSE 0
        END AS slow_moving_flag,
        CASE
            WHEN ri.ending_inventory > (ri.total_outbound_units / 1096.0 * 30)
            THEN 1
            ELSE 0
        END AS excess_flag,
        CASE
            WHEN ri.ending_inventory <= p.reorder_point
            THEN 1
            ELSE 0
        END AS low_inventory_flag

    FROM (
        SELECT
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory,
            SUM(CASE
                    WHEN im.movement_type = 'sale'
                        AND julianday((
                            SELECT MAX(movement_at)
                             FROM inventory_movements))
                         - julianday(im.movement_at) <= 90
                    THEN -im.quantity_change
                    ELSE 0
                END) AS outbound_90_days,
            SUM(CASE
                    WHEN im.movement_type = 'sale'
                    THEN -im.quantity_change
                    ELSE 0
                END) AS total_outbound_units,
            MAX(CASE
                    WHEN im.movement_type = 'sale'
                    THEN im.movement_at
                END) AS last_outbound

        FROM inventory_opening_balances iob

        LEFT JOIN inventory_movements im
            ON iob.product_id = im.product_id
            AND iob.warehouse_id = im.warehouse_id

        GROUP BY
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units
    ) ri

    JOIN products p
        ON ri.product_id = p.product_id
) risk

GROUP BY
    risk.warehouse_id

ORDER BY
    risk.warehouse_id;

-- KPI 35: Late PO Exposure 
-- Outstanding value on POs past expected_at

SELECT
    po.warehouse_id,
    ROUND(SUM((pol.quantity_ordered - pol.quantity_received) * p.unit_cost), 2) AS late_po_exposure_value

FROM purchase_orders po

JOIN purchase_order_lines pol
    ON po.purchase_order_id = pol.purchase_order_id

JOIN products p
    ON pol.product_id = p.product_id

WHERE po.status IN ('open', 'partial')
    AND pol.quantity_ordered > pol.quantity_received
    AND po.expected_at < '2026-01-01'

GROUP BY
    po.warehouse_id

ORDER BY
    po.warehouse_id;

-- KPI 36: Stockout Exposure
-- Stockout or below-ROP positions with insufficient/no inbound pipeline

SELECT
    inventory.warehouse_id,
    SUM(CASE
            WHEN inventory.ending_inventory <= inventory.reorder_point
            THEN MAX(inventory.reorder_point
                - inventory.ending_inventory
                - COALESCE(inbound.inbound_units, 0) , 0)
            ELSE 0
        END) AS uncovered_shortage_units,
    ROUND(SUM(CASE
                WHEN inventory.ending_inventory <= inventory.reorder_point
                THEN MAX(inventory.reorder_point
                    - inventory.ending_inventory
                    - COALESCE(inbound.inbound_units, 0), 0) * inventory.unit_cost
                ELSE 0
            END), 2) AS stockout_exposure_value

FROM (
    SELECT
        ri.product_id,
        ri.warehouse_id,
        ri.ending_inventory,
        p.reorder_point,
        p.unit_cost

    FROM (
        SELECT
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

        FROM inventory_opening_balances iob

        LEFT JOIN inventory_movements im
            ON iob.product_id = im.product_id
            AND iob.warehouse_id = im.warehouse_id

        GROUP BY
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units
    ) ri

    JOIN products p
        ON ri.product_id = p.product_id
) inventory

LEFT JOIN (
    SELECT
        po.warehouse_id,
        pol.product_id,
        SUM(pol.quantity_ordered - pol.quantity_received) AS inbound_units

    FROM purchase_orders po

    JOIN purchase_order_lines pol
        ON po.purchase_order_id = pol.purchase_order_id

    WHERE po.status IN ('open', 'partial')
        AND pol.quantity_ordered > pol.quantity_received

    GROUP BY
        po.warehouse_id,
        pol.product_id
) inbound
    ON inventory.warehouse_id = inbound.warehouse_id
    AND inventory.product_id = inbound.product_id

GROUP BY
    inventory.warehouse_id

ORDER BY
    inventory.warehouse_id;

-- KPI 37: Working Capital Proxy
-- Total current inventory value

SELECT
    ri.warehouse_id,
    ROUND(SUM(MAX(ri.ending_inventory,0) * p.unit_cost), 2) AS working_capital_proxy

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) ri

JOIN products p
    ON ri.product_id = p.product_id

GROUP BY
    ri.warehouse_id

ORDER BY
    ri.warehouse_id;

-- KPI 38: Excess Working Capital Proxy
-- Total excess inventory value

SELECT
    inventory.warehouse_id,
    ROUND(SUM(CASE
                WHEN inventory.ending_inventory > inventory.required_coverage
                THEN (inventory.ending_inventory - inventory.required_coverage)
                    * inventory.unit_cost
                ELSE 0
            END), 2) AS excess_working_capital_proxy

FROM (
    SELECT
        ri.product_id,
        ri.warehouse_id,
        ri.ending_inventory,
        ri.required_coverage,
        p.unit_cost

    FROM (
        SELECT
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory,
            COALESCE(outbound.total_outbound_units, 0) / 1096.0 * 30 AS required_coverage

        FROM inventory_opening_balances iob

        LEFT JOIN inventory_movements im
            ON iob.product_id = im.product_id
            AND iob.warehouse_id = im.warehouse_id

        LEFT JOIN (
            SELECT
                product_id,
                warehouse_id,
                SUM(-quantity_change) AS total_outbound_units

            FROM inventory_movements

            WHERE movement_type = 'sale'

            GROUP BY
                product_id,
                warehouse_id
        ) outbound
            ON iob.product_id = outbound.product_id
            AND iob.warehouse_id = outbound.warehouse_id

        GROUP BY
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units,
            outbound.total_outbound_units
    ) ri

    JOIN products p
        ON ri.product_id = p.product_id
) inventory

GROUP BY
    inventory.warehouse_id

ORDER BY
    inventory.warehouse_id;

-- KPI 39: Inventory Health %
-- Healthy inventory value ÷ total inventory value

SELECT
    inventory.warehouse_id,
    ROUND(inventory.total_inventory_value, 2) AS total_inventory_value,
    ROUND(inventory.inventory_at_risk_value, 2) AS inventory_at_risk_value,
    ROUND(inventory.total_inventory_value - inventory.inventory_at_risk_value, 2) AS healthy_inventory_value,
    ROUND(100.0 *(inventory.total_inventory_value - inventory.inventory_at_risk_value) / inventory.total_inventory_value, 2)
     AS inventory_health_pct

FROM (
    SELECT
        ri.warehouse_id,
        SUM(MAX(ri.ending_inventory, 0) * ri.unit_cost) AS total_inventory_value,
        SUM(CASE
                WHEN ri.non_moving_flag = 1
                    OR ri.slow_moving_flag = 1
                    OR ri.excess_flag = 1
                    OR ri.low_inventory_flag = 1
                THEN MAX(ri.ending_inventory, 0) * ri.unit_cost
                ELSE 0
            END) AS inventory_at_risk_value

    FROM (
        SELECT
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory,
            p.unit_cost,
            p.reorder_point,
            CASE
                WHEN iob.opening_units + COALESCE(SUM(im.quantity_change), 0) > 0
                    AND (MAX(CASE
                                WHEN im.movement_type = 'sale'
                                THEN im.movement_at
                            END) IS NULL
                        OR julianday((
                            SELECT MAX(movement_at)
                             FROM inventory_movements))
                        - julianday(MAX(CASE
                                    WHEN im.movement_type = 'sale'
                                    THEN im.movement_at
                                END)) > 90)
                THEN 1
                ELSE 0
            END AS non_moving_flag,
            CASE
                WHEN iob.opening_units + COALESCE(SUM(im.quantity_change), 0) > 0
                    AND SUM(CASE
                                WHEN im.movement_type = 'sale'
                                    AND julianday((
                                        SELECT MAX(movement_at)
                                         FROM inventory_movements))
                                     - julianday(im.movement_at) <= 90
                                THEN -im.quantity_change
                                ELSE 0
                            END) BETWEEN 1 AND 25
                THEN 1
                ELSE 0
            END AS slow_moving_flag,
            CASE
                WHEN iob.opening_units + COALESCE(SUM(im.quantity_change), 0) > (COALESCE(SUM(CASE
                                    WHEN im.movement_type = 'sale'
                                    THEN -im.quantity_change
                                    ELSE 0
                                END), 0) / 1096.0 * 30)
                THEN 1
                ELSE 0
            END AS excess_flag,
            CASE
                WHEN iob.opening_units + COALESCE(SUM(im.quantity_change), 0) <= p.reorder_point
                THEN 1
                ELSE 0
            END AS low_inventory_flag

        FROM inventory_opening_balances iob

        LEFT JOIN inventory_movements im
            ON iob.product_id = im.product_id
            AND iob.warehouse_id = im.warehouse_id

        JOIN products p
            ON iob.product_id = p.product_id

        GROUP BY
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units,
            p.unit_cost,
            p.reorder_point
    ) ri

    GROUP BY
        ri.warehouse_id
) inventory

ORDER BY
    inventory.warehouse_id;