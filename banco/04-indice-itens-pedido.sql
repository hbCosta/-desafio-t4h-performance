-- Rota GET /clientes/:id/pedidos: busca os itens de um pedido já na ordem do ORDER BY id.
CREATE INDEX idx_itens_pedido_pedido_id
    ON itens_pedido (pedido_id, id);
