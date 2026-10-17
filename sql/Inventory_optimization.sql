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