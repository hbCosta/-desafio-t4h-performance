-- Rota GET /pedidos?status=&pagina=: o total de pedidos de cada status é contado
-- uma vez, quando o banco é criado, em vez de a cada chamada.
-- Se os pedidos mudarem, recalcular com: REFRESH MATERIALIZED VIEW pedidos_por_status;
CREATE MATERIALIZED VIEW pedidos_por_status AS
SELECT status, count(*) AS total
  FROM pedidos
 GROUP BY status;

CREATE UNIQUE INDEX idx_pedidos_por_status_status
    ON pedidos_por_status (status);

ANALYZE pedidos_por_status;
