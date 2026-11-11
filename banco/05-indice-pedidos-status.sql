-- Rota GET /pedidos?status=&pagina=: lê a página de um status já na ordem do
-- ORDER BY criado_em DESC, id DESC, e permite contar os pedidos do status pelo índice.
CREATE INDEX idx_pedidos_status_criado_em
    ON pedidos (status, criado_em DESC, id DESC);
