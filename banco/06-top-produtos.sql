-- Rota GET /relatorios/top-produtos: o ranking de produtos por receita é calculado
-- uma vez, quando o banco é criado, em vez de a cada chamada.
-- É a mesma consulta que a rota fazia, sem o LIMIT (o limite continua na rota).
-- Se os pedidos mudarem, recalcular com: REFRESH MATERIALIZED VIEW top_produtos;
CREATE MATERIALIZED VIEW top_produtos AS
SELECT pr.id, pr.nome, pr.categoria,
       sum(i.quantidade) AS unidades,
       sum(i.quantidade * i.preco_unitario_centavos) AS receita_centavos
  FROM itens_pedido i
  JOIN pedidos p ON p.id = i.pedido_id
  JOIN produtos pr ON pr.id = i.produto_id
 WHERE p.status <> 'cancelado'
 GROUP BY pr.id, pr.nome, pr.categoria;

-- Lê os primeiros do ranking já na ordem do ORDER BY receita_centavos DESC, id.
CREATE INDEX idx_top_produtos_receita
    ON top_produtos (receita_centavos DESC, id);

ANALYZE top_produtos;
