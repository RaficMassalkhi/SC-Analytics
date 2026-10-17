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