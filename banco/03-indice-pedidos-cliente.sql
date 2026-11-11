CREATE INDEX idx_pedidos_cliente_data
ON pedidos (cliente_id, criado_em DESC, id DESC);
